#!/bin/bash

echo "Fetching configuration..."
set -a
source <(gcloud secrets versions access latest --secret="dataroom")
set +a

echo "Pulling latest code..."
git pull origin main

echo "Installing/Updating dependencies..."
npm install --quiet

echo "Opening Cloud SQL Proxy..."
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 5

echo "Applying database changes..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
npx prisma db push --schema=./apps/web/prisma/schema.prisma

kill $PROXY_PID

echo "Updating Cloud Run service..."
gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --set-build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT"

echo "Update Complete!"