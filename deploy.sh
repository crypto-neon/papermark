#!/bin/bash

# --- 0. PRE-FLIGHT CHECK ---
# Ensure we are in the root of the repo
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

# --- 1. INSTALL DEPENDENCIES ---
# Required to build Prisma tools in the temporary Cloud Shell
echo "Installing dependencies (this takes a moment in Cloud Shell)..."
npm install --quiet

# --- 2. SILENT DATABASE CHECK & CREATION ---
INSTANCE_ID=$(echo $CLOUD_SQL_INSTANCE | awk -F: '{print $NF}')
DB_EXISTS=$(gcloud sql databases list --instance=$INSTANCE_ID --format="value(name)" --filter="name=papermark")

if [ "$DB_EXISTS" == "papermark" ]; then
  echo "Database 'papermark' already exists, skipping creation."
else
  echo "Creating database 'papermark' in instance '$INSTANCE_ID'..."
  gcloud sql databases create papermark --instance=$INSTANCE_ID --project=$GCP_PROJECT
fi

# --- 3. START DATABASE TUNNEL ---
echo "Opening Cloud SQL Proxy..."
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 5 

# --- 4. INITIALIZE SCHEMA ---
echo "Pushing database schema to Cloud SQL..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
# Explicit path for Papermark Monorepo
npx prisma db push --schema=./apps/web/prisma/schema.prisma

# --- 5. SEED INITIAL USER ---
echo "Seeding admin user: pr@ivault.io..."
# Explicit path to the web package's prisma client
node -e "
const { PrismaClient } = require('./apps/web/node_modules/@prisma/client');
const prisma = new PrismaClient();
async function seed() {
  try {
    await prisma.user.upsert({
      where: { email: 'pr@ivault.io' },
      update: {},
      create: { email: 'pr@ivault.io', name: 'Admin' }
    });
    console.log('Successfully seeded pr@ivault.io');
  } catch (e) {
    console.error('Seeding error:', e);
  }
}
seed().finally(() => prisma.\$disconnect());
"

# --- 6. CLOSE DATABASE TUNNEL ---
kill $PROXY_PID

# --- 7. BUILD & DEPLOY TO CLOUD RUN ---
echo "Deploying to Google Cloud Run ($SERVICE_NAME)..."
gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --allow-unauthenticated \
  --add-cloudsql-instances $CLOUD_SQL_INSTANCE \
  --set-secrets "/secrets/dataroom=dataroom:latest" \
  --set-build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT" \
  --set-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT"

echo "Deployment Complete!"