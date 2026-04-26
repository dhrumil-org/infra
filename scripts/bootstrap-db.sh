#!/usr/bin/env bash
# =============================================================================
# Bootstrap the PostgreSQL service-account user for IAM auth.
#
# Usage:   ./scripts/bootstrap-db.sh <env>
# Example: ./scripts/bootstrap-db.sh prod
#          ./scripts/bootstrap-db.sh stage
#
# Requires:
#   - aws CLI authenticated to the target account
#   - Session Manager Plugin installed (for `aws ssm start-session` port-forward)
#   - psql available locally
#   - jq available locally
# =============================================================================
set -euo pipefail

ENV="${1:-}"
if [[ -z "$ENV" || ( "$ENV" != "stage" && "$ENV" != "prod" ) ]]; then
  echo "Usage: $0 <stage|prod>" >&2
  exit 1
fi

REGION="us-east-1"
PROJECT="vocuone"
LOCAL_PORT="5433"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/bootstrap-db.sql"

echo "==> Looking up SSM-managed instance + RDS for ${PROJECT}-${ENV}..."

# Use any SSM-managed EC2 in the ECS cluster as the port-forward jump host.
# ECS-optimized AMIs ship with the SSM agent, so the cluster instances are
# automatically managed. No dedicated bastion required.
TARGET_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=${PROJECT}-${ENV}-asg" \
            "Name=instance-state-name,Values=running" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Fallback: any running instance tagged with the env (covers bastion if added later)
if [[ -z "$TARGET_ID" || "$TARGET_ID" == "None" ]]; then
  TARGET_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Environment,Values=${ENV}" \
              "Name=tag:Project,Values=${PROJECT}" \
              "Name=instance-state-name,Values=running" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
fi

if [[ -z "$TARGET_ID" || "$TARGET_ID" == "None" ]]; then
  echo "ERROR: no running SSM-managed instance found in VPC for ${PROJECT}-${ENV}" >&2
  echo "       The script needs any EC2 with SSM agent in the same VPC as RDS." >&2
  exit 1
fi

# Sanity check: SSM must report it as managed (not just running)
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$TARGET_ID" \
  --region "$REGION" \
  --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "")

if [[ "$SSM_STATUS" != "Online" ]]; then
  echo "ERROR: instance $TARGET_ID is not registered with SSM (status: '$SSM_STATUS')" >&2
  echo "       Verify it has the AmazonSSMManagedInstanceCore policy attached." >&2
  exit 1
fi

RDS_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "${PROJECT}-${ENV}-db" \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Address' --output text)

MASTER_SECRET="${PROJECT}/${ENV}/rds/credentials"
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$MASTER_SECRET" \
  --region "$REGION" \
  --query SecretString --output text)
MASTER_USER=$(echo "$SECRET_JSON" | jq -r .username)
MASTER_PW=$(echo   "$SECRET_JSON" | jq -r .password)

echo "    target  : $TARGET_ID (SSM-managed, ECS cluster host)"
echo "    rds host: $RDS_HOST"
echo "    master  : $MASTER_USER"

echo "==> Starting SSM port-forward (localhost:$LOCAL_PORT -> $RDS_HOST:5432)..."

# Start port-forward in background, capture PID so we can kill it on exit
aws ssm start-session \
  --target "$TARGET_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=$RDS_HOST,portNumber=5432,localPortNumber=$LOCAL_PORT" \
  --region "$REGION" >/tmp/ssm-tunnel.log 2>&1 &
TUNNEL_PID=$!
trap 'echo "==> Stopping tunnel (pid $TUNNEL_PID)..."; kill $TUNNEL_PID 2>/dev/null || true' EXIT

# Wait for the tunnel to be ready
echo "==> Waiting for tunnel..."
for i in 1 2 3 4 5 6 7 8 9 10; do
  if (echo > "/dev/tcp/127.0.0.1/$LOCAL_PORT") 2>/dev/null; then
    echo "    tunnel ready"
    break
  fi
  sleep 1
done

echo "==> Running bootstrap SQL..."
PGPASSWORD="$MASTER_PW" psql \
  -h localhost -p "$LOCAL_PORT" \
  -U "$MASTER_USER" \
  -d appdb \
  -v ON_ERROR_STOP=1 \
  -f "$SQL_FILE"

echo ""
echo "==> Done. Force a fresh ECS deployment so tasks pick up the new user:"
echo "    aws ecs update-service --cluster ${PROJECT}-${ENV}-cluster --service ${PROJECT}-${ENV}-app --force-new-deployment --region $REGION"
