# Stage 1: Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json tsconfig.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Runner stage
FROM node:20-alpine AS runner
ENV NODE_ENV=production
WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/db ./db

# Harden directory permissions and assign to non-root user
RUN chown -R node:node /app
USER node

EXPOSE 3000
CMD ["node", "dist/server.js"]
