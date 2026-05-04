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
# We use dummy variables here to satisfy the build-time check
ENV POSTGRES_PRISMA_URL="postgresql://user:pass@localhost:5432/db"
ENV POSTGRES_PRISMA_URL_NON_POOLING="postgresql://user:pass@localhost:5432/db"
RUN npm run build

ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

CMD ["npm", "start"]