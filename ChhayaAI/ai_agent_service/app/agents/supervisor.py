from app.agents import llm_client
from app.agents.alert_agent import handle_alert_task
from app.agents.map_agent import handle_map_task
from app.agents.data_agent import handle_data_task
from app.database.redis_client import get_chat_history


class SupervisorRouter:
    """Intent routing: EMERGENCY vs MAP vs DATA vs ALERT."""

    def __init__(self, llm_client_module=llm_client):
        self.llm_client = llm_client_module

    def route(self, query: str, trigger_type: str) -> str:
        if trigger_type == "EMERGENCY_BUTTON":
            return "EMERGENCY"

        intent = self.llm_client.classify_intent(query)
        return intent


_default_router = SupervisorRouter()


def process_user_request(user_id, session_id, query, lat, lon, trigger_type):
    """
    The CEO Logic: Decides who works on the request.
    Returns a structured contract for the client (no raw strings).
    """

    # 1. GET CONTEXT: What were we talking about?
    history = get_chat_history(session_id)

    # 2–3. ROUTE: EMERGENCY / MAP / DATA / ALERT
    intent = _default_router.route(query, trigger_type)

    # 4. DELEGATION: The Switchboard
    if intent == "EMERGENCY":
        map_response = handle_map_task(
            user_id=user_id,
            session_id=session_id,
            query=query,
            lat=lat,
            lon=lon,
            emergency=True,
            request_mode="VICTIM",
        )
        nearby_helpers = map_response.get("map_payload", {}) and \
            [map_response["map_payload"]["matched_user"]] \
            if map_response.get("map_payload", {}).get("matched_user") else []
        alert_response = handle_alert_task(
            user_id=user_id,
            session_id=session_id,
            query="Emergency button pressed",
            lat=lat,
            lon=lon,
            emergency=True,
            nearby_helpers=nearby_helpers or None,
        )

        return {
            "status": "success",
            "response_type": "EMERGENCY_FLOW",
            "chat_message": "Emergency help options are shown on the map.",
            "map_payload": map_response.get("map_payload"),
            "alert_payload": alert_response.get("alert_payload"),
            "data_payload": None,
            "ui_actions": ["OPEN_MAP_SCREEN", "SHOW_EMERGENCY_BANNER"],
        }

    if intent == "ALERT":
        return handle_alert_task(
            user_id=user_id,
            session_id=session_id,
            query=query,
            lat=lat,
            lon=lon,
        )

    if intent == "MAP":
        return handle_map_task(
            user_id=user_id,
            session_id=session_id,
            query=query,
            lat=lat,
            lon=lon,
        )

    return handle_data_task(query, history)
