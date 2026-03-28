import uuid
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# DB adapter stubs — wire to real Spanner/Redis client when ready
# ---------------------------------------------------------------------------

def _execute_query(gql: str) -> list:
    # TODO: replace with app.db.spanner_client.SpannerClient().execute_graph_query(gql)
    return []


def _upsert_live_user(user_id, lat, lon, role, session_id) -> None:
    # TODO: replace with app.db.spanner_client.SpannerClient().update_user_location(...)
    pass


def _fetch_match(victim_id: str, helper_id: str) -> dict | None:
    # TODO: replace with app.db.spanner_client (match persistence)
    return None


def _create_match(victim_id: str, helper_id: str, priority: int = 1) -> str:
    # TODO: replace with app.db.spanner_client (create match)
    return str(uuid.uuid4())


# ---------------------------------------------------------------------------
# Intent classification
# ---------------------------------------------------------------------------

_HELPER_SIGNALS = ("i can help", "i'll help", "helping", "assist", "responder")
_VICTIM_SIGNALS = ("help me", "i need help", "unsafe", "danger", "emergency", "scared")


def classify_match_type(
    query: str, emergency: bool = False, request_mode: str = "VICTIM"
) -> str:
    if emergency:
        return "FIND_NEARBY_HELPERS" if request_mode != "HELPER" else "FIND_NEARBY_VICTIMS"

    q = query.lower()
    if request_mode == "HELPER" or any(s in q for s in _HELPER_SIGNALS):
        return "FIND_NEARBY_VICTIMS"
    if request_mode == "VICTIM" or any(s in q for s in _VICTIM_SIGNALS):
        return "FIND_NEARBY_HELPERS"
    return "FIND_NEARBY_HELPERS"


# ---------------------------------------------------------------------------
# Location persistence
# ---------------------------------------------------------------------------

def save_live_location(
    user_id: str, lat: float, lon: float, role: str, session_id: str
) -> None:
    _upsert_live_user(user_id, lat, lon, role, session_id)


# ---------------------------------------------------------------------------
# GQL query builders
# ---------------------------------------------------------------------------

_FRESHNESS_MINUTES = 5


def build_find_helpers_query(lat: float, lon: float, user_id: str) -> str:
    return f"""
    GRAPH LiveUserGraph
    MATCH (h:LiveUser)
    WHERE h.role = 'HELPER'
      AND h.is_active = TRUE
      AND h.help_status = 'AVAILABLE'
      AND h.user_id != '{user_id}'
      AND h.last_seen_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {_FRESHNESS_MINUTES} MINUTE)
    RETURN h.user_id, h.lat, h.lon, h.last_seen_at
    ORDER BY DISTANCE(h, STRUCT(lat: {lat}, lon: {lon})) ASC
    LIMIT 1
    """


def build_find_victims_query(lat: float, lon: float, user_id: str) -> str:
    return f"""
    GRAPH LiveUserGraph
    MATCH (v:LiveUser)
    WHERE v.role = 'VICTIM'
      AND v.is_active = TRUE
      AND v.help_status = 'SEARCHING'
      AND v.user_id != '{user_id}'
      AND v.last_seen_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL {_FRESHNESS_MINUTES} MINUTE)
    RETURN v.user_id, v.lat, v.lon, v.last_seen_at
    ORDER BY DISTANCE(v, STRUCT(lat: {lat}, lon: {lon})) ASC
    LIMIT 1
    """


def build_track_user_query(user_id: str, matched_user_id: str) -> str:
    return f"""
    GRAPH LiveUserGraph
    MATCH (a:LiveUser {{user_id: '{user_id}'}}), (b:LiveUser {{user_id: '{matched_user_id}'}})
    RETURN a.user_id AS requester_id, a.lat AS r_lat, a.lon AS r_lon,
           b.user_id AS target_id,    b.lat AS t_lat, b.lon AS t_lon
    LIMIT 1
    """


# ---------------------------------------------------------------------------
# Response builders
# ---------------------------------------------------------------------------

def build_map_payload(
    match_type: str,
    match_status: str,
    match_id: str | None,
    requester: dict,
    matched_user: dict | None,
    route_coordinates: list,
    distance: float | None,
) -> dict:
    return {
        "match_id": match_id,
        "match_type": match_type,
        "match_status": match_status,
        "requester": requester,
        "matched_user": matched_user,
        "route_coordinates": route_coordinates,
        "distance": distance,
    }


def build_error_response(reason: str) -> dict:
    return {
        "status": "error",
        "response_type": "MAP",
        "chat_message": reason,
        "map_payload": None,
        "alert_payload": None,
        "data_payload": None,
        "ui_actions": [],
    }


# ---------------------------------------------------------------------------
# UI action sets
# ---------------------------------------------------------------------------

def _ui_actions(request_mode: str, emergency: bool, matched: bool) -> list[str]:
    if not matched:
        return ["OPEN_MAP_SCREEN", "SHOW_SEARCHING_STATUS"]
    if emergency:
        return ["OPEN_MAP_SCREEN", "SHOW_LIVE_MATCH", "SHOW_EMERGENCY_BANNER"]
    if request_mode == "HELPER":
        return ["OPEN_MAP_SCREEN", "SHOW_VICTIM_LOCATION", "SHOW_MATCH_BANNER"]
    return ["OPEN_MAP_SCREEN", "SHOW_HELPER_LOCATION", "SHOW_MATCH_BANNER"]


# ---------------------------------------------------------------------------
# Core handler
# ---------------------------------------------------------------------------

def handle_map_task(
    user_id,
    session_id,
    query,
    lat,
    lon,
    emergency=False,
    request_mode="VICTIM",
):
    user_id = str(user_id)
    role = request_mode

    save_live_location(user_id, lat, lon, role, session_id)

    match_type = classify_match_type(query, emergency=emergency, request_mode=request_mode)

    if match_type == "TRACK_MATCHED_USER":
        # Caller must supply matched_user_id in query context — handled below if missing
        gql = build_track_user_query(user_id, query)
    elif match_type == "FIND_NEARBY_VICTIMS":
        gql = build_find_victims_query(lat, lon, user_id)
    else:
        gql = build_find_helpers_query(lat, lon, user_id)

    rows = _execute_query(gql)

    requester = {"user_id": user_id, "role": role, "lat": lat, "lon": lon}

    if not rows:
        payload = build_map_payload(
            match_type=match_type,
            match_status="SEARCHING",
            match_id=None,
            requester=requester,
            matched_user=None,
            route_coordinates=[],
            distance=None,
        )
        return {
            "status": "success",
            "response_type": "MAP",
            "chat_message": "Searching for nearby users. Stay connected.",
            "map_payload": payload,
            "alert_payload": None,
            "data_payload": None,
            "ui_actions": _ui_actions(request_mode, emergency, matched=False),
        }

    row = rows[0]
    matched_user = {
        "user_id": row.get("user_id"),
        "name": row.get("name", "Unknown"),
        "role": "HELPER" if match_type == "FIND_NEARBY_HELPERS" else "VICTIM",
        "lat": row.get("lat"),
        "lon": row.get("lon"),
    }

    existing_match = _fetch_match(
        victim_id=user_id if role == "VICTIM" else matched_user["user_id"],
        helper_id=matched_user["user_id"] if role == "VICTIM" else user_id,
    )
    match_id = existing_match["match_id"] if existing_match else _create_match(
        victim_id=user_id if role == "VICTIM" else matched_user["user_id"],
        helper_id=matched_user["user_id"] if role == "VICTIM" else user_id,
    )

    payload = build_map_payload(
        match_type=match_type,
        match_status="MATCHED",
        match_id=match_id,
        requester=requester,
        matched_user=matched_user,
        route_coordinates=[],  # TODO: generate route when routing service is wired
        distance=row.get("distance"),
    )

    chat_msg = (
        "A helper has been found. Their location is marked on the map."
        if role == "VICTIM"
        else "Victim located. Navigate to assist."
    )

    return {
        "status": "success",
        "response_type": "MAP",
        "chat_message": chat_msg,
        "map_payload": payload,
        "alert_payload": None,
        "data_payload": None,
        "ui_actions": _ui_actions(request_mode, emergency, matched=True),
    }
