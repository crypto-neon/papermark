#!/bin/bash

echo "Fetching configuration directly from GCP Secret Manager..."
set -a
source <(gcloud secrets versions access latest --secret="dataroom")
set +a

if [ -z "$GCP_PROJECT" ]; then
  echo "Error: Failed to load secrets from GCP."
  exit 1
fi

# --- 1. INSTALL DEPENDENCIES (Required for DB Tools) ---
echo "Installing dependencies (this may take a minute)..."
npm install --quiet

# --- 2. AUTOMATIC DATABASE CREATION ---
INSTANCE_ID=$(echo $CLOUD_SQL_INSTANCE | awk -F: '{print $NF}')
echo "Ensuring database 'papermark' exists in instance '$INSTANCE_ID'..."
gcloud sql databases create papermark --instance=$INSTANCE_ID --project=$GCP_PROJECT || echo "Database 'papermark' already exists."

# --- 3. START DATABASE TUNNEL ---
echo "Opening Cloud SQL Proxy..."
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 5 

# --- 4. INITIALIZE SCHEMA ---
echo "Pushing database schema..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
# We explicitly point to the monorepo schema path
npx prisma db push --schema=./apps/web/prisma/schema.prisma

# --- 5. SEED INITIAL USER ---
echo "Seeding admin user..."
# We point to the web folder where the prisma client lives
node -e "
const { PrismaClient } = require('./apps/web/node_modules/@prisma/client');
const prisma = new PrismaClient();
async function seed() {
  await prisma.user.upsert({
    where: { email: 'pr@ivault.io' },
    update: {},
    create: { email: 'pr@ivault.io', name: 'Admin' }
  });
  console.log('Successfully seeded pr@ivault.io');
}
seed().catch(console.error).finally(() => prisma.\$disconnect());
"

# --- 6. CLOSE DATABASE TUNNEL ---
kill $PROXY_PID

# --- 7. BUILD & DEPLOY TO CLOUD RUN ---
echo "Deploying to Google Cloud Run ($SERVICE_NAME)..."
# Corrected flags: --set-build-env-vars and --set-env-vars
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