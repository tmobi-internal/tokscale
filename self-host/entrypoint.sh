#!/bin/sh
set -e

if [ -n "$DATABASE_URL" ]; then
  echo "[entrypoint] Running drizzle-kit migrate..."
  npx drizzle-kit migrate 2>&1 || echo "[entrypoint] drizzle-kit migrate failed, continuing anyway"
fi

exec "$@"
