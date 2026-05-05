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
# These allow gcloud builds submit to pass in the real domain values
ARG NEXT_PUBLIC_APP_BASE_HOST
ARG NEXT_PUBLIC_APP_URL
ARG NEXT_PUBLIC_BASE_URL

# --- DUMMY VARIABLES TO BYPASS NEXT.JS BUILD CHECKS ---
# Database (Required for Prisma to compile)
ENV POSTGRES_PRISMA_URL="postgresql://user:pass@localhost:5432/db"
ENV POSTGRES_PRISMA_URL_NON_POOLING="postgresql://user:pass@localhost:5432/db"

# Map the Build ARGs to ENVs so they are available to 'npm run build'
# This ensures the routing logic is "baked" with the correct domain identity
ENV NEXT_PUBLIC_APP_BASE_HOST=${NEXT_PUBLIC_APP_BASE_HOST}
ENV NEXT_PUBLIC_APP_URL=${NEXT_PUBLIC_APP_URL}
ENV NEXT_PUBLIC_BASE_URL=${NEXT_PUBLIC_BASE_URL}

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

# Build the app (now using the real domain identity for routing)
RUN npm run build

ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

CMD ["npm", "start"]