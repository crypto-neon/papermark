#!/bin/bash

# --- 0. PRE-FLIGHT CHECK & USER INPUT ---
if [ ! -f "package.json" ]; then
    echo "Error: Script must be run from the root of the papermark folder."
    exit 1
fi

echo "=========================================="
echo "   Papermark Deployment Setup"
echo "=========================================="
read -p "Enter the email for your Papermark Dataroom Admin: " ADMIN_EMAIL

if [ -z "$ADMIN_EMAIL" ]; then
  echo "Error: Admin email cannot be empty. Deployment aborted."
  exit 1
fi

echo ""
echo "Fetching configuration directly from GCP Secret Manager..."
set -a
source <(gcloud secrets versions access latest --secret="dataroom")
set +a

if [ -z "$GCP_PROJECT" ]; then
  echo "Error: Failed to load secrets from GCP."
  exit 1
fi

# --- 1. INSTALL DEPENDENCIES ---
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
# Export both the standard and Vercel-specific database URLs
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_PRISMA_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_URL_NON_POOLING="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"

# Let Prisma find the schema automatically
npx prisma db push

# --- 5. SEED INITIAL USER ---
echo "Seeding admin user: $ADMIN_EMAIL..."
export SEED_EMAIL="$ADMIN_EMAIL"

node -e "
const { PrismaClient } = require('./node_modules/@prisma/client');
const prisma = new PrismaClient();
const adminEmail = process.env.SEED_EMAIL;

async function seed() {
  try {
    await prisma.user.upsert({
      where: { email: adminEmail },
      update: {},
      create: { email: adminEmail, name: 'Admin' }
    });
    console.log('Successfully seeded ' + adminEmail);
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

if gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --allow-unauthenticated \
  --add-cloudsql-instances $CLOUD_SQL_INSTANCE \
  --set-secrets "/secrets/dataroom=dataroom:latest" \
  --set-build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT" \
  --set-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,NEXT_PUBLIC_TINYBIRD_TRACKER_URL=$NEXT_PUBLIC_TINYBIRD_TRACKER_URL,NEXT_PUBLIC_UPLOAD_TRANSPORT=$NEXT_PUBLIC_UPLOAD_TRANSPORT"; then
  
  echo "=========================================="
  echo "✅ DEPLOYMENT COMPLETE SUCCESSFULLY!"
  echo "=========================================="
else
  echo "=========================================="
  echo "❌ ERROR: Cloud Run Deployment Failed."
  echo "Please check the Cloud Build logs URL printed above for details."
  echo "=========================================="
  exit 1
fi