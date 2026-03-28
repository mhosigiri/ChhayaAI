import os
from pathlib import Path

from dotenv import load_dotenv
from groq import Groq

_SERVICE_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(_SERVICE_ROOT / ".env")
load_dotenv()

SYSTEM_PROMPT = """
You are a Geo-Spatial AI Assistant.
Your goal is to help users navigate safely and answer local questions.

RULES:
1. If the user asks for a route, output ONLY the start and end points in JSON format.
2. If the user asks a general question, be concise (under 3 sentences).
3. Do not make up facts about locations you don't know.
4. Always respond in a professional, helpful tone.
"""

# Used only by supervisor intent routing — not mixed with geo/JSON instructions.
CLASSIFICATION_SYSTEM_PROMPT = """You are a strict intent classifier.
Reply with exactly one word and nothing else: MAP, DATA, or ALERT.

MAP = navigation, locations, safety zones, directions, or where something is.
DATA = general chat, weather, casual explanations, or what/why when not about places or distress.
ALERT = user expresses distress, fear, feeling unsafe, urgent need for help, danger, or crisis."""

_ALERT_KEYWORDS = (
    "feel unsafe",
    "i feel unsafe",
    "unsafe",
    "urgent help",
    "need urgent",
    "something is wrong",
    "in danger",
    "threatened",
    "help me",
    "distress",
    "scared",
    "something wrong",
    "need help now",
    "afraid",
)

_MAP_KEYWORDS = (
    "where",
    "near",
    "route",
    "navigate",
    "navigation",
    "location",
    "direction",
    "directions",
    "map",
    "safe",
    "safety",
    "zone",
    "closest",
    "how do i get",
    "how to get",
    "address",
    "distance",
    "walk",
    "drive",
)

# Groq reads GROQ_API_KEY from the environment; .env is loaded above.
client = Groq(api_key=(os.getenv("GROQ_API_KEY") or "").strip() or None)


def _keyword_fallback_intent(query: str) -> str:
    """When Groq is unavailable or the model reply is ambiguous — deterministic routing."""
    q = query.lower()
    if any(k in q for k in _ALERT_KEYWORDS):
        return "ALERT"
    if any(k in q for k in _MAP_KEYWORDS):
        return "MAP"
    return "DATA"


def _normalize_classifier_output(raw: str | None) -> str | None:
    if not raw:
        return None
    r = raw.strip().upper()
    if "ALERT" in r:
        return "ALERT"
    has_map = "MAP" in r
    has_data = "DATA" in r
    if has_map and not has_data:
        return "MAP"
    if has_data and not has_map:
        return "DATA"
    if r == "MAP" or r.startswith("MAP"):
        return "MAP"
    if r == "DATA" or r.startswith("DATA"):
        return "DATA"
    return None


def classify_map_or_data(query: str) -> str:
    """
    Returns 'MAP', 'DATA', or 'ALERT' for routing (legacy name kept for imports).
    Uses a minimal system prompt; on API/parse failure, uses keyword fallback.
    """
    try:
        completion = client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[
                {"role": "system", "content": CLASSIFICATION_SYSTEM_PROMPT},
                {"role": "user", "content": f"Query: {query}\n\nOne word:"},
            ],
            temperature=0,
            max_tokens=10,
        )
        raw = completion.choices[0].message.content
        normalized = _normalize_classifier_output(raw)
        if normalized:
            return normalized
        return _keyword_fallback_intent(query)
    except Exception as e:
        print(f"ERROR calling Groq (classifier): {e}")
        return _keyword_fallback_intent(query)


def classify_intent(query: str) -> str:
    """Supervisor-facing API: MAP, DATA, or ALERT."""
    return classify_map_or_data(query)


def get_ai_response(user_input: str):
    """
    Calls the Llama-3-8b model with robust error handling.
    """
    try:
        # 2. The API Call
        completion = client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_input},
            ],
            temperature=0.5,  # Lower temperature = more factual/less creative
            max_tokens=500,
        )

        # 3. Extract the text
        return completion.choices[0].message.content

    except Exception as e:
        # 4. Fallback Logic: If the API fails, return a safe message
        print(f"ERROR calling Groq: {e}")
        return "I'm having trouble thinking right now. Please check your connection."
