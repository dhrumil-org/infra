# Eraser.io AWS Diagram Generator — Prompt

Paste the block below into https://www.eraser.io/ai/aws-diagram-generator and click Generate. Tweak labels after if needed, export PNG/SVG, embed in the HIPAA compliance doc above §3.

---

## Prompt to paste

```
Generate an AWS architecture diagram for a HIPAA-compliant clinical SaaS
application called vocuone, running in a single AWS account in us-east-1
with separate stage and prod environments.

External:
- End users are clinicians on web browsers.

Edge layer (regional, outside VPC):
- Amazon CloudFront distribution serving the frontend with TLS 1.2+
  (ACM certificate). Originates from a private S3 bucket via OAC.
- Amazon API Gateway (REST) handling all backend API traffic over TLS 1.2+.

Application layer (inside a single custom VPC across 2 AZs):
- An internet-facing Application Load Balancer with three listeners:
  HTTPS on 443 (production traffic from CloudFront), HTTPS on 8443 (test
  listener used by CodeDeploy blue/green), and HTTP on 80 (used only by
  API Gateway HTTP_PROXY integration).
- AWS WAF (WAFv2) Web ACL attached to the ALB, requiring a custom
  X-Gateway-Secret header on every request to block any direct hits.
- ECS cluster on EC2 (Amazon Linux 2023 ECS-optimized AMI) running a
  Spring Boot Java application as ECS tasks, all in private subnets.
- Auto Scaling Group manages the EC2 instances; CodeDeploy performs
  blue/green deployments between two ECS target groups.
- Amazon RDS for PostgreSQL in private subnets, Multi-AZ in prod,
  with IAM database authentication and SSL forced at the parameter group.

AI / data layer:
- Amazon Bedrock for LLM inference (Claude Sonnet + Haiku models).
- Amazon Bedrock Knowledge Base backed by three S3 buckets
  (kb-data, kb-source, kb-assets) and an S3 Vectors index.
- Amazon Bedrock Agent for conversational orchestration.

Storage & secrets:
- AWS Secrets Manager for database credentials and third-party API keys.
- Amazon ECR for the application's Docker images.
- Three additional S3 buckets: ALB access logs, CloudTrail logs,
  CodePipeline artifacts.

Encryption:
- AWS KMS with separate customer-managed keys for each data domain:
  one for CloudWatch Logs + CloudTrail + EBS, one for RDS, one for
  Secrets Manager, one for ECR, one for AWS Backup, and a dedicated
  key for Bedrock invocation logs.

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
- AWS CodePipeline triggered by ECR image push (EventBridge rule)
- AWS CodeBuild producing the task definition
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
- Three horizontal swim lanes: Public Edge (top), VPC (middle, with
  public subnets stacked above private subnets), and Audit /
  Observability (bottom).
- Color-code data flows: green for TLS-encrypted PHI paths, dashed
  orange for AWS-internal plaintext paths (API Gateway → ALB :80,
  ALB → ECS task), grey for audit/log writes, blue for alerting
  fan-out.
- Use official AWS service icons.
- Label every cross-service edge with the protocol (HTTPS / HTTP /
  TLS) and the auth mechanism (IAM role, IAM auth, ACM cert,
  OIDC).
```

---

## After generating

1. Eraser will produce the diagram with editable shapes.
2. Verify these key annotations are present (add manually if not):
   - "ALB :80 = AWS-internal only, WAF-gated"
   - "RDS: Multi-AZ, CMK, force_ssl=1, IAM auth, PITR"
   - "All CWL groups: CMK + 7yr retention (PHI groups)"
   - "OIDC roles pinned to repo + branch + env"
3. Export as **PNG (transparent) at 2x scale** for the Word document,
   or **SVG** if you'll resize.
4. Drop into `docs/HIPAA-COMPLIANCE.docx` above §3 (replacing the
   ASCII art).
5. Save the source file (`.eraser` or whatever Eraser exports) under
   `docs/architecture/` so the diagram is regenerable.
