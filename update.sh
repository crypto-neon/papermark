#!/bin/bash

# Ensure we are in the root
if [ ! -f "package.json" ]; then
    echo "Error: Script must be run from the root of the papermark folder."
    exit 1
fi

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
echo "Installing/Updating dependencies..."
npm install --quiet

# --- 2. START DATABASE TUNNEL ---
echo "Opening Cloud SQL Proxy..."
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 5

# --- 3. APPLY DATABASE CHANGES ---
echo "Applying any new database migrations..."
# Export both the standard and Vercel-specific database URLs
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_PRISMA_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_PRISMA_URL_NON_POOLING="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"

# Push the schema (it will now find all variables)
npx prisma db push

# --- 4. CLOSE TUNNEL ---
echo "Closing Cloud SQL Proxy..."
kill $PROXY_PID

# --- 5. REDEPLOY TO CLOUD RUN ---
echo "Updating Cloud Run service ($SERVICE_NAME)..."

if gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --set-build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT" \
  --set-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT"; then
  
  echo "=========================================="
  echo "✅ UPDATE COMPLETE SUCCESSFULLY!"
  echo "=========================================="
else
  echo "=========================================="
  echo "❌ ERROR: Cloud Run Update Failed."
  echo "Please check the Cloud Build logs URL printed above for details."
  echo "=========================================="
  exit 1
fi