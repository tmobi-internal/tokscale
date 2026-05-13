#!/usr/bin/env bash
set -euo pipefail

echo "=== Tokscale EC2 Bootstrap ==="
echo "Run this on a fresh Ubuntu 22.04+ EC2 instance."
echo ""

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"

echo ""
echo "=== Docker installed ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (for docker group)"
echo "  2. git clone https://github.com/tmobi-internal/tokscale.git"
echo "  3. cd tokscale/self-host"
echo "  4. cp .env.example .env"
echo "  5. Edit .env with your values"
echo "  6. bash deploy.sh up"
