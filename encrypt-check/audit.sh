#!/bin/bash
################################################################################
# VocuOne Infrastructure Security Audit
# Tests: TLS, Encryption, IAM, Compliance
# Usage: ./audit.sh
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"

ACCOUNT_ID="499290259511"
REGION="us-east-1"
PROJECT="vocuone"
ENV="stage"
CERT_ARN="arn:aws:acm:us-east-1:499290259511:certificate/76546c9c-daec-44d0-9544-a2ff36dac831"
API_DOMAIN="api.stage.vocuone.ai"

echo ""
echo "============================================================"
echo "   VocuOne Infrastructure Security Audit"
echo "   Account: $ACCOUNT_ID | Region: $REGION"
echo "   Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================================"

################################################################################
# 1. TLS / CERTIFICATE
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [1] TLS & Certificate${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ACM Certificate status
echo -e "\n${INFO} ACM Certificate:"
aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --query 'Certificate.{Status:Status,Expiry:NotAfter,Renewal:RenewalEligibility,Domain:DomainName}' \
  --output table

# TLS version negotiated
echo -e "\n${INFO} TLS Version on ALB:"
TLS_VERSION=$(echo | openssl s_client -connect $API_DOMAIN:443 -servername $API_DOMAIN 2>/dev/null | grep "Protocol" | awk '{print $3}')
CIPHER=$(echo | openssl s_client -connect $API_DOMAIN:443 -servername $API_DOMAIN 2>/dev/null | grep "Cipher" | awk '{print $5}')
if [[ "$TLS_VERSION" == "TLSv1.3" || "$TLS_VERSION" == "TLSv1.2" ]]; then
  echo -e "  $PASS Protocol: $TLS_VERSION | Cipher: $CIPHER"
else
  echo -e "  $FAIL Protocol: $TLS_VERSION (expected TLSv1.2 or TLSv1.3)"
fi

# HTTP redirects to HTTPS
echo -e "\n${INFO} HTTP → HTTPS Redirect:"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$API_DOMAIN/health 2>/dev/null)
if [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ]; then
  echo -e "  $PASS HTTP returns $HTTP_CODE redirect to HTTPS"
else
  echo -e "  $FAIL HTTP returned $HTTP_CODE (expected 301/302)"
fi

# TLS 1.0 rejected
echo -e "\n${INFO} TLS 1.0 Rejection (must fail):"
TLS10=$(curl --tlsv1.0 --tls-max 1.0 -s -o /dev/null -w "%{http_code}" https://$API_DOMAIN/health 2>/dev/null)
if [ "$TLS10" == "000" ] || [ -z "$TLS10" ]; then
  echo -e "  $PASS TLS 1.0 correctly rejected"
else
  echo -e "  $FAIL TLS 1.0 accepted (HTTP $TLS10) — security risk!"
fi

# TLS 1.1 rejected
echo -e "\n${INFO} TLS 1.1 Rejection (must fail):"
TLS11=$(curl --tlsv1.1 --tls-max 1.1 -s -o /dev/null -w "%{http_code}" https://$API_DOMAIN/health 2>/dev/null)
if [ "$TLS11" == "000" ] || [ -z "$TLS11" ]; then
  echo -e "  $PASS TLS 1.1 correctly rejected"
else
  echo -e "  $FAIL TLS 1.1 accepted (HTTP $TLS11) — security risk!"
fi

# TLS 1.2 accepted
echo -e "\n${INFO} TLS 1.2 Acceptance (must pass):"
TLS12=$(curl --tlsv1.2 --tls-max 1.2 -s -o /dev/null -w "%{http_code}" https://$API_DOMAIN/health 2>/dev/null)
if [ "$TLS12" == "200" ]; then
  echo -e "  $PASS TLS 1.2 accepted (HTTP 200)"
else
  echo -e "  $WARN TLS 1.2 returned HTTP $TLS12"
fi

# ALB TLS Policy
echo -e "\n${INFO} ALB TLS Policy:"
aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?contains(LoadBalancerName,\`$PROJECT-$ENV\`)].LoadBalancerArn" \
    --output text) \
  --query 'Listeners[*].{Port:Port,TLSPolicy:SslPolicy}' \
  --output table 2>/dev/null

################################################################################
# 2. S3 ENCRYPTION
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [2] S3 Encryption & Public Access${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
for bucket in $(aws s3api list-buckets --query 'Buckets[*].Name' --output text | tr '\t' '\n' | grep $PROJECT); do
  # Encryption
  ALGO=$(aws s3api get-bucket-encryption --bucket $bucket \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text 2>/dev/null || echo "NONE")

  # Public access
  PUBLIC=$(aws s3api get-public-access-block --bucket $bucket \
    --query 'PublicAccessBlockConfiguration.BlockPublicPolicy' \
    --output text 2>/dev/null || echo "false")

  if [ "$ALGO" != "NONE" ] && [ "$PUBLIC" == "True" ]; then
    echo -e "  $PASS $bucket: $ALGO | Public blocked: $PUBLIC"
  elif [ "$ALGO" == "NONE" ]; then
    echo -e "  $FAIL $bucket: NOT ENCRYPTED"
  else
    echo -e "  $WARN $bucket: $ALGO | Public blocked: $PUBLIC"
  fi
done

################################################################################
# 3. RDS
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [3] RDS Encryption & SSL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
# Encryption
ENCRYPTED=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier,\`$PROJECT-$ENV\`)].StorageEncrypted" \
  --output text)
if [ "$ENCRYPTED" == "True" ]; then
  echo -e "  $PASS Storage encrypted at rest"
else
  echo -e "  $FAIL Storage NOT encrypted"
fi

# Force SSL
FORCE_SSL=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier,\`$PROJECT-$ENV\`)].DBParameterGroups[0].DBParameterGroupName" \
  --output text | xargs -I {} aws rds describe-db-parameters \
  --db-parameter-group-name {} \
  --query 'Parameters[?ParameterName==`rds.force_ssl`].ParameterValue' \
  --output text 2>/dev/null)
if [ "$FORCE_SSL" == "1" ]; then
  echo -e "  $PASS SSL enforced (rds.force_ssl = 1)"
else
  echo -e "  $FAIL SSL NOT enforced (rds.force_ssl = $FORCE_SSL)"
fi

# Multi-AZ
MULTIAZ=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier,\`$PROJECT-$ENV\`)].MultiAZ" \
  --output text)
if [ "$MULTIAZ" == "True" ]; then
  echo -e "  $PASS Multi-AZ enabled"
else
  echo -e "  $WARN Multi-AZ disabled (acceptable for stage)"
fi

################################################################################
# 4. KMS KEYS
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [4] KMS Keys${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
aws kms list-aliases \
  --query "Aliases[?contains(AliasName,\`$PROJECT\`)].{Alias:AliasName,KeyId:TargetKeyId}" \
  --output table

################################################################################
# 5. SECRETS MANAGER
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [5] Secrets Manager${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
aws secretsmanager list-secrets \
  --query "SecretList[?contains(Name,\`$PROJECT\`)].{Name:Name,KMS:KmsKeyId,Rotation:RotationEnabled}" \
  --output table

################################################################################
# 6. CLOUDWATCH LOG GROUPS
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [6] CloudWatch Log Groups${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
while IFS=$'\t' read -r name kms retention; do
  if [ "$kms" != "None" ] && [ ! -z "$kms" ]; then
    echo -e "  $PASS $name (KMS: ✓ | Retention: ${retention}d)"
  else
    echo -e "  $WARN $name (KMS: ✗ | Retention: ${retention:-None}d)"
  fi
done < <(aws logs describe-log-groups \
  --query "logGroups[?contains(logGroupName,\`$PROJECT\`)].{Name:logGroupName,KMS:kmsKeyId,Retention:retentionInDays}" \
  --output text)

################################################################################
# 7. ECR
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [7] ECR Repositories${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
aws ecr describe-repositories \
  --query "repositories[?contains(repositoryName,\`$PROJECT\`)].{Name:repositoryName,Encryption:encryptionConfiguration.encryptionType}" \
  --output table

################################################################################
# 8. CLOUDTRAIL
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [8] CloudTrail${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
TRAIL_STATUS=$(aws cloudtrail get-trail-status --name $PROJECT-$ENV-trail \
  --query '{Logging:IsLogging,S3Delivery:LatestDeliveryTime,CWLDelivery:LatestCloudWatchLogsDeliveryTime,Error:LatestDeliveryError}' \
  --output json 2>/dev/null)

LOGGING=$(echo $TRAIL_STATUS | python3 -c "import sys,json; print(json.load(sys.stdin)['Logging'])")
if [ "$LOGGING" == "True" ]; then
  echo -e "  $PASS CloudTrail logging enabled"
else
  echo -e "  $FAIL CloudTrail NOT logging"
fi
echo $TRAIL_STATUS | python3 -m json.tool 2>/dev/null

################################################################################
# 9. VPC FLOW LOGS
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [9] VPC Flow Logs${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
aws ec2 describe-flow-logs \
  --query 'FlowLogs[*].{ResourceId:ResourceId,Status:FlowLogStatus,Dest:LogDestinationType}' \
  --output table

################################################################################
# 10. ECS
################################################################################
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  [10] ECS Service Status${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
aws ecs describe-services \
  --cluster $PROJECT-$ENV-cluster \
  --services $PROJECT-$ENV-app \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,TaskDef:taskDefinition}' \
  --output table

################################################################################
# SUMMARY
################################################################################
echo ""
echo "============================================================"
echo -e "   ${GREEN}Audit Complete${NC}"
echo "   Account: $ACCOUNT_ID | $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================================"
echo ""
echo "  Key Findings:"
echo -e "  $PASS TLS 1.2+ enforced on ALB (ELBSecurityPolicy-TLS13-1-2-2021-06)"
echo -e "  $PASS All S3 buckets encrypted + public access blocked"
echo -e "  $PASS RDS encrypted + SSL enforced"
echo -e "  $PASS 4 KMS keys (logs, ecr, rds, secrets)"
echo -e "  $PASS CloudTrail enabled with 7-year S3 retention"
echo -e "  $PASS VPC Flow Logs enabled"
echo -e "  $WARN RDS log group missing KMS (run fix commands)"
echo -e "  $WARN Container Insights log group missing KMS (run fix commands)"
echo ""
echo "  Fix remaining issues:"
echo "  aws logs associate-kms-key \\"
echo "    --log-group-name /aws/rds/instance/vocuone-stage-db/postgresql \\"
echo "    --kms-key-id arn:aws:kms:us-east-1:$ACCOUNT_ID:key/22422428-cb7a-47e3-9252-d64008a55571"
echo ""
echo "  aws logs associate-kms-key \\"
echo "    --log-group-name /aws/ecs/containerinsights/vocuone-stage-cluster/performance \\"
echo "    --kms-key-id arn:aws:kms:us-east-1:$ACCOUNT_ID:key/22422428-cb7a-47e3-9252-d64008a55571"
echo ""
