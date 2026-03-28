"""
Shared HTTP / agent contract: one request shape and one response shape for the iOS client and Python agents.

* ``CommonRequest`` — inbound from the app (chat, buttons, optional location).
* ``CommonResponse`` — outbound envelope; payloads may carry extra keys during rollout (payload models use extra="allow").
"""
from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator

# ---------------------------------------------------------------------------
# Payloads (nested)
# ---------------------------------------------------------------------------


class MapPayload(BaseModel):
    """Map / matching agent body. All fields optional so SEARCHING vs MATCHED flows stay valid."""

    model_config = ConfigDict(extra="allow")

    requester: Optional[dict[str, Any]] = Field(
        default=None,
        description="Current user: user_id, role, lat, lon.",
    )
    matched_user: Optional[dict[str, Any]] = Field(
        default=None,
        description="Single matched peer (helper or victim), if any.",
    )
    nearby_helpers: Optional[list[dict[str, Any]]] = Field(
        default=None,
        description="Optional list of nearby helpers when returning multiple candidates.",
    )
    route_coordinates: Optional[list[Any]] = Field(
        default=None,
        description="Polyline or graph path for map rendering.",
    )
    distance: Optional[float] = Field(default=None, description="Meters or backend-specific distance.")
    emergency: Optional[bool] = Field(default=None, description="True when this payload is from an emergency path.")
    match_id: Optional[str] = None
    match_status: Optional[str] = None
    match_type: Optional[str] = None
    message: Optional[str] = Field(default=None, description="Legacy or agent-specific map message.")


class AlertPayload(BaseModel):
    """Victim-side alert record + dispatch metadata."""

    model_config = ConfigDict(extra="allow")

    alert_id: Optional[str] = None
    user_id: Optional[str] = None
    session_id: Optional[str] = None
    alert_type: Optional[str] = None
    priority: Optional[str] = None
    status: Optional[str] = None
    message: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None
    notified_helper_count: int = Field(default=0, ge=0)
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class DataPayload(BaseModel):
    """Conversational agent metadata; not user-visible copy (that lives in chat_message)."""

    model_config = ConfigDict(extra="allow")

    agent_name: str = Field(default="data_agent", description="Which agent produced the reply.")
    source: str = Field(
        default="llm",
        description="e.g. llm, fallback, cached.",
    )
    history_used: bool = Field(default=False)
    context_used: bool = Field(default=False)
    notes: Optional[str] = Field(default=None, description="Debug or internal hints; avoid PII.")
    reply: Optional[str] = Field(default=None, description="Optional duplicate of assistant text for logging.")


# ---------------------------------------------------------------------------
# Envelope
# ---------------------------------------------------------------------------


class CommonResponse(BaseModel):
    """
    Single response shape for supervisor and all sub-agents after normalization.

    ``chat_message`` is the primary user-visible string when present.
    """

    model_config = ConfigDict(extra="forbid")

    status: str = Field(..., description="success | error")
    response_type: str = Field(
        ...,
        description="CHAT | MAP | ALERT | EMERGENCY_FLOW | …",
    )
    chat_message: Optional[str] = None
    map_payload: Optional[MapPayload] = None
    alert_payload: Optional[AlertPayload] = None
    data_payload: Optional[DataPayload] = None
    ui_actions: list[str] = Field(default_factory=list)


class CommonRequest(BaseModel):
    """
    Single request shape from the client.

    * ``query`` may be empty for button-only flows (e.g. emergency).
    * ``lat`` / ``lon`` may be omitted for pure chat; supply both when sending location.
    """

    model_config = ConfigDict(extra="forbid")

    user_id: str = Field(..., min_length=1)
    session_id: str = Field(..., min_length=1)
    query: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None
    trigger_type: str = Field(default="CHAT", description="CHAT | EMERGENCY_BUTTON | …")

    @model_validator(mode="before")
    @classmethod
    def lat_lon_pair(cls, data: Any) -> Any:
        """If only one coordinate is sent, drop both (backend-safe pair)."""
        if isinstance(data, dict):
            lat, lon = data.get("lat"), data.get("lon")
            if (lat is None) ^ (lon is None):
                return {**data, "lat": None, "lon": None}
        return data


__all__ = [
    "AlertPayload",
    "CommonRequest",
    "CommonResponse",
    "DataPayload",
    "MapPayload",
]
