#!/bin/bash
set -e

PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
DB="${TOKSCALE_DB:-tokscale}"
USERNAME="admin"
TOKEN="tt_${USERNAME}"
TOKEN_HASH=$(echo -n "$TOKEN" | shasum -a 256 | cut -d' ' -f1)

psql -d "$DB" -q <<SQL
INSERT INTO users (github_id, username, display_name, is_admin)
VALUES (abs(hashtext('$USERNAME')), '$USERNAME', '$USERNAME', true)
ON CONFLICT (username) DO UPDATE SET is_admin = true;

DELETE FROM api_tokens
WHERE user_id = (SELECT id FROM users WHERE username = '$USERNAME')
  AND name = 'default';

INSERT INTO api_tokens (user_id, token, name)
VALUES ((SELECT id FROM users WHERE username = '$USERNAME'), '$TOKEN_HASH', 'default');
SQL

echo "Admin seeded:"
echo "  Username: $USERNAME"
echo "  Token:    $TOKEN"
echo "  Admin:    true"
