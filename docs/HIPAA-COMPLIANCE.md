# HIPAA Compliance Attestation — vocuone

| Property | Value |
|---|---|
| Version | 1.0 |
| Last updated | 2026-05-19 |
| Owner | DevOps Lead |
| Status | Draft for review |
| Scope | AWS account `499290259511`, region `us-east-1`, envs `stage` + `prod` |
| Components | Clinician app (frontend + backend), Admin console (frontend + shared backend), Bedrock AI |
| Standards | HIPAA Security Rule (45 CFR §164.302–.318), §164.530(j)(2), AWS HIPAA Shared Responsibility Model, NIST SP 800-66 |

---

## 1. Executive Summary

vocuone runs a clinical case-companion application (clinician web app + internal admin console + Bedrock-backed AI) processing PHI exclusively on HIPAA-eligible AWS services under a signed BAA. All technical safeguards are implemented as code in this Terraform repository and continuously verified by `scripts/hipaa-encryption-audit.sh`.

| HIPAA Section | Status |
|---|---|
| §164.308 Administrative | Compliant |
| §164.310 Physical | Inherited from AWS via BAA |
| §164.312 Technical | Compliant |
| §164.314 Organizational | AWS BAA in force |
| §164.316 / §164.530(j)(2) Docs + 7yr retention | Compliant |

---

## 2. Scope

**In scope:** AWS account `499290259511`, us-east-1, stage + prod environments. Three product surfaces share a single backend and data plane:

| Surface | Audience | Frontend hosting | Backend |
|---|---|---|---|
| Clinician app | Doctors / care team | CloudFront + private S3 (OAC) | Shared ECS API |
| Admin console | Internal operations | CloudFront + private S3 (OAC) | Shared ECS API |
| AI / KB | (Server-side only) | n/a | Bedrock + Bedrock Agent + KB |

Traffic path: client → CloudFront (frontend static assets) **and** client → API Gateway → ALB → ECS task → RDS / Bedrock / S3.

**Out of scope:** Application code (separate review), endpoint security, AWS physical security (BAA-inherited).

---

## 3. Architecture

```
                                ┌─── CloudFront (clinician app)  ──► S3 (app bucket, private, OAC)
[Clinician browser] ─TLS1.2+──┤
                                └─── API Gateway ─HTTP*─► ALB:80 ──► ECS task ──┐
                                                                                 │
                                ┌─── CloudFront (admin console) ─► S3 (admin bucket, private, OAC)
[Admin operator]    ─TLS1.2+──┤
                                └─── API Gateway ─HTTP*─► ALB:80 ──► ECS task ──┤
                                                                                 │
                                                                                 ▼
                            ┌────────────────────────────┬──────────────────────┴──────────────┐
                            ▼                            ▼                                     ▼
                      [RDS PostgreSQL]            [Bedrock KB + Agent]                  [CloudWatch Logs]
                      (Multi-AZ, CMK, TLS)         (S3 KB buckets, SSE-S3)               (CMK, 7yr retention)
                            │                                                                  ▲
                            └──► AWS Backup vault (CMK) + automated snapshots                  │
                                                                                              │
[All AWS API calls] ─────────────────────────────────────► [CloudTrail S3 (CMK) + CWL tail]

* API Gateway → ALB :80 hop is plaintext on AWS-internal network only;
  gated by WAF requiring X-Gateway-Secret header. Direct-to-ALB blocked.
```

**Key properties:** every PHI store uses AES-256 (CMK where customer-managed); all public-facing TLS 1.2+; both frontend S3 buckets are private (CloudFront-only access via OAC) and contain only static JS/CSS — **no PHI ever lives in the frontend buckets**; ECS tasks in private subnets with no public IP; RDS reachable only from ECS security group with `rds.force_ssl=1`; WAF gates the ALB; CloudTrail log file validation on.

---

## 4. AWS Services & HIPAA Eligibility

Every service handling PHI is on the current AWS HIPAA Eligible Services Reference list.

| Service | Purpose | PHI at rest? |
|---|---|---|
| EC2 + ECS + EBS | App compute (shared backend for both frontends) | Transient |
| RDS PostgreSQL | Primary patient DB | Durable |
| S3 — KB buckets (3) | Bedrock KB documents | Durable |
| S3 — Clinician app frontend | Static React build (JS/CSS only) | None |
| S3 — Admin console frontend | Static React build (JS/CSS only) | None |
| CloudFront (× 2 — app + admin) | Frontend CDN with TLS 1.2+ | In-flight |
| Bedrock + Bedrock Agents | LLM inference, KB retrieval | In-flight + retrieval |
| API Gateway + ALB + WAF | Public API ingress | In-flight |
| Lambda | CodeDeploy hook, Synthetics canary | No |
| CloudWatch + CloudTrail | Audit + logs | Durable (audit) |
| Secrets Manager | DB creds, frontend env configs | Creds only |
| KMS | Encryption keys | No (keys) |
| AWS Backup | Cross-service backup | Durable (snapshots) |
| VPC, Route 53, ACM, Inspector, SSM, EventBridge, SNS, Synthetics, CodePipeline/Deploy/Build | Supporting | No / N/A |

Audit script confirms only HIPAA-eligible services are touched.

---

## 5. Technical Safeguards (§164.312)

### Encryption at rest (§164.312(a)(2)(iv))

Every PHI store is AES-256 encrypted; frontend buckets contain no PHI but are still encrypted:

| Store | Key |
|---|---|
| RDS storage + Perf Insights + automated snapshots | CMK `alias/vocuone-${env}-rds` |
| EBS — ECS root volumes | CMK `alias/vocuone-${env}-logs` |
| S3 — Bedrock KB (3 buckets) | AES-256 SSE-S3 (BAA-acceptable) |
| S3 — Clinician app frontend | AES-256 SSE-S3 |
| S3 — Admin console frontend | AES-256 SSE-S3 |
| S3 — ALB logs / pipeline artifacts / canary | AES-256 SSE-S3 |
| S3 — CloudTrail | SSE-KMS, CMK `alias/vocuone-${env}-logs` |
| CWL — app, Bedrock, RDS postgresql, VPC flow, CloudTrail | CMK `alias/vocuone-${env}-logs` (Bedrock has dedicated CMK) |
| Secrets Manager (PHI-bearing) | CMK `alias/vocuone-${env}-secrets` |
| AWS Backup vault | CMK `alias/vocuone-${env}-backup` |
| ECR images | CMK `alias/vocuone-${env}-ecr` |

All CMKs have key rotation enabled and a 30-day deletion window. Continuous verification: `bash scripts/hipaa-encryption-audit.sh ${env}`.

### Encryption in transit (§164.312(e))

| Path | Protection |
|---|---|
| Clinician browser → CloudFront (app) | TLS 1.2+ (ACM cert, redirect-to-https viewer policy) |
| Admin operator → CloudFront (admin) | TLS 1.2+ (ACM cert, redirect-to-https viewer policy) |
| CloudFront → S3 frontend buckets | TLS via Origin Access Control (OAC); buckets block all non-CloudFront access |
| Client → API Gateway | TLS 1.2+ (AWS-managed) |
| CloudFront / API Gateway → ALB :443 | TLS 1.2+ (`ELBSecurityPolicy-TLS13-1-2-2021-06`) |
| API Gateway → ALB :80 | HTTP on AWS regional network; WAF gate (`X-Gateway-Secret`); compensating control per AWS HIPAA reference architecture |
| ALB → ECS task | HTTP intra-VPC private subnet; SG-restricted; AWS-standard pattern |
| ECS → RDS | TLS enforced (`rds.force_ssl=1`) |
| ECS → AWS services (Bedrock, S3, Secrets Mgr, CloudWatch) | HTTPS by default (AWS SDK) |

### Access control (§164.312(a)(1))

- **Apps**: ECS task IAM roles with per-task credentials via IMDSv2; RDS IAM database auth + Secrets Manager-vended password (dual auth).
- **Frontend buckets**: S3 bucket policy denies all access except the specific CloudFront distribution via OAC; no public access; `BlockPublicAccess` enforced at the bucket level.
- **Admin console**: identical S3+CloudFront pattern as clinician app; admin authentication happens at the application layer (separate JWT scope) — infra-side controls are identical to the clinician app.
- **CI/CD**: GitHub Actions OIDC `sts:AssumeRoleWithWebIdentity`, `sub`/`aud` claims pinned to repo + branch + environment. No long-lived CI keys.
- **Operators**: SSM Session Manager (no SSH); MFA on console; CloudTrail logged.
- **Service-to-service**: trust policies with `aws:SourceAccount` + `aws:SourceArn` confused-deputy guards.

### Audit controls + integrity (§164.312(b), (c))

- CloudTrail (all API events + KB S3 data events) → S3 (no expiry) + CWL tail (365d); log file validation on.
- App/Bedrock/RDS audit log groups: CMK + 2557d (7yr) retention per §164.530(j)(2).
- CloudFront access logs: optional, sent to a separate S3 bucket with SSE-S3 if enabled.
- KMS key rotation, S3 versioning on KB buckets, RDS PITR.

### Authentication (§164.312(d))

JWT for end users (separate scopes for clinician vs admin); OIDC for CI; IAM roles for services; MFA + SSM for operators.

---

## 6. Administrative Safeguards (§164.308)

| Sub-section | Implementation |
|---|---|
| (a)(1) Security mgmt | Risk analysis = this doc + audit script; quarterly review |
| (a)(2) Security Officer | DevOps Lead (named in Sign-off) |
| (a)(3) Workforce security | IAM access via Terraform; termination removes IAM identity ≤24h |
| (a)(4) Min necessary | Per-role IAM policies; access changes via PR + OIDC apply |
| (a)(6) Incident procedures | CloudWatch alarms → SNS → on-call; CloudTrail for forensics |
| (a)(7) Contingency | Multi-AZ RDS (prod), PITR 7d, AWS Backup vault, full IaC for rebuild |
| (a)(8) Evaluation | Self-attestation + continuous audit script; third-party assessment planned |

---

## 7. Physical Safeguards (§164.310)

Inherited from AWS via the signed BAA. AWS SOC 1/2/3, ISO 27001/17/18, FedRAMP authorizations cover facility access, workstation use, device/media controls for the underlying infrastructure. Customer-side endpoint security under separate device-management policy.

---

## 8. Organizational Requirements (§164.314)

AWS BAA signed via AWS Artifact, covering all HIPAA-eligible services in use. No subcontractor BAAs currently needed — Sentry/SendGrid/Google Calendar are configured for non-PHI events only.

---

## 9. Documentation & Retention (§164.316, §164.530(j)(2))

- Policy: this document + Terraform code as source of truth
- PHI-bearing audit logs: 2557d (7 years) retention — app, Bedrock, RDS postgres, CloudTrail S3
- Non-PHI logs (VPC flow, CT tail, CloudFront access logs): 365d
- Git history = full audit trail of infrastructure changes

---

## 10. Continuous Verification

**Audit script** (`scripts/hipaa-encryption-audit.sh`): enumerates every PHI-handling resource, verifies encryption + retention; non-zero exit on failure; CI-runnable.

**Active monitoring** (CloudWatch alarms → SNS → email):
- Backend HTTP 5xx (ALB target + ELB layer)
- ECS CPU / memory
- Bedrock latency p95, invocation throttling, errors
- Synthetics canary failures (probes both CloudFront distributions + the API)
- App-level AI call error rate (metric filter on `/ecs/${env}-app`)

---

## 11. KMS Key Inventory

| Alias | Purpose |
|---|---|
| `alias/vocuone-${env}-logs` | CloudWatch Logs, CloudTrail, SNS, EBS, ECR |
| `alias/vocuone-${env}-rds` | RDS storage + Perf Insights |
| `alias/vocuone-${env}-secrets` | Secrets Manager (PHI) |
| `alias/vocuone-${env}-ecr` | ECR image layers |
| `alias/vocuone-${env}-backup` | AWS Backup vault |
| `alias/vocuone-bedrock-invocations` | Bedrock invocation logs (account-wide singleton) |

All CMKs: rotation enabled, 30-day deletion window. Frontend S3 buckets use SSE-S3 (AWS-managed) since they hold no PHI; HIPAA-acceptable under BAA.

---

## 12. Sign-off

The undersigned acknowledges the safeguards described, the signed AWS BAA, and the continuous-verification mechanism.

| Role | Name | Signature | Date |
|---|---|---|---|
| Security Officer (DevOps Lead) | | | |
| Privacy Officer | | | |
| CTO / Engineering Lead | | | |

---

## Appendix — References

- 45 CFR §160, §162, §164 — HIPAA Rules
- NIST SP 800-66 Rev. 2 — HIPAA implementation guide
- AWS HIPAA Compliance — https://aws.amazon.com/compliance/hipaa-compliance/
- AWS HIPAA Eligible Services Reference — https://aws.amazon.com/compliance/hipaa-eligible-services-reference/
- HHS Guidance on HIPAA & Cloud Computing — https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html
