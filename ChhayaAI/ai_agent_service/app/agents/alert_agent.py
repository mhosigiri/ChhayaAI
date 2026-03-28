import uuid
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# DB / push adapter stubs — wire to real services when ready
# ---------------------------------------------------------------------------

def _get_open_alert(user_id: str, session_id: str) -> dict | None:
    # TODO: replace with app.db.spanner_client.SpannerClient().get_active_alert_for_user(user_id)
    # Open states: ACTIVE, DISPATCHED, NO_HELPER_FOUND
    return None


def _save_alert(alert: dict) -> dict:
    # TODO: replace with app.db.spanner_client (persist alert)
    return alert


def _send_push_to_helper(payload: dict) -> bool:
    # TODO: replace with app.services.push_client.send(payload)
    return True


# ---------------------------------------------------------------------------
# Classification helpers
# ---------------------------------------------------------------------------

_MEDICAL_SIGNALS = ("injured", "hurt", "bleeding", "heart", "unconscious", "fainted", "sick")
_PANIC_SIGNALS = ("panic", "can't breathe", "shaking", "overwhelmed", "freaking out")
_SAFETY_SIGNALS = ("unsafe", "danger", "threatened", "being followed", "attacked", "stalked")
_EMERGENCY_SIGNALS = ("emergency", "911", "critical", "dying", "life", "help me now")
_URGENT_SIGNALS = ("urgent", "asap", "immediately", "right now", "hurry", "quickly")


def detect_alert_type(query: str, emergency: bool = False) -> str:
    if emergency:
        return "emergency_help"
    q = query.lower()
    if any(s in q for s in _EMERGENCY_SIGNALS):
        return "emergency_help"
    if any(s in q for s in _MEDICAL_SIGNALS):
        return "medical"
    if any(s in q for s in _PANIC_SIGNALS):
        return "panic"
    if any(s in q for s in _SAFETY_SIGNALS):
        return "safety"
    return "general_help"


def detect_priority(query: str, emergency: bool = False) -> str:
    if emergency:
        return "high"
    q = query.lower()
    if any(s in q for s in _EMERGENCY_SIGNALS + _URGENT_SIGNALS):
        return "high"
    if any(s in q for s in _SAFETY_SIGNALS + _MEDICAL_SIGNALS + _PANIC_SIGNALS):
        return "medium"
    return "low"


def build_alert_message(query: str, alert_type: str, priority: str) -> str:
    if priority == "high":
        return f"High-priority {alert_type} alert raised. Help is being dispatched."
    if priority == "medium":
        return f"{alert_type.replace('_', ' ').title()} alert created. Searching for nearby help."
    return "Your alert has been logged. Help will reach you when available."


# ---------------------------------------------------------------------------
# Alert lifecycle
# ---------------------------------------------------------------------------

def create_or_update_alert(
    user_id: str,
    session_id: str,
    alert_type: str,
    priority: str,
    lat: float | None = None,
    lon: float | None = None,
) -> dict:
    now = datetime.now(timezone.utc).isoformat()

    existing = _get_open_alert(user_id, session_id)
    if existing:
        existing.update({
            "alert_type": alert_type,
            "priority": priority,
            "lat": lat,
            "lon": lon,
            "updated_at": now,
        })
        return _save_alert(existing)

    alert = {
        "alert_id": str(uuid.uuid4()),
        "user_id": user_id,
        "session_id": session_id,
        "alert_type": alert_type,
        "priority": priority,
        "status": "ACTIVE",
        "lat": lat,
        "lon": lon,
        "created_at": now,
        "updated_at": now,
    }
    return _save_alert(alert)


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

def build_helper_notification_payload(alert: dict, helper: dict) -> dict:
    return {
        "alert_id": alert["alert_id"],
        "alert_type": alert["alert_type"],
        "priority": alert["priority"],
        "victim_user_id": alert["user_id"],
        "victim_lat": alert.get("lat"),
        "victim_lon": alert.get("lon"),
        "helper_user_id": helper.get("user_id"),
        "message": f"Someone nearby needs {alert['alert_type'].replace('_', ' ')} help. Can you respond?",
    }


def dispatch_help_notifications(alert: dict, nearby_helpers: list) -> int:
    count = 0
    for helper in nearby_helpers:
        payload = build_helper_notification_payload(alert, helper)
        if _send_push_to_helper(payload):
            count += 1
    return count


# ---------------------------------------------------------------------------
# Response builders
# ---------------------------------------------------------------------------

def build_alert_payload(alert: dict, notified_helpers: int = 0) -> dict:
    return {
        "alert_id": alert.get("alert_id"),
        "user_id": alert.get("user_id"),
        "session_id": alert.get("session_id"),
        "alert_type": alert.get("alert_type"),
        "priority": alert.get("priority"),
        "status": alert.get("status"),
        "message": alert.get("message", ""),
        "lat": alert.get("lat"),
        "lon": alert.get("lon"),
        "notified_helper_count": notified_helpers,
        "created_at": alert.get("created_at"),
        "updated_at": alert.get("updated_at"),
    }


def build_error_response(message: str) -> dict:
    return {
        "status": "error",
        "response_type": "ALERT",
        "chat_message": message,
        "alert_payload": None,
        "ui_actions": ["SHOW_ERROR"],
    }


def _ui_actions_for_status(status: str) -> list[str]:
    if status == "DISPATCHED":
        return ["OPEN_ALERT_SCREEN", "SHOW_ALERT_CREATED", "SHOW_HELPERS_NOTIFIED"]
    if status == "NO_HELPER_FOUND":
        return ["OPEN_ALERT_SCREEN", "SHOW_ALERT_CREATED", "SHOW_SEARCHING_STATUS"]
    return ["OPEN_ALERT_SCREEN", "SHOW_ALERT_CREATED"]


# ---------------------------------------------------------------------------
# Core handler
# ---------------------------------------------------------------------------

def handle_alert_task(
    user_id: str | int,
    session_id: str,
    query: str,
    lat: float | None = None,
    lon: float | None = None,
    emergency: bool = False,
    nearby_helpers: list | None = None,
) -> dict:
    user_id = str(user_id)

    alert_type = detect_alert_type(query, emergency=emergency)
    priority = detect_priority(query, emergency=emergency)
    message = build_alert_message(query, alert_type, priority)

    alert = create_or_update_alert(user_id, session_id, alert_type, priority, lat, lon)
    alert["message"] = message

    notified = 0
    if nearby_helpers:
        notified = dispatch_help_notifications(alert, nearby_helpers)
        alert["status"] = "DISPATCHED" if notified > 0 else "NO_HELPER_FOUND"
    elif alert["status"] == "ACTIVE":
        alert["status"] = "NO_HELPER_FOUND" if not nearby_helpers else "ACTIVE"

    _save_alert(alert)

    return {
        "status": "success",
        "response_type": "ALERT",
        "chat_message": message,
        "alert_payload": build_alert_payload(alert, notified_helpers=notified),
        "ui_actions": _ui_actions_for_status(alert["status"]),
    }
