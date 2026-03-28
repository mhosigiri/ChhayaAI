"""
Session chat history in Redis. All connection settings come from app.config (env).
"""
from __future__ import annotations

import json
import logging
from typing import Any

from app.config import (
    get_redis_db,
    get_redis_history_limit,
    get_redis_host,
    get_redis_password,
    get_redis_port,
)

logger = logging.getLogger(__name__)

try:
    from redis import Redis
except ImportError:  # pragma: no cover
    Redis = None  # type: ignore[misc, assignment]


class RedisClient:
    """Owns Redis connection, list storage for chat:{session_id}, and history shaping."""

    def __init__(self) -> None:
        self._host = get_redis_host()
        self._port = get_redis_port()
        self._password = get_redis_password()
        self._db = get_redis_db()
        self._history_limit = get_redis_history_limit()
        self._redis: Any = None

    def _ensure_redis(self) -> Any | None:
        if not self._host:
            return None
        if Redis is None:
            logger.error("redis package not installed; pip install redis")
            return None
        if self._redis is None:
            try:
                self._redis = Redis(
                    host=self._host,
                    port=self._port,
                    password=self._password,
                    db=self._db,
                    decode_responses=False,
                    socket_connect_timeout=5.0,
                    socket_timeout=5.0,
                )
            except Exception as e:
                logger.exception("redis_client: failed to create client: %s", e)
                self._redis = None
        return self._redis

    def check_connection(self) -> bool:
        if not self._host:
            logger.info("redis_client: REDIS_HOST unset; session memory disabled")
            return True
        r = self._ensure_redis()
        if r is None:
            logger.error("redis_client: check_connection — no client")
            return False
        try:
            r.ping()
            logger.info("redis_client: ping ok host=%s port=%s", self._host, self._port)
            return True
        except Exception as e:
            logger.error("redis_client: ping failed: %s", e)
            return False

    def _build_session_key(self, session_id: str) -> str:
        return f"chat:{session_id}"

    def _serialize_message(self, role: str, content: str) -> str:
        return json.dumps({"role": role, "content": content}, separators=(",", ":"))

    def _deserialize_message(self, raw: Any) -> dict[str, str] | None:
        if raw is None:
            return None
        if isinstance(raw, (bytes, bytearray)):
            try:
                text = raw.decode("utf-8", errors="replace")
            except Exception:
                return None
        elif isinstance(raw, str):
            text = raw
        else:
            return None
        text = text.strip()
        if not text:
            return None
        try:
            obj = json.loads(text)
        except (json.JSONDecodeError, TypeError, ValueError):
            return None
        if not isinstance(obj, dict):
            return None
        role = obj.get("role")
        content = obj.get("content")
        if role not in ("user", "assistant"):
            return None
        if not isinstance(content, str) or not content.strip():
            return None
        return {"role": role, "content": content.strip()}

    def _normalize_history(self, messages: list[Any]) -> list[dict[str, str]]:
        out: list[dict[str, str]] = []
        for raw in messages:
            item = self._deserialize_message(raw)
            if item is not None:
                out.append(item)
        return out

    def save_chat_message(self, session_id: str, role: str, content: str) -> bool:
        sid = (session_id or "").strip()
        if not sid:
            logger.warning("redis_client: save rejected — empty session_id")
            return False
        if role not in ("user", "assistant"):
            logger.warning("redis_client: save rejected — invalid role=%r", role)
            return False
        if not isinstance(content, str) or not content.strip():
            logger.warning("redis_client: save rejected — empty content")
            return False
        r = self._ensure_redis()
        if r is None:
            logger.error("redis_client: save failed — redis unavailable")
            return False
        key = self._build_session_key(sid)
        payload = self._serialize_message(role, content.strip())
        try:
            r.rpush(key, payload)
            r.ltrim(key, -self._history_limit, -1)
            logger.info(
                "redis_client: saved message session_id=%s role=%s len=%s trimmed_to=%s",
                sid,
                role,
                len(content),
                self._history_limit,
            )
            return True
        except Exception as e:
            logger.error("redis_client: save failed session_id=%s: %s", sid, e)
            return False

    def get_chat_history(self, session_id: str) -> list[dict[str, str]]:
        sid = (session_id or "").strip()
        if not sid:
            return []
        r = self._ensure_redis()
        if r is None:
            return []
        key = self._build_session_key(sid)
        try:
            raw_list = r.lrange(key, 0, -1)
            logger.info(
                "redis_client: fetched history session_id=%s count=%s",
                sid,
                len(raw_list) if raw_list else 0,
            )
        except Exception as e:
            logger.error("redis_client: fetch failed session_id=%s: %s", sid, e)
            return []
        if not raw_list:
            return []
        return self._normalize_history(list(raw_list))

    def clear_chat_history(self, session_id: str) -> bool:
        sid = (session_id or "").strip()
        if not sid:
            logger.warning("redis_client: clear rejected — empty session_id")
            return False
        r = self._ensure_redis()
        if r is None:
            logger.error("redis_client: clear failed — redis unavailable")
            return False
        key = self._build_session_key(sid)
        try:
            r.delete(key)
            logger.info("redis_client: cleared history session_id=%s", sid)
            return True
        except Exception as e:
            logger.error("redis_client: clear failed session_id=%s: %s", sid, e)
            return False


_client: RedisClient | None = None


def _singleton() -> RedisClient:
    global _client
    if _client is None:
        _client = RedisClient()
    return _client


def check_memory_connection() -> bool:
    """Ping Redis once; safe when REDIS_HOST is unset (reports ok, memory off)."""
    return _singleton().check_connection()


def get_chat_history(session_id: str) -> list[dict[str, str]]:
    return _singleton().get_chat_history(session_id)


def save_chat_message(session_id: str, role: str, content: str) -> bool:
    return _singleton().save_chat_message(session_id, role, content)


def clear_chat_history(session_id: str) -> bool:
    return _singleton().clear_chat_history(session_id)
