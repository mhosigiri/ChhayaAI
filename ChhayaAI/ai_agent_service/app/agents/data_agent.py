from app.agents.llm_client import get_ai_response

_MAX_HISTORY = 6

_CHAT_SYSTEM_PROMPT = """\
You are Chhaya, a calm and supportive safety companion inside the Chhaya AI app.

RULES:
1. Reply in 1–4 short, clear sentences. Never write essays.
2. Be warm, grounded, and app-aware.
3. If the user sounds scared or stressed, acknowledge it before offering next steps.
4. Guide users toward app features (help button, location sharing) when relevant.
5. Never claim to be emergency services, police, or 911.
6. Never mention internal systems, databases, or agent architecture.
7. Never invent events (notifications sent, helpers found, routes created) unless stated in context.
8. If unsure, give a calm, neutral fallback."""

_FALLBACKS = [
    "I can help explain how the app works or guide you on what to do next.",
    "If you need immediate help, press the help button.",
    "Keep your location on so nearby helpers can find you if needed.",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def prepare_history(chat_history) -> list[dict]:
    if not chat_history:
        return []
    if isinstance(chat_history, str):
        return []
    clean = []
    for item in chat_history:
        if not isinstance(item, dict):
            continue
        role = item.get("role", "")
        content = item.get("content", "")
        if role in ("user", "assistant") and isinstance(content, str) and content.strip():
            clean.append({"role": role, "content": content.strip()})
    return clean[-_MAX_HISTORY:]


def build_data_messages(
    query: str,
    history: list[dict] | None = None,
    system_context: dict | None = None,
) -> list[dict]:
    system_text = _CHAT_SYSTEM_PROMPT
    if system_context:
        relevant = {
            k: v for k, v in system_context.items()
            if k in ("alert_status", "match_status", "user_role", "last_action")
        }
        if relevant:
            system_text += f"\n\nCurrent app state: {relevant}"

    messages = [{"role": "system", "content": system_text}]
    if history:
        messages.extend(history)
    messages.append({"role": "user", "content": query.strip()})
    return messages


def build_data_success_response(chat_message: str, data_payload: dict | None = None) -> dict:
    return {
        "status": "success",
        "response_type": "CHAT",
        "chat_message": chat_message,
        "data_payload": data_payload,
        "ui_actions": ["SHOW_CHAT_MESSAGE"],
    }


def build_data_error_response(message: str) -> dict:
    return {
        "status": "error",
        "response_type": "CHAT",
        "chat_message": message,
        "data_payload": None,
        "ui_actions": ["SHOW_CHAT_MESSAGE"],
    }


def _safe_reply(raw: str | None) -> str:
    if not raw or not raw.strip():
        return _FALLBACKS[0]
    text = raw.strip()
    if any(bad in text.lower() for bad in ("redis", "spanner", "graph query", "agent")):
        return _FALLBACKS[0]
    return text


# ---------------------------------------------------------------------------
# Core handler
# ---------------------------------------------------------------------------

def handle_data_task(
    query: str,
    chat_history=None,
    system_context: dict | None = None,
) -> dict:
    history = prepare_history(chat_history)
    messages = build_data_messages(query, history=history, system_context=system_context)

    user_message = "\n".join(
        m["content"] for m in messages if m["role"] != "system"
    )

    try:
        raw = get_ai_response(user_message)
        reply = _safe_reply(raw)
    except Exception:
        reply = _FALLBACKS[0]

    return build_data_success_response(
        chat_message=reply,
        data_payload={"history_used": bool(history), "context_used": bool(system_context)},
    )
