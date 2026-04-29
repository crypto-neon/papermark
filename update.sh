#!/bin/bash

echo "Fetching configuration directly from GCP Secret Manager..."
set -a
source <(gcloud secrets versions access latest --secret="dataroom")
set +a

if [ -z "$GCP_PROJECT" ]; then
  echo "Error: Failed to load secrets from GCP."
  exit 1
fi

echo "Pulling latest code..."
git pull origin main

echo "Opening Cloud SQL Proxy..."
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 4

echo "Applying any new database migrations..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
npx prisma db push

echo "Closing Cloud SQL Proxy..."
kill $PROXY_PID

echo "Updating Cloud Run service ($SERVICE_NAME)..."
gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT"

echo "Update Complete!"