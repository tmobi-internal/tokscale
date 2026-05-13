FROM node:22-alpine AS base
WORKDIR /app

FROM base AS deps
COPY packages/frontend/package.json ./
RUN npm install --legacy-peer-deps

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY packages/frontend/ ./

RUN sed -i 's/process\.env\.NODE_ENV === "production" ? "require" : false/process.env.DB_SSL === "true" ? "require" : false/' src/lib/db/index.ts
RUN sed -i 's/secure: process.env.NODE_ENV === "production"/secure: false/g' src/app/api/auth/github/route.ts
RUN sed -i 's/secure: process.env.NODE_ENV === "production"/secure: false/g' src/lib/auth/session.ts

ENV NEXT_TELEMETRY_DISABLED=1
ENV DATABASE_URL="postgresql://dummy:dummy@localhost:5432/dummy"

RUN npx next build

FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./
COPY --from=builder /app/next.config.ts ./
COPY --from=builder /app/src ./src
COPY --from=builder /app/drizzle.config.ts ./

RUN chown -R nextjs:nodejs .next/cache

USER nextjs
EXPOSE 3000

CMD ["npx", "next", "start", "-H", "0.0.0.0"]
