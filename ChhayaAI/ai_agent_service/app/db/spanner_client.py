"""
Spanner / graph access layer. Lives under app/db (separate from app/memory Redis).
"""
from __future__ import annotations

import logging
import math
import uuid
from typing import Any

from app.config import (
    get_spanner_database_id,
    get_spanner_instance_id,
    get_spanner_project_id,
)

logger = logging.getLogger(__name__)

try:
    from google.cloud import spanner

    _HAS_SPANNER = True
except ImportError:
    spanner = None  # type: ignore[assignment, misc]
    _HAS_SPANNER = False


class SpannerClient:
    def __init__(self) -> None:
        self._project_id = get_spanner_project_id()
        self._instance_id = get_spanner_instance_id()
        self._database_id = get_spanner_database_id()
        self._client: Any = None
        self._database: Any = None
        self._disabled = not (
            _HAS_SPANNER and self._project_id and self._instance_id and self._database_id
        )
        if self._disabled:
            logger.warning(
                "SpannerClient: disabled (missing SDK or SPANNER_PROJECT_ID / INSTANCE / DATABASE)"
            )

    def verify_connection(self) -> bool:
        if self._disabled:
            return False
        try:
            self._ensure_database()
            return self._database is not None
        except Exception as e:
            self._handle_db_error(e, "verify_connection")
            return False

    def _ensure_database(self) -> None:
        if self._database is not None or self._disabled:
            return
        self._client = spanner.Client(project=self._project_id)
        inst = self._client.instance(self._instance_id)
        self._database = inst.database(self._database_id)

    def execute_graph_query(self, query: str) -> list[dict[str, Any]]:
        q = (query or "").strip()
        if not q:
            logger.warning("execute_graph_query: empty query")
            return []
        if self._disabled:
            return []
        try:
            self._ensure_database()
            rows = self._run_query(q)
            return self._normalize_rows(rows)
        except Exception as e:
            self._handle_db_error(e, "execute_graph_query")
            return []

    def update_user_location(
        self,
        user_id: str,
        lat: float,
        lon: float,
        role: str | None = None,
    ) -> dict[str, Any]:
        uid = self._validate_user_id(user_id)
        if not uid:
            return {"ok": False, "error": "invalid user_id"}
        if not self._validate_lat_lon(lat, lon):
            return {"ok": False, "error": "invalid coordinates"}
        if self._disabled:
            return {"ok": False, "error": "spanner_disabled"}
        try:
            self._ensure_database()
            logger.debug("update_user_location stub user_id=%s role=%s", uid, role)
            return {"ok": True, "user_id": uid}
        except Exception as e:
            self._handle_db_error(e, "update_user_location")
            return {"ok": False, "error": str(e)}

    def get_nearby_helpers(
        self,
        lat: float,
        lon: float,
        radius: float | None = None,
        limit: int | None = None,
        exclude_user_id: str | None = None,
    ) -> list[dict[str, Any]]:
        if not self._validate_lat_lon(lat, lon):
            return []
        if self._disabled:
            return []
        lim = min(limit or 10, 100)
        try:
            self._ensure_database()
            logger.debug(
                "get_nearby_helpers stub lat=%s lon=%s radius=%s limit=%s exclude=%s",
                lat,
                lon,
                radius,
                lim,
                exclude_user_id,
            )
            return []
        except Exception as e:
            self._handle_db_error(e, "get_nearby_helpers")
            return []

    def create_alert_record(
        self,
        *,
        user_id: str,
        session_id: str,
        alert_type: str,
        priority: str,
        status: str = "ACTIVE",
        lat: float | None = None,
        lon: float | None = None,
        message: str | None = None,
    ) -> dict[str, Any] | None:
        uid = self._validate_user_id(user_id)
        sid = (session_id or "").strip()
        if not uid or not sid:
            logger.warning("create_alert_record: missing user_id or session_id")
            return None
        if lat is not None and lon is not None and not self._validate_lat_lon(lat, lon):
            return None
        if self._disabled:
            return {
                "alert_id": str(uuid.uuid4()),
                "user_id": uid,
                "session_id": sid,
                "alert_type": alert_type,
                "priority": priority,
                "status": status,
                "lat": lat,
                "lon": lon,
                "message": message,
                "ok": False,
                "error": "spanner_disabled",
            }
        try:
            self._ensure_database()
            aid = str(uuid.uuid4())
            logger.debug("create_alert_record stub alert_id=%s", aid)
            return {
                "alert_id": aid,
                "user_id": uid,
                "session_id": sid,
                "alert_type": alert_type,
                "priority": priority,
                "status": status,
                "lat": lat,
                "lon": lon,
                "message": message,
                "ok": True,
            }
        except Exception as e:
            self._handle_db_error(e, "create_alert_record")
            return None

    def update_alert_status(
        self,
        alert_id: str,
        status: str,
        helpers_notified_count: int | None = None,
    ) -> dict[str, Any]:
        aid = (alert_id or "").strip()
        if not aid:
            return {"ok": False, "error": "invalid alert_id"}
        if self._disabled:
            return {"ok": False, "error": "spanner_disabled"}
        try:
            self._ensure_database()
            logger.debug(
                "update_alert_status stub alert_id=%s status=%s count=%s",
                aid,
                status,
                helpers_notified_count,
            )
            return {"ok": True, "alert_id": aid, "status": status}
        except Exception as e:
            self._handle_db_error(e, "update_alert_status")
            return {"ok": False, "error": str(e)}

    def get_active_alert_for_user(self, user_id: str) -> dict[str, Any] | None:
        uid = self._validate_user_id(user_id)
        if not uid:
            return None
        if self._disabled:
            return None
        try:
            self._ensure_database()
            logger.debug("get_active_alert_for_user stub user_id=%s", uid)
            return None
        except Exception as e:
            self._handle_db_error(e, "get_active_alert_for_user")
            return None

    def _run_query(self, query: str) -> list[Any]:
        if self._database is None:
            return []
        with self._database.snapshot() as snapshot:
            result_set = snapshot.execute_sql(query)
            return list(result_set)

    def _normalize_rows(self, rows: Any) -> list[dict[str, Any]]:
        if not rows:
            return []
        normalized: list[dict[str, Any]] = []
        for row in rows:
            try:
                if isinstance(row, dict):
                    normalized.append(dict(row))
                elif hasattr(row, "keys") and callable(row.keys):
                    normalized.append({k: row[k] for k in row.keys()})
                elif isinstance(row, (list, tuple)):
                    normalized.append({f"col_{i}": v for i, v in enumerate(row)})
                else:
                    normalized.append({"value": row})
            except Exception as e:
                logger.debug("skip malformed row: %s", e)
        return normalized

    def _handle_db_error(self, exc: BaseException, operation: str) -> None:
        logger.exception("spanner %s failed: %s", operation, exc)

    @staticmethod
    def _validate_user_id(user_id: str | None) -> str | None:
        if user_id is None:
            return None
        u = str(user_id).strip()
        if not u or len(u) > 256:
            return None
        return u

    @staticmethod
    def _validate_lat_lon(lat: float, lon: float) -> bool:
        try:
            la = float(lat)
            lo = float(lon)
        except (TypeError, ValueError):
            return False
        if not (math.isfinite(la) and math.isfinite(lo)):
            return False
        return -90.0 <= la <= 90.0 and -180.0 <= lo <= 180.0
