# Use a lightweight Node.js image
FROM node:20-alpine

# Install OpenSSL and libc6-compat (Required by Prisma on Alpine Linux)
RUN apk add --no-cache libc6-compat openssl

# Set the working directory inside the container
WORKDIR /app

# Copy everything from your project into the container
COPY . .

# Install dependencies
RUN npm install

# Generate the Prisma Client using the root schema
RUN npx prisma generate

# Build the Next.js application
RUN npm run build

# Set production environment variables
ENV NODE_ENV=production
ENV PORT=3000

# Expose the port Cloud Run expects
EXPOSE 3000

# Start the application
CMD ["npm", "start"]