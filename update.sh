#!/bin/bash

if [ ! -f "package.json" ]; then
    echo "Error: Run from the root folder."
    exit 1
fi

set -a && source <(gcloud secrets versions access latest --secret="dataroom") && set +a

echo "Pulling latest code..."
git pull origin main
npm install --quiet

cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
PROXY_PID=$!
sleep 5

echo "Syncing database..."
export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_PRISMA_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
export POSTGRES_PRISMA_URL_NON_POOLING="postgresql://$DB_USER:$DB_PASS@localhost:5432/papermark"
npx prisma db push

kill $PROXY_PID

# --- BUILD & DEPLOY ---
IMAGE_URL="gcr.io/$GCP_PROJECT/papermark:latest"
CLOUD_RUN_DB_URL="postgresql://$DB_USER:$DB_PASS@localhost/papermark?host=/cloudsql/$CLOUD_SQL_INSTANCE"

echo "=========================================="
echo "Phase 1: Building the Updated Image..."
echo "=========================================="
if gcloud builds submit --tag $IMAGE_URL .; then
  echo "✅ Build Successful!"
else
  echo "❌ Build Failed. Check the terminal output above."
  exit 1
fi

echo "=========================================="
echo "Phase 2: Updating Cloud Run service..."
echo "=========================================="
if gcloud run deploy $SERVICE_NAME \
  --image $IMAGE_URL \
  --project $GCP_PROJECT \
  --region $REGION \
  --allow-unauthenticated \
  --add-cloudsql-instances $CLOUD_SQL_INSTANCE \
  --set-secrets "/secrets/dataroom=dataroom:latest" \
  --set-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,POSTGRES_PRISMA_URL=$CLOUD_RUN_DB_URL,POSTGRES_PRISMA_URL_NON_POOLING=$CLOUD_RUN_DB_URL"; then
  
  echo "=========================================="
  echo "✅ UPDATE SUCCESSFUL!"
  echo "=========================================="
else
  echo "=========================================="
  echo "❌ UPDATE FAILED. Check logs above."
  echo "=========================================="
  exit 1
fi