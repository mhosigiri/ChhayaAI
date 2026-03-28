"""
FastAPI transport: validate body, optional auth, supervisor only, normalize JSON.
"""
from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from typing import Annotated, Any

from dotenv import load_dotenv
from fastapi import FastAPI, Header
from fastapi.responses import JSONResponse

from app.agents.supervisor import process_user_request
from app.auth.validator import validate_authorization
from app.memory.redis_client import check_memory_connection
from app.schemas.request_response import CommonRequest, CommonResponse

logger = logging.getLogger(__name__)

_SERVICE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(_SERVICE_ROOT, ".env"))
load_dotenv()

_RESPONSE_KEYS = (
    "status",
    "response_type",
    "chat_message",
    "map_payload",
    "alert_payload",
    "data_payload",
    "ui_actions",
)


@asynccontextmanager
async def _lifespan(_app: FastAPI):
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s %(name)s %(message)s",
    )
    logger.info("application startup")
    check_memory_connection()
    yield
    logger.info("application shutdown")


def health_check() -> dict[str, str]:
    return {"status": "ok"}


def validate_request_data(req: CommonRequest) -> tuple[bool, str | None]:
    if len(req.trigger_type) > 128:
        return False, "trigger_type too long"
    if not str(req.user_id).strip():
        return False, "user_id required"
    if not str(req.session_id).strip():
        return False, "session_id required"
    return True, None


def _fallback_envelope(message: str) -> dict[str, Any]:
    return CommonResponse(
        status="error",
        response_type="DATA",
        chat_message=message,
        map_payload=None,
        alert_payload=None,
        data_payload=None,
        ui_actions=["SHOW_ERROR"],
    ).model_dump(mode="json")


def normalize_supervisor_response(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        logger.error("supervisor returned non-dict")
        return _fallback_envelope("Service returned an invalid payload.")
    payload: dict[str, Any] = {k: raw.get(k) for k in _RESPONSE_KEYS}
    if payload.get("ui_actions") is None:
        payload["ui_actions"] = []
    if not isinstance(payload["ui_actions"], list):
        payload["ui_actions"] = []
    try:
        model = CommonResponse.model_validate(payload)
        return model.model_dump(mode="json")
    except Exception:
        logger.exception("response normalization failed")
        return _fallback_envelope("Service response could not be normalized.")


def handle_request(req: CommonRequest, authorization: str | None) -> tuple[int, dict[str, Any]]:
    logger.info("request start session_id=%s trigger=%s", req.session_id, req.trigger_type)

    ok, err = validate_request_data(req)
    if not ok:
        logger.warning("request validation failed: %s", err)
        return 400, _fallback_envelope(err or "Invalid request")

    auth_ok, auth_err = validate_authorization(authorization)
    if not auth_ok:
        logger.warning("auth failed: %s", auth_err)
        body = CommonResponse(
            status="error",
            response_type="DATA",
            chat_message=auth_err or "Unauthorized",
            map_payload=None,
            alert_payload=None,
            data_payload=None,
            ui_actions=["SHOW_ERROR"],
        ).model_dump(mode="json")
        return 401, body

    try:
        raw = process_user_request(
            user_id=req.user_id,
            session_id=req.session_id,
            query=req.query,
            lat=req.lat,
            lon=req.lon,
            trigger_type=req.trigger_type,
        )
    except Exception:
        logger.exception("supervisor raised")
        return 500, _fallback_envelope("Request could not be processed.")

    out = normalize_supervisor_response(raw)
    logger.info(
        "request end session_id=%s response_type=%s",
        req.session_id,
        out.get("response_type"),
    )
    return 200, out


def create_app() -> FastAPI:
    app = FastAPI(title="Chhaya AI Agent Service", lifespan=_lifespan)

    @app.get("/health")
    async def _health():
        return health_check()

    @app.post("/v1/chat")
    async def _chat(
        body: CommonRequest,
        authorization: Annotated[str | None, Header()] = None,
    ):
        code, payload = handle_request(body, authorization)
        return JSONResponse(status_code=code, content=payload)

    return app


app = create_app()
