from app.agents.llm_client import get_ai_response


def handle_data_task(query: str, history: list | str | None) -> dict:
    """
    General chat / info using session history context.
    """
    history = history or []
    context_hint = (
        f"\n\nRecent conversation context:\n{history!s}"
        if history
        else ""
    )
    user_message = f"{query}{context_hint}"
    reply = get_ai_response(user_message)

    return {
        "status": "success",
        "response_type": "DATA",
        "chat_message": reply,
        "map_payload": None,
        "alert_payload": None,
        "data_payload": {"reply": reply, "history_used": bool(history)},
        "ui_actions": [],
    }
