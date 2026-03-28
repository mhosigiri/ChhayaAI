import logging
import math
from typing import Any

from app.agents import llm_client
from app.agents.alert_agent import handle_alert_task
from app.agents.data_agent import handle_data_task
from app.agents.map_agent import handle_map_task
from app.memory.redis_client import get_chat_history, save_chat_message

logger = logging.getLogger(__name__)

CONTRACT_KEYS = (
    "status",
    "response_type",
    "chat_message",
    "map_payload",
    "alert_payload",
    "data_payload",
    "ui_actions",
)

_WHITELIST_INTENTS = frozenset({"ALERT", "MAP", "DATA"})
_EMERGENCY_TRIGGERS = frozenset({"EMERGENCY_BUTTON", "EMERGENCY"})


def sanitize_query(query: Any) -> str:
    if query is None:
        return ""
    text = str(query).strip()
    if len(text) > 8000:
        text = text[:8000]
        logger.warning("supervisor: query truncated to 8000 chars")
    return text


def sanitize_trigger_type(trigger_type: Any) -> str:
    if trigger_type is None:
        return "CHAT"
    t = str(trigger_type).strip().upper().replace(" ", "_")
    if t in _EMERGENCY_TRIGGERS:
        return "EMERGENCY_BUTTON"
    return t or "CHAT"


def safe_load_history(session_id: Any) -> list:
    sid = str(session_id).strip() if session_id is not None else ""
    if not sid:
        logger.info("supervisor: empty session_id, skipping history load")
        return []
    try:
        history = get_chat_history(sid)
        if history is None:
            return []
        if isinstance(history, list):
            return history
        logger.warning("supervisor: history not a list, coercing to empty")
        return []
    except Exception as e:
        logger.exception("supervisor: history load failed session_id=%s: %s", sid, e)
        return []


def normalize_intent(raw_intent: Any) -> str:
    if raw_intent is None:
        return "DATA"
    s = str(raw_intent).strip().upper()
    if s in _WHITELIST_INTENTS:
        return s
    if "ALERT" in s:
        return "ALERT"
    if "MAP" in s:
        return "MAP"
    if "DATA" in s:
        return "DATA"
    return "DATA"


def is_valid_location(lat: Any, lon: Any) -> bool:
    try:
        la = float(lat)
        lo = float(lon)
    except (TypeError, ValueError):
        return False
    if not (math.isfinite(la) and math.isfinite(lo)):
        return False
    return -90.0 <= la <= 90.0 and -180.0 <= lo <= 180.0


def normalize_agent_response(agent_response: Any) -> dict:
    empty = {
        "status": "error",
        "response_type": "DATA",
        "chat_message": "Service unavailable.",
        "map_payload": None,
        "alert_payload": None,
        "data_payload": None,
        "ui_actions": [],
    }
    if not isinstance(agent_response, dict):
        return dict(empty)
    out = {**empty}
    for k in CONTRACT_KEYS:
        if k in agent_response:
            out[k] = agent_response[k]
    return out


def build_supervisor_success_response(
    *,
    response_type: str,
    chat_message: str,
    map_payload: Any = None,
    alert_payload: Any = None,
    data_payload: Any = None,
    ui_actions: list | None = None,
) -> dict:
    return {
        "status": "success",
        "response_type": response_type,
        "chat_message": chat_message or "",
        "map_payload": map_payload,
        "alert_payload": alert_payload,
        "data_payload": data_payload,
        "ui_actions": list(ui_actions or []),
    }


def build_supervisor_error_response(
    message: str,
    response_type: str = "DATA",
    *,
    map_payload: Any = None,
    alert_payload: Any = None,
    data_payload: Any = None,
    ui_actions: list | None = None,
) -> dict:
    return {
        "status": "error",
        "response_type": response_type,
        "chat_message": message,
        "map_payload": map_payload,
        "alert_payload": alert_payload,
        "data_payload": data_payload,
        "ui_actions": list(ui_actions or []),
    }


def extract_nearby_helpers_from_map(map_norm: dict | None) -> list | None:
    if not map_norm or not isinstance(map_norm, dict):
        return None
    mp = map_norm.get("map_payload")
    if not isinstance(mp, dict):
        return None
    matched = mp.get("matched_user")
    if not isinstance(matched, dict):
        return None
    if matched.get("user_id") is None:
        return None
    return [matched]


class SupervisorRouter:
    """Routes to EMERGENCY | ALERT | MAP | DATA (classifier never sets EMERGENCY)."""

    def __init__(self, llm_module=llm_client):
        self._llm = llm_module

    def route(self, query: str, trigger_type: str) -> str:
        if trigger_type == "EMERGENCY_BUTTON":
            logger.info("supervisor.route: EMERGENCY (trigger)")
            return "EMERGENCY"
        try:
            raw = self._llm.classify_intent(query)
        except Exception as e:
            logger.exception("supervisor.route: classifier failed, default DATA: %s", e)
            return "DATA"
        intent = normalize_intent(raw)
        logger.info("supervisor.route: raw=%r normalized=%s", raw, intent)
        return intent


_default_router = SupervisorRouter()


def _run_map_agent(**kwargs) -> dict | None:
    try:
        raw = handle_map_task(**kwargs)
        return normalize_agent_response(raw)
    except Exception as e:
        logger.exception("supervisor: map_agent failed: %s", e)
        return None


def _run_alert_agent(**kwargs) -> dict | None:
    try:
        raw = handle_alert_task(**kwargs)
        return normalize_agent_response(raw)
    except Exception as e:
        logger.exception("supervisor: alert_agent failed: %s", e)
        return None


def _run_data_agent(query: str, history: list) -> dict | None:
    try:
        raw = handle_data_task(query, chat_history=history, system_context=None)
        return normalize_agent_response(raw)
    except Exception as e:
        logger.exception("supervisor: data_agent failed: %s", e)
        return None


def _merge_emergency_response(
    map_norm: dict | None,
    alert_norm: dict | None,
) -> dict:
    map_ok = map_norm is not None
    alert_ok = alert_norm is not None

    map_p = map_norm.get("map_payload") if map_norm else None
    alert_p = alert_norm.get("alert_payload") if alert_norm else None

    if map_ok and not alert_ok:
        alert_p = {"error": "alert_dispatch_unavailable", "logged": False}
        logger.warning("supervisor: emergency — map ok, alert failed")

    ui: list[str] = ["OPEN_MAP_SCREEN", "SHOW_EMERGENCY_BANNER"]
    if alert_norm and isinstance(alert_norm.get("ui_actions"), list):
        for a in alert_norm["ui_actions"]:
            if a not in ui:
                ui.append(a)

    parts: list[str] = []
    if map_ok:
        cm = map_norm.get("chat_message")
        if cm:
            parts.append(str(cm))
    if alert_ok:
        cm = alert_norm.get("chat_message")
        if cm:
            parts.append(str(cm))
    chat_message = " ".join(parts).strip()

    if not map_ok and not alert_ok:
        logger.error("supervisor: emergency — map and alert both failed")
        return build_supervisor_error_response(
            "Emergency request could not be processed.",
            response_type="EMERGENCY_FLOW",
            map_payload=None,
            alert_payload=None,
            ui_actions=["SHOW_ERROR", "OPEN_MAP_SCREEN"],
        )

    if not chat_message:
        chat_message = "Emergency flow completed."

    return build_supervisor_success_response(
        response_type="EMERGENCY_FLOW",
        chat_message=chat_message,
        map_payload=map_p,
        alert_payload=alert_p,
        data_payload=None,
        ui_actions=ui,
    )


def process_user_request(user_id, session_id, query, lat, lon, trigger_type):
    q = sanitize_query(query)
    trig = sanitize_trigger_type(trigger_type)
    logger.info(
        "supervisor: request user_id=%s session_id=%s trigger=%s query_len=%s",
        user_id,
        session_id,
        trig,
        len(q),
    )

    history = safe_load_history(session_id)

    if trig == "EMERGENCY_BUTTON":
        if not is_valid_location(lat, lon):
            logger.warning("supervisor: EMERGENCY blocked — invalid location")
            return build_supervisor_error_response(
                "Location is required for emergency assistance. Enable location and try again.",
                response_type="EMERGENCY_FLOW",
                ui_actions=["SHOW_ERROR", "OPEN_MAP_SCREEN"],
            )
        map_norm = _run_map_agent(
            user_id=user_id,
            session_id=session_id,
            query=q or "emergency",
            lat=float(lat),
            lon=float(lon),
            emergency=True,
            request_mode="VICTIM",
        )
        nearby = extract_nearby_helpers_from_map(map_norm)
        alert_norm = _run_alert_agent(
            user_id=user_id,
            session_id=session_id,
            query="Emergency button pressed",
            lat=float(lat),
            lon=float(lon),
            emergency=True,
            nearby_helpers=nearby,
        )
        return _merge_emergency_response(map_norm, alert_norm)

    intent = _default_router.route(q, trig)

    if intent == "MAP":
        if not is_valid_location(lat, lon):
            logger.warning("supervisor: MAP blocked — invalid location")
            return build_supervisor_error_response(
                "Location is required for map matching. Enable location and try again.",
                response_type="MAP",
                ui_actions=["SHOW_ERROR", "OPEN_MAP_SCREEN"],
            )
        agent_out = _run_map_agent(
            user_id=user_id,
            session_id=session_id,
            query=q,
            lat=float(lat),
            lon=float(lon),
            emergency=False,
            request_mode="VICTIM",
        )
        if agent_out is None:
            return build_supervisor_error_response(
                "Map service unavailable. Try again shortly.",
                response_type="MAP",
                ui_actions=["SHOW_ERROR"],
            )
        return build_supervisor_success_response(
            response_type=agent_out.get("response_type") or "MAP",
            chat_message=agent_out.get("chat_message") or "",
            map_payload=agent_out.get("map_payload"),
            alert_payload=None,
            data_payload=None,
            ui_actions=agent_out.get("ui_actions") or [],
        )

    if intent == "ALERT":
        if not is_valid_location(lat, lon):
            logger.warning("supervisor: ALERT blocked — invalid location")
            return build_supervisor_error_response(
                "Location is required to send an alert. Enable location and try again.",
                response_type="ALERT",
                ui_actions=["SHOW_ERROR", "OPEN_ALERT_SCREEN"],
            )
        agent_out = _run_alert_agent(
            user_id=user_id,
            session_id=session_id,
            query=q,
            lat=float(lat),
            lon=float(lon),
            emergency=False,
            nearby_helpers=None,
        )
        if agent_out is None:
            return build_supervisor_error_response(
                "Alert service unavailable. Try again shortly.",
                response_type="ALERT",
                ui_actions=["SHOW_ERROR"],
            )
        return build_supervisor_success_response(
            response_type=agent_out.get("response_type") or "ALERT",
            chat_message=agent_out.get("chat_message") or "",
            map_payload=None,
            alert_payload=agent_out.get("alert_payload"),
            data_payload=None,
            ui_actions=agent_out.get("ui_actions") or [],
        )

    agent_out = _run_data_agent(q, history)
    if agent_out is None:
        return build_supervisor_error_response(
            "Chat service unavailable. Try again shortly.",
            response_type="DATA",
            ui_actions=["SHOW_ERROR", "SHOW_CHAT_MESSAGE"],
        )
    sid = str(session_id).strip() if session_id is not None else ""
    if sid and q.strip():
        save_chat_message(sid, "user", q)
    reply = agent_out.get("chat_message") or ""
    if sid and reply.strip():
        save_chat_message(sid, "assistant", reply)
    return build_supervisor_success_response(
        response_type=agent_out.get("response_type") or "CHAT",
        chat_message=reply,
        map_payload=None,
        alert_payload=None,
        data_payload=agent_out.get("data_payload"),
        ui_actions=agent_out.get("ui_actions") or [],
    )
