FROM harbor.tmapadmin.com/docker/node:22-alpine AS builder

WORKDIR /app

COPY packages/frontend/package.json packages/frontend/yarn.lock* ./
RUN yarn install --frozen-lockfile || yarn install

COPY packages/frontend/ ./
RUN yarn build

FROM harbor.tmapadmin.com/docker/node:22-alpine AS runner

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

WORKDIR /app

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package.json ./
COPY --from=builder /app/next.config.ts ./
COPY --from=builder /app/src ./src
COPY --from=builder /app/drizzle.config.ts ./

COPY self-host/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN chown -R nextjs:nodejs .next

USER nextjs

EXPOSE 3000

ENTRYPOINT ["entrypoint.sh"]
CMD ["npx", "next", "start", "-H", "0.0.0.0"]
