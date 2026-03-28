from app.agents.supervisor import process_user_request

response = process_user_request(
    user_id="u1",
    session_id="s1",
    query="What does this app do?",
    lat=None,
    lon=None,
    trigger_type="CHAT"
)

print(response)