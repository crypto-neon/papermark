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

# Manually generate the client from the modular schema folder
RUN npx prisma generate

# Build the Next.js app
# We use dummy variables here to satisfy the build-time checks
ENV POSTGRES_PRISMA_URL="postgresql://user:pass@localhost:5432/db"
ENV POSTGRES_PRISMA_URL_NON_POOLING="postgresql://user:pass@localhost:5432/db"

# Add these new dummy variables to bypass the Upstash and Hanko checks
ENV QSTASH_TOKEN="dummy_token"
ENV UPSTASH_REDIS_REST_URL="https://dummy.upstash.io"
ENV UPSTASH_REDIS_REST_TOKEN="dummy_token"
ENV HANKO_API_KEY="dummy_key"
ENV NEXT_PUBLIC_HANKO_TENANT_ID="dummy_id"
ENV OPENAI_API_KEY="dummy_key"
ENV SLACK_CLIENT_ID="dummy_id"
ENV SLACK_CLIENT_SECRET="dummy_secret"

RUN npm run build

ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

CMD ["npm", "start"]