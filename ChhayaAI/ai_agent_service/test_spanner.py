from app.config import get_google_application_credentials
from app.db.spanner_client import SpannerClient

def main():
    print("Credential path:", get_google_application_credentials())

    try:
        client = SpannerClient()
        print("SpannerClient initialized successfully")
    except Exception as e:
        print("Failed to initialize SpannerClient:", e)
        return

    # Test a safe query path
    try:
        result = client.execute_graph_query("GRAPH RoadGraph MATCH (n) RETURN n LIMIT 1")
        print("Query executed successfully")
        print("Result:", result)
    except Exception as e:
        print("Query failed:", e)

if __name__ == "__main__":
    main()