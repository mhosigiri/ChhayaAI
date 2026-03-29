#!/bin/bash
# Deploy ai_agent_service to Google Cloud Run
# Run this from inside the ai_agent_service/ directory: bash deploy.sh

set -euo pipefail

PROJECT_ID="chhaya-ai-491617"
REGION="us-central1"
SERVICE_NAME="chhaya-agent"
IMAGE="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

echo "==> Building and pushing Docker image..."
gcloud builds submit --tag "$IMAGE" .

echo "==> Deploying to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE" \
  --platform managed \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --allow-unauthenticated \
  --set-env-vars "GROQ_API_KEY=${GROQ_API_KEY}" \
  --set-env-vars "SPANNER_PROJECT_ID=${SPANNER_PROJECT_ID}" \
  --set-env-vars "SPANNER_INSTANCE_ID=${SPANNER_INSTANCE_ID}" \
  --set-env-vars "SPANNER_DATABASE_ID=${SPANNER_DATABASE_ID}" \
  --set-env-vars "AUTH_REQUIRED=0" \
  --set-env-vars "REDIS_HOST=" \
  --memory 512Mi \
  --min-instances 0 \
  --max-instances 10

echo ""
echo "==> Done! Your service URL is:"
gcloud run services describe "$SERVICE_NAME" \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --format "value(status.url)"
