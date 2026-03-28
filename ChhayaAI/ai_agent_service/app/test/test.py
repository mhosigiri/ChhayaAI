"""Smoke script: run from ai_agent_service as: python app/test/test.py"""
import sys
from pathlib import Path

_root = Path(__file__).resolve().parents[2]
if str(_root) not in sys.path:
    sys.path.insert(0, str(_root))

from app.agents.supervisor import process_user_request

response = process_user_request(
    user_id="u1",
    session_id="s1",
    query="What does this app do?",
    lat=None,
    lon=None,
    trigger_type="CHAT",
)

print(response)
