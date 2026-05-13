#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Tokscale AWS 원커맨드 배포 스크립트
# 사용법: SSO 로그인 후 이 스크립트를 실행하면 EC2 생성부터 배포까지 자동 처리
#
#   export DYLD_LIBRARY_PATH=/opt/homebrew/opt/expat/lib:$DYLD_LIBRARY_PATH
#   aws sso login --profile 457475465920_tmobi-developer-admin
#   bash self-host/aws-deploy.sh
# ============================================================================

export DYLD_LIBRARY_PATH=/opt/homebrew/opt/expat/lib:${DYLD_LIBRARY_PATH:-}
export AWS_PROFILE="${AWS_PROFILE:-457475465920_tmobi-developer-admin}"
export AWS_REGION="ap-northeast-2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEY_NAME="tokscale-key"
KEY_FILE="$SCRIPT_DIR/${KEY_NAME}.pem"
SG_NAME="tokscale-sg"
INSTANCE_TYPE="t4g.small"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[tokscale]${NC} $*"; }
warn() { echo -e "${YELLOW}[tokscale]${NC} $*"; }
err()  { echo -e "${RED}[tokscale]${NC} $*" >&2; exit 1; }

log "Verifying AWS credentials..."
aws sts get-caller-identity > /dev/null 2>&1 || err "AWS credentials invalid. Run: aws sso login --profile $AWS_PROFILE"

# --- Key Pair ---
if [ -f "$KEY_FILE" ]; then
  log "Key pair already exists: $KEY_FILE"
else
  log "Creating key pair: $KEY_NAME"
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' \
    --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
fi

# --- Security Group ---
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
EXISTING_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

if [ "$EXISTING_SG" != "None" ] && [ "$EXISTING_SG" != "" ]; then
  SG_ID="$EXISTING_SG"
  log "Security group already exists: $SG_ID"
else
  log "Creating security group: $SG_NAME"
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Tokscale self-host: HTTP + SSH" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)

  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0
  log "Security group created: $SG_ID (SSH + HTTP)"
fi

# --- AMI (Ubuntu 22.04 arm64) ---
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*" \
            "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)
log "Using AMI: $AMI_ID (Ubuntu 22.04 arm64)"

# --- Launch EC2 ---
log "Launching EC2 instance ($INSTANCE_TYPE)..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=tokscale-self-host}]" \
  --query 'Instances[0].InstanceId' --output text)

log "Instance launched: $INSTANCE_ID"
log "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

log "EC2 is running at: $PUBLIC_IP"

# --- Wait for SSH ---
log "Waiting for SSH to become available..."
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$KEY_FILE" ubuntu@"$PUBLIC_IP" "echo ok" 2>/dev/null; then
    break
  fi
  sleep 5
done

# --- Install Docker on EC2 ---
log "Installing Docker on EC2..."
ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@"$PUBLIC_IP" << 'REMOTE_SCRIPT'
set -euo pipefail
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu
REMOTE_SCRIPT

# --- Clone repo and deploy ---
log "Cloning tokscale and deploying..."
AUTH_SECRET=$(openssl rand -hex 32)
PG_PASSWORD=$(openssl rand -hex 16)

ssh -o StrictHostKeyChecking=no -i "$KEY_FILE" ubuntu@"$PUBLIC_IP" << REMOTE_DEPLOY
set -euo pipefail
sudo -u ubuntu bash << 'EOF'
cd ~
git clone https://github.com/tmobi-internal/tokscale.git
cd tokscale/self-host

cat > .env << ENVFILE
POSTGRES_PASSWORD=${PG_PASSWORD}
GITHUB_CLIENT_ID=PLACEHOLDER_FILL_AFTER_OAUTH_APP_CREATED
GITHUB_CLIENT_SECRET=PLACEHOLDER_FILL_AFTER_OAUTH_APP_CREATED
NEXT_PUBLIC_URL=http://${PUBLIC_IP}
AUTH_SECRET=${AUTH_SECRET}
ENVFILE

EOF
REMOTE_DEPLOY

log ""
log "============================================"
log "  EC2 배포 완료!"
log "============================================"
log ""
log "  Instance ID : $INSTANCE_ID"
log "  Public IP   : $PUBLIC_IP"
log "  SSH         : ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
log ""
log "============================================"
log "  다음 단계: GitHub OAuth App 생성"
log "============================================"
log ""
log "  1. https://github.com/settings/developers 에서 New OAuth App"
log "  2. Homepage URL:  http://$PUBLIC_IP"
log "  3. Callback URL:  http://$PUBLIC_IP/api/auth/github/callback"
log "  4. Client ID와 Secret을 복사"
log ""
log "  5. EC2에서 .env 수정:"
log "     ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
log "     cd tokscale/self-host"
log "     nano .env  (GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET 입력)"
log ""
log "  6. Docker 빌드 & 실행:"
log "     sudo docker compose up -d --build"
log "     sudo docker compose exec app npx drizzle-kit push --force"
log ""
log "  7. 팀원 CLI 설정:"
log "     export TOKSCALE_API_URL=http://$PUBLIC_IP"
log "     tokscale login"
log "     tokscale submit"
log ""

echo "$PUBLIC_IP" > "$SCRIPT_DIR/ec2-ip.txt"
echo "$INSTANCE_ID" > "$SCRIPT_DIR/ec2-instance-id.txt"
