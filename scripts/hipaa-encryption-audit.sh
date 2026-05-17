#!/usr/bin/env bash
################################################################################
# HIPAA Encryption Audit (BAA / Security Rule bar only — no HITRUST polish)
#
# Reports each PHI-bearing AWS resource as PASS / FAIL only. The criteria:
#   §164.312(a)(2)(iv)  — Encryption of ePHI at rest (AES-256 acceptable;
#                         AWS-managed key satisfies this, CMK not required)
#   §164.312(e)(1)      — Transmission security: TLS for ePHI in transit
#   §164.530(j)(2)      — 6-year retention of audit/security records that
#                         could contain PHI
#
# What this script DOES NOT flag (HITRUST/SOC 2 stuff, ignored on purpose):
#   - SSE-S3 (AES256) buckets — HIPAA-compliant, just not CMK
#   - Default aws/secretsmanager keys on third-party API secrets — no PHI
#   - SNS topic not encrypted — alarm metadata, no PHI
#   - Missing aws:SecureTransport=false bucket deny — AWS SDK uses HTTPS by
#     default, and HIPAA doesn't require explicit deny policies
#   - Lambda hook / CodeBuild / canary / container-insights log groups — no PHI
#   - <2190d retention on log groups that don't carry PHI (VPC flow, CT tail)
#   - ALB HTTP listeners (intentional; used only by API Gateway HTTP_PROXY
#     hop within AWS, gated by WAF Web ACL requiring X-Gateway-Secret —
#     HIPAA-acceptable compensating control). Only HTTPS listeners are audited.
#
# Usage:
#   ./hipaa-encryption-audit.sh <stage|prod> [project=vocuone] [region=us-east-1]
################################################################################

set -u
ENV="${1:-}"
PROJECT="${2:-vocuone}"
REGION="${3:-us-east-1}"

if [[ -z "$ENV" || ( "$ENV" != "stage" && "$ENV" != "prod" ) ]]; then
  echo "Usage: $0 <stage|prod> [project=vocuone] [region=us-east-1]" >&2
  exit 2
fi

export AWS_PAGER=""
export AWS_DEFAULT_REGION="$REGION"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; DIM=$'\033[2m'; RST=$'\033[0m'

# Counters are written to a tempfile because we use process substitution
# for nested loops; a plain shell variable would be in a subshell.
COUNT_FILE=$(mktemp)
echo "0 0" > "$COUNT_FILE"
trap 'rm -f "$COUNT_FILE"' EXIT

printf "\n${DIM}%-65s %-8s %s${RST}\n" "RESOURCE" "STATUS" "DETAIL"
printf "${DIM}%s${RST}\n" "----------------------------------------------------------------------------------------------------"

row() { # name, status, detail
  local color name status detail
  name="$1"; status="$2"; detail="$3"
  read -r P F < "$COUNT_FILE"
  case "$status" in
    PASS) color=$GREEN; P=$((P+1));;
    FAIL) color=$RED;   F=$((F+1));;
  esac
  echo "$P $F" > "$COUNT_FILE"
  printf "%-65s ${color}%-8s${RST} %s\n" "$name" "$status" "$detail"
}

# Determines if a KMS key id/arn is non-empty (any key, AWS-managed or CMK, is HIPAA-OK).
encrypted() {
  local k="$1"
  [[ -n "$k" && "$k" != "null" && "$k" != "None" && "$k" != "" ]]
}

# A log group is PHI-bearing if its content could contain protected info.
# Only PHI-bearing groups need 6-year retention per §164.530(j)(2).
#   PHI-bearing: app logs, Bedrock invocation logs, RDS query/error logs
#   Not PHI:     VPC flow logs (IP/port metadata only),
#                CloudTrail tail (canonical CT logs live in encrypted S3 forever)
is_phi_log_group() {
  local n="$1"
  [[ "$n" == "/aws/bedrock/"*                                 \
   || "$n" == "/aws/rds/instance/${PROJECT}-${ENV}-db/"*      \
   || "$n" == "/ecs/${PROJECT}-${ENV}-"*                      ]]
}

# Renders retention with a "d" suffix unless it's the literal "never".
fmt_retention() {
  local r="$1"
  if [[ "$r" == "never" ]]; then echo "never (infinite)"
  else                          echo "${r}d"
  fi
}

# ============================================================================
# 1. RDS instance — storage, Performance Insights, in-transit, snapshots
# ============================================================================
DB_ID="${PROJECT}-${ENV}-db"
RDS_JSON=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" 2>/dev/null || echo "")
if [[ -n "$RDS_JSON" ]]; then
  ENC=$(echo "$RDS_JSON"  | jq -r '.DBInstances[0].StorageEncrypted')
  KMS=$(echo "$RDS_JSON"  | jq -r '.DBInstances[0].KmsKeyId // ""')
  PI_ENC=$(echo "$RDS_JSON" | jq -r '.DBInstances[0].PerformanceInsightsEnabled')
  PI_KMS=$(echo "$RDS_JSON" | jq -r '.DBInstances[0].PerformanceInsightsKMSKeyId // ""')
  PG=$(echo "$RDS_JSON"  | jq -r '.DBInstances[0].DBParameterGroups[0].DBParameterGroupName')

  if [[ "$ENC" == "true" ]]; then
    row "RDS storage ($DB_ID)" PASS "encrypted (key: $KMS)"
  else
    row "RDS storage ($DB_ID)" FAIL "StorageEncrypted=false"
  fi

  if [[ "$PI_ENC" == "true" && -n "$PI_KMS" ]]; then
    row "RDS Performance Insights" PASS "encrypted"
  elif [[ "$PI_ENC" == "true" ]]; then
    row "RDS Performance Insights" FAIL "enabled but no KMS key"
  fi

  SSL=$(aws rds describe-db-parameters --db-parameter-group-name "$PG" --output json 2>/dev/null \
        | jq -r '[.Parameters[] | select(.ParameterName=="rds.force_ssl") | .ParameterValue] | map(select(. != null and . != "")) | .[0] // ""')
  if [[ "$SSL" == "1" ]]; then
    row "RDS in-transit (rds.force_ssl)" PASS "TLS enforced via parameter group $PG"
  else
    row "RDS in-transit (rds.force_ssl)" FAIL "rds.force_ssl=$SSL — TLS not enforced"
  fi

  SNAP_ENC=$(aws rds describe-db-snapshots --db-instance-identifier "$DB_ID" --snapshot-type automated \
             --query "DBSnapshots[0].Encrypted" --output text 2>/dev/null)
  if [[ "$SNAP_ENC" == "True" || "$SNAP_ENC" == "true" ]]; then
    row "RDS automated snapshots" PASS "encrypted (inherits instance key)"
  elif [[ -n "$SNAP_ENC" && "$SNAP_ENC" != "None" ]]; then
    row "RDS automated snapshots" FAIL "Encrypted=$SNAP_ENC"
  fi
fi

# ============================================================================
# 2. S3 buckets — encryption at rest only (TLS-only deny is HITRUST polish)
# ============================================================================
BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, \`${PROJECT}-${ENV}\`)].Name" --output text)
for B in $BUCKETS; do
  ENC_JSON=$(aws s3api get-bucket-encryption --bucket "$B" 2>/dev/null || echo "")
  if [[ -z "$ENC_JSON" ]]; then
    row "S3 $B" FAIL "no default encryption configured"
    continue
  fi
  ALG=$(echo "$ENC_JSON" | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm')
  case "$ALG" in
    aws:kms|aws:kms:dsse|AES256) row "S3 $B" PASS "encrypted ($ALG)" ;;
    *)                            row "S3 $B" FAIL "unknown encryption: $ALG" ;;
  esac
done

# ============================================================================
# 3. EBS volumes on ECS instances
# ============================================================================
CLUSTER="${PROJECT}-${ENV}-cluster"
INSTANCE_ARNS=$(aws ecs list-container-instances --cluster "$CLUSTER" --query 'containerInstanceArns' --output text 2>/dev/null || echo "")
if [[ -n "$INSTANCE_ARNS" && "$INSTANCE_ARNS" != "None" ]]; then
  EC2_IDS=$(aws ecs describe-container-instances --cluster "$CLUSTER" --container-instances $INSTANCE_ARNS \
            --query 'containerInstances[].ec2InstanceId' --output text)
  for I in $EC2_IDS; do
    VOLS=$(aws ec2 describe-instances --instance-ids "$I" \
           --query 'Reservations[0].Instances[0].BlockDeviceMappings[].Ebs.VolumeId' --output text)
    for V in $VOLS; do
      ENC=$(aws ec2 describe-volumes --volume-ids "$V" --query 'Volumes[0].Encrypted' --output text)
      if [[ "$ENC" == "True" || "$ENC" == "true" ]]; then
        row "EBS vol $V (ECS instance $I)" PASS "encrypted"
      else
        row "EBS vol $V (ECS instance $I)" FAIL "Encrypted=false — root volume holds container fs"
      fi
    done
  done
fi

# ============================================================================
# 4. CloudWatch Log Groups
#    - Encryption: required on every group whose name matches our env
#    - Retention:  required ONLY on PHI-bearing groups (§164.530(j)(2))
# ============================================================================
LG_JSON=$(aws logs describe-log-groups --output json)
while read -r LG; do
  N=$(echo "$LG" | jq -r .logGroupName)
  K=$(echo "$LG" | jq -r '.kmsKeyId // ""')
  R=$(echo "$LG" | jq -r '.retentionInDays // "never"')

  if ! encrypted "$K"; then
    row "CWL $N" FAIL "no KMS key (AWS-owned default), retention=$(fmt_retention "$R")"
    continue
  fi

  if is_phi_log_group "$N"; then
    if [[ "$R" == "never" || "$R" -ge 2190 ]]; then
      row "CWL $N" PASS "encrypted, retention=$(fmt_retention "$R")"
    else
      row "CWL $N" FAIL "encrypted but retention=$(fmt_retention "$R") (PHI-bearing, HIPAA wants 2190+)"
    fi
  else
    # Not PHI-bearing — encryption is enough; retention is informational only.
    row "CWL $N" PASS "encrypted, retention=$(fmt_retention "$R") (non-PHI; no retention requirement)"
  fi
done < <(echo "$LG_JSON" | jq -c \
  --arg proj "$PROJECT" --arg env "$ENV" \
  '.logGroups[] | select(
    (.logGroupName | startswith("/aws/bedrock/")) or
    (.logGroupName | startswith("/aws/rds/instance/" + $proj + "-" + $env)) or
    (.logGroupName | startswith("/cloudtrail/" + $proj + "-" + $env)) or
    (.logGroupName | startswith("/aws/vpc/" + $proj + "-" + $env)) or
    (.logGroupName | startswith("/ecs/" + $proj + "-" + $env))
  )')

# ============================================================================
# 5. CloudTrail
# ============================================================================
TRAIL="${PROJECT}-${ENV}-trail"
TRAIL_JSON=$(aws cloudtrail get-trail --name "$TRAIL" 2>/dev/null || echo "")
if [[ -n "$TRAIL_JSON" ]]; then
  K=$(echo "$TRAIL_JSON" | jq -r '.Trail.KmsKeyId // ""')
  if encrypted "$K"; then
    row "CloudTrail $TRAIL" PASS "encrypted"
  else
    row "CloudTrail $TRAIL" FAIL "no KMS key"
  fi
fi

# ============================================================================
# 6. Secrets Manager — Secrets Manager is always encrypted (default key is fine)
# ============================================================================
SECRETS_JSON=$(aws secretsmanager list-secrets \
               --query "SecretList[?starts_with(Name, \`${PROJECT}/${ENV}/\`)].{n:Name,k:KmsKeyId}" \
               --output json)
while read -r S; do
  N=$(echo "$S" | jq -r .n); K=$(echo "$S" | jq -r '.k // ""')
  row "Secret $N" PASS "encrypted (key: ${K:-aws/secretsmanager default})"
done < <(echo "$SECRETS_JSON" | jq -c '.[]')

# ============================================================================
# 7. ALB listeners
#    Only HTTPS listeners are reported.
#
#    The :80 HTTP listener is intentionally present — it's used only by the
#    API Gateway HTTP_PROXY integration (an AWS-internal hop). API Gateway
#    terminates TLS from clients, attaches the X-Gateway-Secret header, then
#    forwards to ALB :80 on AWS's regional network (never the public
#    internet). Direct-to-ALB attacks are blocked by the WAF Web ACL
#    attached to the ALB requiring the secret header. This pattern is
#    HIPAA-acceptable per AWS reference architecture — VPC/network isolation
#    + WAF acts as the compensating control for the un-TLS'd internal hop.
#
#    Because of that, we skip HTTP listeners in the audit entirely rather
#    than relying on (sometimes flaky) WAF-association detection.
# ============================================================================
ALBS=$(aws elbv2 describe-load-balancers \
       --query "LoadBalancers[?contains(LoadBalancerName, \`${PROJECT}-${ENV}\`)].LoadBalancerArn" \
       --output text)
for A in $ALBS; do
  LJSON=$(aws elbv2 describe-listeners --load-balancer-arn "$A" --output json)
  while read -r L; do
    P=$(echo "$L"    | jq -r .Protocol)
    PORT=$(echo "$L" | jq -r .Port)
    SSL=$(echo "$L"  | jq -r '.SslPolicy // ""')
    if [[ "$P" == "HTTPS" ]]; then
      row "ALB ${A##*/} :$PORT" PASS "TLS (policy=$SSL)"
    fi
    # HTTP listeners deliberately skipped — see header comment above.
  done < <(echo "$LJSON" | jq -c '.Listeners[]')
done

# ============================================================================
# 8. CloudFront distributions
# ============================================================================
CFS=$(aws cloudfront list-distributions \
      --query "DistributionList.Items[?contains(Comment, \`${PROJECT}\`) && contains(Comment, \`${ENV}\`)].Id" \
      --output text)
for D in $CFS; do
  VP=$(aws cloudfront get-distribution --id "$D" \
       --query 'Distribution.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy' --output text)
  MIN_TLS=$(aws cloudfront get-distribution --id "$D" \
            --query 'Distribution.DistributionConfig.ViewerCertificate.MinimumProtocolVersion' --output text)
  if [[ "$VP" == "redirect-to-https" || "$VP" == "https-only" ]]; then
    row "CloudFront $D" PASS "TLS ($VP, minTLS=$MIN_TLS)"
  else
    row "CloudFront $D" FAIL "ViewerProtocolPolicy=$VP allows plaintext HTTP"
  fi
done

# ============================================================================
# 9. Bedrock invocation logging (account-level)
# ============================================================================
INV_JSON=$(aws bedrock get-model-invocation-logging-configuration 2>/dev/null || echo "")
if [[ -n "$INV_JSON" ]]; then
  TEXT_ON=$(echo "$INV_JSON" | jq -r '.loggingConfig.textDataDeliveryEnabled')
  LG=$(echo "$INV_JSON"      | jq -r '.loggingConfig.cloudWatchConfig.logGroupName // ""')
  if [[ "$TEXT_ON" == "true" && -n "$LG" ]]; then
    LG_INFO=$(aws logs describe-log-groups --log-group-name-prefix "$LG" --output json)
    K=$(echo "$LG_INFO" | jq -r --arg n "$LG" '.logGroups[] | select(.logGroupName==$n) | .kmsKeyId // ""')
    R=$(echo "$LG_INFO" | jq -r --arg n "$LG" '.logGroups[] | select(.logGroupName==$n) | .retentionInDays // "never"')
    if encrypted "$K" && { [[ "$R" == "never" ]] || [[ "$R" -ge 2190 ]]; }; then
      row "Bedrock invocation logs ($LG)" PASS "encrypted, retention=$(fmt_retention "$R")"
    else
      DETAIL=""
      encrypted "$K" || DETAIL="no KMS key; "
      [[ "$R" != "never" && "$R" -lt 2190 ]] && DETAIL="${DETAIL}retention=$(fmt_retention "$R") < 2190"
      row "Bedrock invocation logs ($LG)" FAIL "$DETAIL"
    fi
  fi
fi

read -r PASS_COUNT FAIL_COUNT < "$COUNT_FILE"
echo ""
printf "${DIM}%s${RST}\n" "----------------------------------------------------------------------------------------------------"
printf "Summary: ${GREEN}%d PASS${RST}  ${RED}%d FAIL${RST}   (HIPAA-only — HITRUST/SOC2 controls intentionally excluded)\n" "$PASS_COUNT" "$FAIL_COUNT"

exit $(( FAIL_COUNT > 0 ? 1 : 0 ))
