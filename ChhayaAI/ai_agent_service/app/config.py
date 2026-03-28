"""Central env-backed settings (no secrets in repo)."""
from __future__ import annotations

import os

from dotenv import load_dotenv

_SERVICE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(_SERVICE_ROOT, ".env"))
load_dotenv()

_raw_creds = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
if _raw_creds and not os.path.isabs(_raw_creds):
    _resolved = os.path.normpath(os.path.join(_SERVICE_ROOT, _raw_creds))
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = _resolved

GOOGLE_APPLICATION_CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS") or None


def get_google_application_credentials() -> str | None:
    """Absolute path to the service account JSON, or None if unset."""
    return GOOGLE_APPLICATION_CREDENTIALS


def get_spanner_project_id() -> str:
    return os.getenv("SPANNER_PROJECT_ID", "").strip()


def get_spanner_instance_id() -> str:
    return os.getenv("SPANNER_INSTANCE_ID", "").strip()


def get_spanner_database_id() -> str:
    return os.getenv("SPANNER_DATABASE_ID", "").strip()


def get_redis_host() -> str:
    return os.getenv("REDIS_HOST", "").strip()


def get_redis_port() -> int:
    raw = os.getenv("REDIS_PORT", "6379").strip()
    try:
        p = int(raw)
        return p if 0 < p < 65536 else 6379
    except ValueError:
        return 6379


def get_redis_password() -> str | None:
    p = os.getenv("REDIS_PASSWORD", "")
    return p if p.strip() else None


def get_redis_db() -> int:
    raw = os.getenv("REDIS_DB", "0").strip()
    try:
        d = int(raw)
        return d if d >= 0 else 0
    except ValueError:
        return 0


def get_redis_history_limit() -> int:
    raw = os.getenv("REDIS_HISTORY_LIMIT", "50").strip()
    try:
        n = int(raw)
        return max(1, min(n, 10_000))
    except ValueError:
        return 50


def auth_required() -> bool:
    return os.getenv("AUTH_REQUIRED", "").strip().lower() in ("1", "true", "yes")
