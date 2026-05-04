#!/bin/bash

# --- 0. PRE-FLIGHT CHECK & USER INPUT ---
if [ ! -f "package.json" ]; then
    echo "Error: Script must be run from the root of the papermark folder."
    exit 1
fi

echo "=========================================="
echo "   Papermark Deployment Setup"
echo "=========================================="
echo "⚠️  IMPORTANT: The email below is for your"
echo "Papermark Dataroom login, NOT Google Cloud."
read -p "Enter the Admin email for your Dataroom: " ADMIN_EMAIL

if [ -z "$ADMIN_EMAIL" ]; then
  echo "Error: Admin email cannot be empty. Deployment aborted."
  exit 1
fi

echo ""
echo "Fetching configuration from GCP Secret Manager..."
set -a
source <(gcloud secrets versions access latest --secret="dataroom")
set +a

# --- 1. INSTALL DEPENDENCIES ---
echo "Installing local dependencies..."
npm install --quiet

# --- 2. DATABASE CHECK ---
INSTANCE_ID=$(echo $CLOUD_SQL_INSTANCE | awk -F: '{print $NF}')
DB_EXISTS=$(gcloud sql databases list --instance=$INSTANCE_ID --format="value(name)" --filter="name=papermark")

if [ "$DB_EXISTS" != "papermark" ]; then
  echo "Creating database 'papermark'..."
  gcloud sql databases create papermark --instance=$INSTANCE_ID --project=$GCP_PROJECT
fi

# --- 3. DATABASE TUNNEL ---
cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 5 

# --- 4. INITIALIZE SCHEMA ---
echo "Pushing modular schema to Cloud SQL..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_PRISMA_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_PRISMA_URL_NON_POOLING="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"

npx prisma db push

# --- 5. SEED INITIAL USER ---
echo "Seeding admin user: $ADMIN_EMAIL..."
export SEED_EMAIL="$ADMIN_EMAIL"
node -e "
const { PrismaClient } = require('./node_modules/@prisma/client');
const prisma = new PrismaClient();
async function seed() {
  try {
    await prisma.user.upsert({
      where: { email: process.env.SEED_EMAIL },
      update: {},
      create: { email: process.env.SEED_EMAIL, name: 'Admin' }
    });
    console.log('Successfully seeded ' + process.env.SEED_EMAIL);
  } catch (e) { console.error('Seeding error:', e); }
}
seed().finally(() => prisma.\$disconnect());
"

kill $PROXY_PID

# --- 7. BUILD & DEPLOY TO CLOUD RUN ---
IMAGE_URL="gcr.io/$GCP_PROJECT/papermark:latest"

echo "=========================================="
echo "Phase 7A: Building the Docker Image..."
echo "=========================================="
# We build explicitly first to bypass the gcloud polling timeout
if gcloud builds submit --tag $IMAGE_URL .; then
  echo "✅ Build Successful!"
else
  echo "❌ Build Failed. Check the terminal output above."
  exit 1
fi

echo "=========================================="
echo "Phase 7B: Deploying to Cloud Run ($SERVICE_NAME)..."
echo "=========================================="
# Now we deploy the finished image, no 'source' building required
if gcloud run deploy $SERVICE_NAME \
  --image $IMAGE_URL \
  --project $GCP_PROJECT \
  --region $REGION \
  --allow-unauthenticated \
  --add-cloudsql-instances $CLOUD_SQL_INSTANCE \
  --set-secrets "/secrets/dataroom=dataroom:latest" \
  --set-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,POSTGRES_PRISMA_URL=$POSTGRES_PRISMA_URL,POSTGRES_PRISMA_URL_NON_POOLING=$POSTGRES_PRISMA_URL_NON_POOLING"; then
  
  echo "=========================================="
  echo "✅ DEPLOYMENT COMPLETE SUCCESSFULLY!"
  echo "=========================================="
else
  echo "=========================================="
  echo "❌ ERROR: Cloud Run Deployment Failed."
  echo "=========================================="
  exit 1
fi