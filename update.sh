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

echo "Updating Cloud Run service..."
if gcloud run deploy $SERVICE_NAME \
  --project $GCP_PROJECT \
  --region $REGION \
  --source . \
  --set-build-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,POSTGRES_PRISMA_URL=$POSTGRES_PRISMA_URL,POSTGRES_PRISMA_URL_NON_POOLING=$POSTGRES_PRISMA_URL_NON_POOLING" \
  --set-env-vars "NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL,NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL,POSTGRES_PRISMA_URL=$POSTGRES_PRISMA_URL,POSTGRES_PRISMA_URL_NON_POOLING=$POSTGRES_PRISMA_URL_NON_POOLING"; then
  echo "✅ UPDATE SUCCESSFUL!"
else
  echo "❌ UPDATE FAILED. Check build logs above."
  exit 1
fi