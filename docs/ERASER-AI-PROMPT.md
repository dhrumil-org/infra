# Eraser.io AWS Diagram Generator — Prompt

Paste the block below into https://www.eraser.io/ai/aws-diagram-generator and click Generate. Tweak labels after if needed, export PNG/SVG, save under `docs/architecture/`, embed in the HIPAA compliance doc above §3.

---

## Prompt to paste

```
Generate an AWS architecture diagram for a HIPAA-compliant clinical SaaS
application called vocuone, running in a single AWS account in us-east-1
across two Availability Zones, with separate stage and prod environments.

The product has THREE surfaces that share a single backend and data plane:
  1. Clinician web app (used by doctors / care team)
  2. Internal admin console (used by operations staff)
  3. Bedrock-backed AI (server-side only)

============================================================
EXTERNAL USERS (left side of diagram)
============================================================
- A "Clinicians" user icon (doctors on web browsers)
- A separate "Internal staff" user icon (admin operators on browsers)
- Both groups connect over the public internet with TLS 1.2+

============================================================
FRONTEND EDGE — TWO PARALLEL STATIC-SITE STACKS
============================================================
Show as two SIDE-BY-SIDE rows in the Public Edge lane:

ROW A — Clinician app frontend:
  - Route 53 DNS (alias: stage-app.vocuone.ai / app.vocuone.ai)
  - ACM TLS 1.2+ certificate
  - Amazon CloudFront distribution (viewer protocol = redirect-to-https)
  - Origin: private S3 bucket "S3 app frontend (OAC)" — React build
  - Origin access via Origin Access Control (OAC); bucket has
    BlockPublicAccess on; bucket policy denies all non-CloudFront access
  - Static assets only — no PHI at rest in this bucket

ROW B — Admin console frontend (MIRROR THE STRUCTURE):
  - Route 53 DNS (alias: admin.vocuone.ai with stage variant)
  - Separate ACM TLS 1.2+ certificate
  - Separate Amazon CloudFront distribution (redirect-to-https)
  - Origin: private S3 bucket "S3 admin frontend (OAC)" — React build
  - Same OAC + BlockPublicAccess pattern as the clinician app
  - Static assets only — no PHI at rest

============================================================
BACKEND EDGE (same Public Edge lane, to the right of the frontends)
============================================================
- Amazon API Gateway (REST). BOTH clinician and admin frontends call
  this same API over TLS 1.2+. Show two parallel TLS arrows — one
  from each user, both terminating at API Gateway.
- AWS WAFv2 Web ACL — attached to the ALB (next lane down). Requires
  custom "X-Gateway-Secret" header on every request to block any
  direct-to-ALB hits from outside AWS regional network.

============================================================
VPC LANE — Custom VPC across 2 AZs (us-east-1a, us-east-1b)
============================================================
Box the entire VPC. Inside it, two nested boxes:

PUBLIC SUBNETS (AZ-a, AZ-b):
  - Application Load Balancer (internet-facing), with 3 listeners:
    * HTTPS :443 → forwards to ECS target group (production traffic)
    * HTTPS :8443 → forwards to ECS target group (CodeDeploy test)
    * HTTP :80   → forwards to ECS target group (API Gateway
                   HTTP_PROXY integration only, gated by WAF)
  - NAT Gateway (one for the VPC; egress from private subnets)
  - Internet Gateway (at the VPC boundary)
  - VPC Endpoints (Interface + Gateway): S3 (gw), ECR, Secrets Manager,
    KMS, CloudWatch Logs — so in-VPC traffic stays on AWS backbone

PRIVATE SUBNETS (AZ-a, AZ-b):
  - Auto Scaling Group + EC2 (Amazon Linux 2023 ECS-optimized AMI)
  - ECS Cluster running the Spring Boot Java application as ECS tasks
  - ECS Target Groups (two — blue and green, controlled by CodeDeploy
    blue/green deployment strategy)
  - Amazon RDS for PostgreSQL — Multi-AZ in prod, encrypted with
    customer-managed KMS key, IAM database authentication enabled,
    SSL forced at the parameter group level (rds.force_ssl=1),
    automated backups + PITR
  - AWS Secrets Manager (DB credentials + 3rd-party API keys)
  - Amazon ECR (Docker images for the backend app)
  - AWS Backup Vault (RDS automated snapshots, CMK-encrypted)

============================================================
AI / DATA PLANE (place in the Public Edge lane to the far right,
visually grouped under a "Bedrock" box)
============================================================
- Amazon Bedrock LLM (Claude Sonnet 4.6 + Haiku 4.5 models)
- Amazon Bedrock Knowledge Base
- Amazon Bedrock Agent (conversational orchestration)
- Three S3 KB buckets visually GROUPED together:
    * kb-data    (primary KB content)
    * kb-source  (Bedrock-parsed multimodal extracts)
    * kb-assets  (KB asset storage)
- S3 Vectors index (vector storage for KB embeddings)

============================================================
ENCRYPTION — KMS Customer-Managed Keys
============================================================
Group all six CMKs inside one "AWS KMS — Customer-Managed Keys" box
in the private subnets area. Show each key with the resource it protects:

  - logs/CloudTrail/EBS    → protects CloudWatch Logs, CloudTrail,
                              SNS, EBS volumes, ECR
  - RDS                    → protects RDS storage + Performance Insights
  - Secrets                → protects Secrets Manager
  - ECR                    → ECR image layer encryption (also)
  - Backup                 → AWS Backup vault
  - Bedrock-invocations    → Bedrock invocation log group (account-wide)

============================================================
AUDIT / OBSERVABILITY LANE (bottom — account-wide)
============================================================
- AWS CloudTrail (management events + S3 data events on KB buckets)
- S3 CloudTrail bucket (SSE-KMS, log file validation enabled, no expiry)
- CloudWatch Logs CMK box, containing the PHI-bearing log groups:
    * /ecs/${env}-app                              (Spring Boot app)
    * /aws/bedrock/${project}-invocations          (Bedrock requests)
    * /aws/rds/instance/${env}-db/postgresql       (RDS audit)
    * /aws/rds/instance/${env}-db/upgrade          (RDS upgrade events)
    * /aws/vpc/${env}-flow-logs                    (VPC flow logs)
    * /cloudtrail/${env}                           (CT live-query tail)
  All groups: encrypted with CMK; retention 2557d (7yr) for PHI groups,
  365d for non-PHI metadata groups.
- VPC Flow Logs (the actual flow log source, in VPC)
- EventBridge (triggers CodePipeline on ECR push)
- CloudWatch Alarms (cluster of alarms: ALB 5xx, ECS CPU/memory,
  Bedrock p95 latency, throttling, AI call error rate, canary failure)
- Synthetics Canary (probes the API Gateway hourly over HTTPS) — show
  an explicit arrow from the canary UP to API Gateway labeled
  "HTTPS hourly probe"
- Amazon SNS topic "${project}-${env}-alerts" (on-call email)
- S3 ALB access logs bucket

============================================================
CI/CD LANE (deploy-time only — show in a separate sub-box inside the
private subnet area, OR as a strip across the bottom of the VPC box)
============================================================
- GitHub Actions (external, top-left of CI/CD sub-box) authenticates
  via AWS IAM OIDC provider (sts:AssumeRoleWithWebIdentity).
  Two roles: stage-oidc and prod-oidc. Sub claims pinned to:
    repo:vocanote-ai/{infra,backend,frontend,canary}:ref:refs/heads/{stage,prod}
- IAM OIDC provider
- EventBridge rule (fires on ECR push)
- CodePipeline (orchestrates the deploy)
- CodeBuild (produces taskdef.json)
- CodeDeploy (executes blue/green ECS deployment — show arrow into
  the ECS Target Groups in the private subnet)
- Lambda function "listener-presync" (CodeDeploy AfterAllowTraffic hook)
- S3 Pipeline Artifacts bucket

============================================================
REQUIRED ARROWS (with labels for the auditor)
============================================================
Show every cross-component edge with protocol + auth labels:

PHI in transit (GREEN solid lines):
  - Clinicians  → CloudFront (app)     "TLS 1.2+, ACM cert"
  - Internal staff → CloudFront (admin) "TLS 1.2+, ACM cert"
  - CloudFront (app)   → S3 app   "OAC over TLS (private)"
  - CloudFront (admin) → S3 admin "OAC over TLS (private)"
  - Clinicians  → API Gateway          "TLS 1.2+"
  - Internal staff → API Gateway        "TLS 1.2+"
  - CloudFront (app)   → ALB :443       "HTTPS, ACM cert"
  - ECS task → RDS                      "TLS (rds.force_ssl=1), IAM auth"
  - ECS task → Bedrock                  "HTTPS, IAM task role"
  - ECS task → S3 KB buckets            "HTTPS, IAM task role"
  - ECS task → Secrets Manager          "HTTPS, IAM task role"
  - ECS task → CloudWatch Logs          "HTTPS via VPC endpoint"
  - Synthetics canary → API Gateway     "HTTPS hourly probe"

PHI on AWS-internal network (DASHED ORANGE — compensating control):
  - API Gateway → ALB :80   "HTTP + X-Gateway-Secret header, AWS regional net"
  - ALB → ECS task          "HTTP intra-VPC, SG-restricted"

Audit/log flows (THIN GREY):
  - ECS task → CloudWatch Logs (/ecs/app)
  - Bedrock → CloudWatch Logs (/aws/bedrock/)
  - RDS → CloudWatch Logs (/aws/rds/instance/)
  - RDS → AWS Backup Vault   "automated snapshots, CMK-encrypted"
  - VPC → VPC Flow Logs → CloudWatch Logs
  - All AWS API calls → CloudTrail → S3 CloudTrail bucket
  - ALB → S3 ALB access logs

Alerting (THIN BLUE):
  - CloudWatch Alarms → SNS topic → on-call email

CI/CD (DOTTED, deploy-time only):
  - GitHub Actions → IAM OIDC → CodePipeline (OIDC AssumeRoleWithWebIdentity)
  - ECR push → EventBridge → CodePipeline
  - CodePipeline → CodeBuild → CodeDeploy
  - CodeDeploy → ECS Target Groups (blue/green swap)
  - CodeDeploy → listener-presync Lambda (deployment hook)

============================================================
KEY ANNOTATIONS (small text callouts on the diagram)
============================================================
  - "ALB :80 = AWS-internal only, WAF-gated"
  - "Both frontend S3 buckets = static assets only, no PHI at rest"
  - "RDS: Multi-AZ, CMK, force_ssl=1, IAM auth, PITR 7d"
  - "All CWL groups: CMK + 7yr retention (PHI groups), 365d (non-PHI)"
  - "OIDC roles pinned to repo + branch + environment claim"
  - "Customer-managed KMS keys: rotation enabled, 30-day deletion window"

============================================================
LAYOUT
============================================================
- Four horizontal swim lanes top to bottom:
    1. Public Edge (Regional) — frontends, edge, Bedrock data plane
    2. Custom VPC (us-east-1, 2 AZs)
         a. Public Subnets (top of VPC box)
         b. Private Subnets (bottom of VPC box, with CI/CD sub-box)
    3. Audit / Observability (account-wide)
- Use official AWS service icons everywhere.
- Two parallel user paths (clinician + admin) at the top-left.
- Group the Bedrock KB buckets visually under "Bedrock KB" so they
  don't look like edge buckets.

============================================================
COLOR LEGEND (include in bottom-right corner)
============================================================
  - GREEN solid     = TLS-encrypted PHI path
  - ORANGE dashed   = AWS-internal plaintext (compensating control applies)
  - GREY thin       = Audit / log writes
  - BLUE thin       = Alerting fan-out
  - DOTTED          = CI/CD (deploy-time only, no PHI traffic)
```

---

## After eraser generates the diagram

1. **Verify the admin console is rendered** — there should be TWO CloudFront → S3 paths in the Public Edge lane, not one. If only one appears, paste this corrective prompt:

   > Add a second frontend stack to the Public Edge lane representing the internal admin console: separate "Internal staff" user icon, separate CloudFront distribution, separate private S3 bucket via OAC, separate ACM cert, DNS alias admin.vocuone.ai. The admin frontend calls the SAME API Gateway as the clinician app (show a second TLS arrow from Internal staff to API Gateway, parallel to the clinician one). Mirror all styling.

2. **Verify these annotations appear** (add manually in eraser if missing):
   - "ALB :80 = AWS-internal only, WAF-gated"
   - "Both frontend S3 buckets = static assets, no PHI at rest"
   - "RDS: Multi-AZ, CMK, force_ssl=1, IAM auth, PITR"
   - "All CWL groups: CMK + 7yr retention (PHI groups)"

3. **Verify critical arrows are present:**
   - Canary → API Gateway (HTTPS hourly probe)
   - RDS → AWS Backup Vault (automated snapshots)
   - ECS task → CloudWatch Logs (/ecs/app) — explicit, not implied

4. **Export:**
   - Save the eraser source as `docs/architecture/architecture.eraser`
   - Export PNG (transparent background, 2x or 4x scale) as `docs/architecture/architecture.png`
   - Export SVG as `docs/architecture/architecture.svg`

5. **Embed in Word doc:**
   - Open `docs/HIPAA-COMPLIANCE.docx`
   - Right-click the dashed placeholder box in §3 → Cut
   - Insert → Pictures → choose `architecture.png`
   - Save and commit all four files together (.eraser, .png, .svg, .docx)
