FROM node:22-alpine

# Necessary for Prisma to run on Alpine Linux
RUN apk add --no-cache libc6-compat openssl

WORKDIR /app

# Improve build speed by copying only package files first
COPY package*.json ./
COPY prisma ./prisma/

# Install dependencies without running the "postinstall" prisma generate yet
RUN npm install --ignore-scripts

# Now copy the rest of the code
COPY . .

# --- BUILD ARGUMENTS ---

# --- DUMMY VARIABLES TO BYPASS NEXT.JS BUILD CHECKS ---
# Database (Required for Prisma to compile)
ENV POSTGRES_PRISMA_URL="postgresql://user:pass@localhost:5432/db"
ENV POSTGRES_PRISMA_URL_NON_POOLING="postgresql://user:pass@localhost:5432/db"

# The hidden variables (Not in their .env.example)
ENV OPENAI_API_KEY="dummy_openai"
ENV SLACK_CLIENT_ID="dummy_slack"
ENV SLACK_CLIENT_SECRET="dummy_slack"

# The documented variables from their .env.example
ENV NEXTAUTH_SECRET="dummy_secret"
ENV QSTASH_TOKEN="dummy_qstash"
ENV QSTASH_CURRENT_SIGNING_KEY="dummy_qstash"
ENV QSTASH_NEXT_SIGNING_KEY="dummy_qstash"
ENV UPSTASH_REDIS_REST_URL="https://dummy.upstash.io"
ENV UPSTASH_REDIS_REST_TOKEN="dummy_upstash"
ENV UPSTASH_REDIS_REST_LOCKER_URL="https://dummy.upstash.io"
ENV UPSTASH_REDIS_REST_LOCKER_TOKEN="dummy_upstash"
ENV HANKO_API_KEY="dummy_hanko"
ENV NEXT_PUBLIC_HANKO_TENANT_ID="dummy_hanko"
ENV RESEND_API_KEY="dummy_resend"
ENV TINYBIRD_TOKEN="dummy_tinybird"
ENV TRIGGER_SECRET_KEY="dummy_trigger"
ENV NEXT_PRIVATE_DOCUMENT_PASSWORD_KEY="dummy_secret"
ENV NEXT_PRIVATE_VERIFICATION_SECRET="dummy_secret"

# Manually generate the client
RUN npx prisma generate

RUN npm run build

ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

# BULK INGESTION: This reads the mounted secret file and exports all variables right before booting
CMD ["sh", "-c", "if [ -f /secrets/dataroom ]; then set -a && . /secrets/dataroom && set +a; fi && npm start"]