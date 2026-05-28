# Eraser.io AWS Diagram Generator — Prompt

Paste the block below into https://www.eraser.io/ai/aws-diagram-generator and click Generate. Tweak labels after if needed, export PNG/SVG, embed in the HIPAA compliance doc above §3.

---

## Prompt to paste

```
Generate an AWS architecture diagram for a HIPAA-compliant clinical SaaS
application called vocuone, running in a single AWS account in us-east-1
with separate stage and prod environments. The product has two distinct
frontend surfaces (clinician app and internal admin console) that share
a single backend.

External users:
- Clinicians on web browsers (use the clinician app frontend).
- Internal operations staff on web browsers (use the admin console).

Frontend hosting — TWO separate static-site stacks:

1. Clinician app frontend ("vocuone-frontend"):
   - Amazon CloudFront distribution with TLS 1.2+ (ACM certificate),
     viewer protocol policy redirect-to-https.
   - Origin: private S3 bucket containing the React build (JS, CSS, HTML).
   - Access from CloudFront to S3 via Origin Access Control (OAC).
   - Bucket has BlockPublicAccess on; bucket policy denies all access
     except the specific CloudFront distribution.
   - DNS aliases: stage-app.vocuone.ai / app.vocuone.ai.

2. Admin console frontend ("vocuone-admin"):
   - Identical pattern: separate CloudFront distribution + separate
     private S3 bucket via OAC.
   - DNS alias: admin.vocuone.ai (with stage variant).
   - Serves only internal staff; authentication enforced at the
     application layer with a separate JWT scope from the clinician
     app, but infra-side controls (S3 OAC, CloudFront TLS) are
     identical.

Note: Both frontend S3 buckets contain only static JS/CSS/HTML — no PHI
is stored at rest in them. The browser running the JavaScript handles
PHI in memory and sends/receives it via the backend API.

Backend edge layer (regional, outside VPC):
- Amazon API Gateway (REST) handling all backend API traffic over
  TLS 1.2+. Both frontends call the same API.

Backend application layer (inside a single custom VPC across 2 AZs):
- An internet-facing Application Load Balancer with three listeners:
  HTTPS on 443 (production traffic from CloudFront), HTTPS on 8443
  (test listener used by CodeDeploy blue/green), and HTTP on 80
  (used only by API Gateway HTTP_PROXY integration).
- AWS WAF (WAFv2) Web ACL attached to the ALB, requiring a custom
  X-Gateway-Secret header on every request to block any direct hits.
- ECS cluster on EC2 (Amazon Linux 2023 ECS-optimized AMI) running a
  Spring Boot Java application as ECS tasks, all in private subnets.
- Auto Scaling Group manages the EC2 instances; CodeDeploy performs
  blue/green deployments between two ECS target groups.
- Amazon RDS for PostgreSQL in private subnets, Multi-AZ in prod,
  with IAM database authentication and SSL forced at the parameter
  group level.

AI / data layer:
- Amazon Bedrock for LLM inference (Claude Sonnet + Haiku models).
- Amazon Bedrock Knowledge Base backed by three S3 buckets
  (kb-data, kb-source, kb-assets) and an S3 Vectors index.
- Amazon Bedrock Agent for conversational orchestration.

Storage & secrets:
- AWS Secrets Manager for database credentials and third-party API keys.
- Amazon ECR for the backend application's Docker images.
- Three additional S3 buckets: ALB access logs, CloudTrail logs,
  CodePipeline artifacts.

Encryption (KMS):
- AWS KMS with separate customer-managed keys for each data domain:
  one for CloudWatch Logs + CloudTrail + EBS, one for RDS, one for
  Secrets Manager, one for ECR, one for AWS Backup, and a dedicated
  key for Bedrock invocation logs.
- Frontend S3 buckets use SSE-S3 (AWS-managed) since they hold no PHI.

Audit / observability (account-wide):
- AWS CloudTrail capturing management events plus S3 data events on
  the Knowledge Base buckets, writing to a dedicated CloudTrail S3
  bucket with log file validation, also tailed to CloudWatch Logs.
- CloudWatch Logs for application logs (/ecs/app), Bedrock invocation
  logs (/aws/bedrock/), RDS PostgreSQL logs (/aws/rds/instance/),
  and VPC Flow Logs — all encrypted with the logs CMK, retention 7
  years for PHI-bearing groups.
- CloudWatch Alarms for ALB 5xx errors, ECS CPU/memory, Bedrock
  latency p95, throttling, and synthetics canary failure — all
  routing to an SNS topic that emails the on-call address.
- Amazon Synthetics canary probing the public API hourly.
- AWS Backup vault for RDS automated snapshots.

CI/CD:
- AWS CodePipeline triggered by ECR image push (EventBridge rule).
- AWS CodeBuild producing the task definition.
- AWS CodeDeploy performing the blue/green ECS deployment, with a
  Lambda function (listener-presync) running as a deployment hook.
- GitHub Actions authenticates via AWS IAM OIDC provider (no long-
  lived access keys); two roles (stage-oidc and prod-oidc) with
  branch- and environment-pinned sub claims.

Network:
- Custom VPC with public subnets (ALB, NAT Gateways) and private
  subnets (ECS, RDS).
- NAT Gateway for outbound egress from private subnets.
- VPC endpoints (gateway + interface) for in-VPC routing to S3,
  ECR, Secrets Manager, KMS, CloudWatch Logs.
- Route 53 for DNS, ACM for TLS certificates.

Layout preference:
- Four horizontal swim lanes:
  1. Frontend Edge (top): both CloudFront distributions + their S3
     buckets, shown side by side
  2. Backend Edge: API Gateway + WAF
  3. VPC (middle, with public subnets stacked above private subnets):
     ALB, NAT, ECS, RDS, Bedrock connections
  4. Audit / Observability (bottom): CloudTrail, CloudWatch Logs,
     AWS Backup, alarms, SNS
- Color-code data flows:
  - Green: TLS-encrypted PHI paths
  - Dashed orange: AWS-internal plaintext paths (API Gateway → ALB :80,
    ALB → ECS task)
  - Grey: audit/log writes
  - Blue: alerting fan-out
- Use official AWS service icons.
- Label every cross-service edge with the protocol (HTTPS / HTTP /
  TLS) and the auth mechanism (IAM role, IAM auth, ACM cert, OIDC,
  OAC for S3).
```

---

## After generating

1. Eraser will produce the diagram with editable shapes.
2. Verify these key annotations are present (add manually if not):
   - "ALB :80 = AWS-internal only, WAF-gated"
   - "Both frontend S3 buckets = static assets, no PHI at rest"
   - "RDS: Multi-AZ, CMK, force_ssl=1, IAM auth, PITR"
   - "All CWL groups: CMK + 7yr retention (PHI groups)"
   - "OIDC roles pinned to repo + branch + env"
3. Export as **PNG (transparent) at 2x scale** for the Word document,
   or **SVG** if you'll resize.
4. Drop into `docs/HIPAA-COMPLIANCE.docx` above §3 (replacing the
   ASCII art).
5. Save the source file (`.eraser` or whatever Eraser exports) under
   `docs/architecture/` so the diagram is regenerable.
