#!/bin/bash

echo "Fetching configuration directly from GCP Secret Manager..."
set -a
source <(gcloud secrets versions access latest --secret="dataroom")
set +a

if [ -z "$GCP_PROJECT" ]; then
  echo "Error: Failed to load secrets from GCP. Check your gcloud authentication."
  exit 1
fi

# --- 1. AUTOMATIC DATABASE CREATION ---
# Extract the last part of the connection name (the Instance ID)
INSTANCE_ID=$(echo $CLOUD_SQL_INSTANCE | awk -F: '{print $NF}')
echo "Ensuring database 'papermark' exists in instance '$INSTANCE_ID'..."
gcloud sql databases create papermark --instance=$INSTANCE_ID --project=$GCP_PROJECT || echo "Database 'papermark' already exists, skipping creation."

# --- 2. START DATABASE TUNNEL ---
echo "Opening Cloud SQL Proxy for $CLOUD_SQL_INSTANCE..."
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 4 

# --- 3. INITIALIZE SCHEMA ---
echo "Pushing database schema..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
npx prisma db push

# --- 4. SEED INITIAL USER ---
echo "Seeding user pr@ivault.io..."
node -e "
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
async function seed() {
  await prisma.user.upsert({
    where: { email: 'pr@ivault.io' },
    update: {},
    create: { email: 'pr@ivault.io', name: 'iVault PR' }
  });
  console.log('Successfully seeded pr@ivault.io');
}
seed().finally(() => prisma.\$disconnect());
"

# --- 5. CLOSE DATABASE TUNNEL ---
echo "Closing Cloud SQL Proxy..."
kill $PROXY_PID

# --- 6. BUILD & DEPLOY TO CLOUD RUN ---
echo "Deploying to Google Cloud Run ($SERVICE_NAME)..."
gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --allow-unauthenticated \
  --add-cloudsql-instances $CLOUD_SQL_INSTANCE \
  --set-secrets "/secrets/dataroom=dataroom:latest" \
  --build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT" \
  --set-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT"

echo "Deployment Complete!"