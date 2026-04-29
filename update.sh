#!/bin/bash

echo "Fetching configuration directly from GCP Secret Manager..."
set -a
source <(gcloud secrets versions access latest --secret="dataroom")
set +a

if [ -z "$GCP_PROJECT" ]; then
  echo "Error: Failed to load secrets from GCP."
  exit 1
fi

echo "Pulling latest code from GitHub..."
git pull origin main

# --- 1. SYNC DEPENDENCIES ---
# Required because Cloud Shell storage is temporary; we must ensure prisma is available
echo "Installing/Updating dependencies..."
npm install --quiet

# --- 2. START DATABASE TUNNEL ---
echo "Opening Cloud SQL Proxy..."
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 5

# --- 3. APPLY DATABASE CHANGES ---
echo "Applying any new database migrations..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
# Crucial: Pointing to the monorepo schema path
npx prisma db push --schema=./apps/web/prisma/schema.prisma

# --- 4. CLOSE TUNNEL ---
echo "Closing Cloud SQL Proxy..."
kill $PROXY_PID

# --- 5. REDEPLOY TO CLOUD RUN ---
echo "Updating Cloud Run service ($SERVICE_NAME)..."
# Using the corrected --set-build-env-vars flag
gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --set-build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT"

echo "Update Complete!"