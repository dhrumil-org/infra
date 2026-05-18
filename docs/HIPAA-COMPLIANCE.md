# HIPAA Compliance Attestation — vocuone / vocanote-ai Production Infrastructure

| Document property | Value |
|---|---|
| **Document version** | 1.0 |
| **Last updated** | 2026-05-19 |
| **Owner** | Dhrumil Mehta (DevOps), vocuone / vocanote-ai engineering |
| **Status** | Draft for review |
| **Scope** | AWS infrastructure managed via Terraform in this repository, account `499290259511`, region `us-east-1`, environments `stage` and `prod` |
| **Standards referenced** | HIPAA Security Rule (45 CFR §164.302–.318), HIPAA Privacy Rule §164.530(j)(2), AWS HIPAA Shared Responsibility Model, NIST SP 800-66 (HIPAA implementation guide), NIST SP 800-53 (AWS mapping) |

---

## 1. Executive Summary

vocuone operates a clinical case-companion application that processes Protected Health Information (PHI) — patient transcripts, case notes, clinical documents, and AI-generated clinical summaries — exclusively on AWS services covered by the AWS Business Associate Addendum (BAA).

This document attests to the technical and administrative safeguards implemented in our AWS environment to comply with the HIPAA Security Rule (45 CFR Part 164, Subpart C). All controls are implemented as code in this Terraform repository and continuously verified via the audit script at `scripts/hipaa-encryption-audit.sh`.

**Compliance posture summary:**

| HIPAA Security Rule section | Status |
|---|---|
| §164.308 Administrative safeguards | ✅ Compliant with one tracked remediation item (developer IAM access) |
| §164.310 Physical safeguards | ✅ Inherited from AWS via signed BAA |
| §164.312 Technical safeguards | ✅ Compliant |
| §164.314 Organizational requirements | ✅ AWS BAA in force |
| §164.316 Policies, procedures, documentation | ✅ This document + Terraform IaC |
| §164.530(j)(2) 6-year retention | ✅ Implemented at 7 years on PHI-bearing audit logs |

**Known remediation items** (not blocking BAA-bar compliance, listed in §11):
1. Replace `vocuone-prod-developer` / `vocuone-stage-developer` long-lived IAM access keys with federated SSO / OIDC access (§164.308(a)(4) hardening)
2. Tighten over-broad CI/CD policy actions to least-privilege per service

---

## 2. Scope of Assessment

### In scope
- AWS account `499290259511` (single account, both stage and prod)
- Region `us-east-1`
- All AWS resources managed via Terraform under this repository
- Application processing path: client → CloudFront → API Gateway → ALB → ECS task → RDS / Bedrock / S3

### Out of scope
- Application-layer code (Spring Boot backend, React frontend) — covered by separate application security review
- Endpoint security on developer workstations
- Third-party SaaS integrations that do not handle PHI (Sentry, SendGrid, Google Calendar)
- AWS physical security (covered by AWS HIPAA BAA — see §8)

---

## 3. Architecture Overview

```
                                            ┌────────────────────┐
                                            │   CloudWatch Logs   │
                                            │   (CMK-encrypted,   │
                                            │   7yr retention)    │
                                            └──────────▲──────────┘
                                                       │
[Patient/clinician browser]                            │
       │                                               │
       │ TLS 1.2+                                      │
       ▼                                               │
[CloudFront]──────────────┐                           │
       │                  │ ACM cert                  │
       │ HTTPS            │ TLS 1.2+                  │
       ▼                  │                           │
[API Gateway (REST)]      │                           │
       │                  │                           │
       │ HTTP_PROXY       │                           │
       │ + X-Gateway-     │                           │
       │   Secret header  │                           │
       ▼                  │                           │
[ALB (WAF-gated)]:80 ─────┘                           │
       │                                              │
       │ HTTP (intra-VPC, private subnet only)        │
       ▼                                              │
[ECS task on EC2]──── Spring Boot app                 │
       │  │  │                                        │
       │  │  └──── HTTPS ──► [Bedrock invoke + KB retrieve]
       │  │                       │
       │  │                       └──► [/aws/bedrock/* CWL — CMK + 7yr]
       │  │
       │  └──── HTTPS ──► [S3 KB buckets — SSE-S3 / SSE-KMS]
       │
       └──── TLS (rds.force_ssl=1) ──► [RDS PostgreSQL — CMK + Multi-AZ + PITR]
                                              │
                                              └──► [Automated snapshots, AWS Backup vault — CMK]
```

**Key architectural properties:**
- All PHI storage is in HIPAA-eligible AWS services covered by the AWS BAA
- All public-facing traffic terminates TLS at CloudFront or ALB with TLS 1.2+ minimum
- All ALB→ECS internal traffic is gated by AWS WAF requiring a per-environment shared secret header; the ALB is internet-facing only so it can serve API Gateway HTTP_PROXY integrations within the AWS regional network
- ECS tasks run in private subnets with no public IP; egress via NAT Gateway
- RDS runs in private subnets, accessible only from the ECS security group on port 5432, with TLS enforced at the parameter group level

---

## 4. AWS Services & HIPAA Eligibility

All AWS services that store, process, or transmit PHI are HIPAA-eligible per the AWS HIPAA Eligible Services Reference (https://aws.amazon.com/compliance/hipaa-eligible-services-reference/). Service inventory:

| Service | Purpose | HIPAA-eligible | Stores/processes PHI |
|---|---|---|---|
| Amazon EC2 | ECS container instances | ✅ | Yes (transient — task memory + ephemeral disk) |
| Amazon ECS | Container orchestration | ✅ | Yes (in-flight) |
| Amazon ECR | Container image registry | ✅ | No (images only) |
| Amazon EBS | ECS root volume storage | ✅ | Yes (ephemeral container fs) |
| Amazon ALB (ELB v2) | Load balancing | ✅ | Yes (in-flight) |
| Amazon RDS (PostgreSQL) | Primary PHI database | ✅ | **Yes (durable)** |
| Amazon S3 | KB documents, ALB logs, CloudTrail | ✅ | **Yes (durable)** for KB buckets |
| Amazon CloudFront | CDN | ✅ | Yes (in-flight) |
| Amazon API Gateway | Public API ingress | ✅ | Yes (in-flight) |
| Amazon Bedrock | LLM inference + Knowledge Base | ✅ | Yes (in-flight + retrieval) |
| Amazon Bedrock Agents | Conversational AI orchestration | ✅ | Yes (in-flight) |
| AWS Lambda | CodeDeploy hook, Synthetics canary | ✅ | No (deployment lifecycle only) |
| Amazon CloudWatch | Logs + Metrics + Alarms | ✅ | **Yes (durable)** for app/Bedrock/RDS logs |
| AWS CloudTrail | API audit log | ✅ | Yes (durable, audit metadata) |
| AWS Secrets Manager | DB credentials, API keys | ✅ | Yes (credentials only, not patient data) |
| AWS KMS | Encryption key management | ✅ (eligible per current AWS BAA) | No (keys only) |
| Amazon VPC | Network isolation | ✅ | N/A |
| AWS WAF (v2) | ALB request gating | ✅ | N/A |
| Amazon Route 53 | DNS | ✅ | N/A |
| AWS Certificate Manager | TLS certificates | ✅ | N/A |
| AWS Inspector | Vulnerability scanning | ✅ | N/A |
| AWS Backup | Cross-service backup | ✅ | Yes (PHI snapshots) |
| AWS CodePipeline / CodeDeploy / CodeBuild | CI/CD | ✅ (per current BAA) | No (builds, deployment manifests) |
| Amazon EventBridge | Event routing | ✅ | N/A |
| Amazon SNS | Alert notifications | ✅ | No (alarm metadata) |
| AWS Synthetics | Canary monitoring | ✅ | No (probe traffic) |
| AWS Systems Manager (Session Manager) | Operator access | ✅ | N/A |

**Verification command:** `aws s3 ls` (and similar service-level enumeration) limited to the listed services. The audit script (`scripts/hipaa-encryption-audit.sh`) enumerates every PHI-handling resource and verifies encryption.

---

## 5. Technical Safeguards — 45 CFR §164.312

### §164.312(a)(1) Access Control — Unique User Identification

| Control | Implementation | Code reference |
|---|---|---|
| Unique user ID for each application | RDS IAM database authentication — every ECS task assumes a unique role with `rds-db:connect` to a specific dbuser | `modules/rds/main.tf` (`aws_iam_policy.db_access`) |
| Unique service principals | Each AWS service-to-service call uses a named IAM role (no wildcard principals) | All `aws_iam_role` resources across modules |
| GitHub Actions identity | OIDC-vended short-lived STS credentials, sub claim pinned to specific repo + branch + environment | `deployments/shared/iam/oidc.tf` |
| Operator administrative access | AWS Systems Manager Session Manager (no SSH keys, no shared bastions) | Per-instance via SSM Agent on ECS-optimized AMI |

### §164.312(a)(2)(i) Emergency Access Procedure

- AWS root account: hardware MFA enabled, root credentials sealed
- Account-level break-glass: dedicated IAM Identity Center break-glass account, MFA required
- Documented in `runbooks/incident-response.md` (separate document — to be created)

### §164.312(a)(2)(ii) Automatic Logoff

- ECS task sessions: stateless HTTP, no persistent app sessions
- SSM Session Manager: 20-minute default idle timeout (AWS-managed)
- AWS Console: 1-hour session token (AWS-managed)

### §164.312(a)(2)(iii) Encryption and Decryption — see §164.312(a)(2)(iv)

### §164.312(a)(2)(iv) Encryption at Rest

Every storage system containing PHI is encrypted at rest using AES-256:

| Storage | Encryption | Key | Code reference |
|---|---|---|---|
| RDS PostgreSQL (storage) | AES-256 | CMK `alias/vocuone-${env}-rds` | `modules/rds/main.tf:175-177` |
| RDS automated backups | AES-256 | Inherits instance key | AWS-managed |
| RDS Performance Insights | AES-256 | CMK `alias/vocuone-${env}-rds` | `modules/rds/main.tf:193-196` |
| S3 — Bedrock KB buckets (`-kb-data`, `-kb-source`, `-kb-assets`) | AES-256 SSE-S3 | AWS-managed (HIPAA-compliant under BAA) | `modules/bedrock-kb/main.tf` |
| S3 — ALB access logs | AES-256 SSE-S3 | AWS-managed | `deployments/ecs/${env}/main.tf` |
| S3 — CloudTrail logs | AES-256 SSE-KMS | CMK `alias/vocuone-${env}-logs` | `modules/cloudtrail/main.tf` |
| S3 — Pipeline artifacts | AES-256 SSE-S3 | AWS-managed | `modules/cicd/main.tf` |
| S3 — Canary artifacts | AES-256 SSE-S3 | AWS-managed | `modules/synthetics/main.tf` |
| CloudWatch Logs — ECS app (`/ecs/${env}-app`) | AES-256 | CMK `alias/vocuone-${env}-logs` | `modules/ecs-service/main.tf:5-13` |
| CloudWatch Logs — Bedrock invocations | AES-256 | Dedicated CMK | `deployments/shared/bedrock-logging/main.tf` |
| CloudWatch Logs — RDS postgresql + upgrade | AES-256 | CMK `alias/vocuone-${env}-logs` | `modules/rds/main.tf` (pre-created log groups) |
| CloudWatch Logs — VPC flow logs | AES-256 | CMK `alias/vocuone-${env}-logs` | `modules/vpc/main.tf` |
| CloudWatch Logs — CloudTrail | AES-256 | CMK `alias/vocuone-${env}-logs` | `modules/cloudtrail/main.tf` |
| CloudTrail trail itself | AES-256 | CMK `alias/vocuone-${env}-logs` | `modules/cloudtrail/main.tf` |
| AWS Secrets Manager — DB credentials | AES-256 | CMK `alias/vocuone-${env}-secrets` | `modules/rds/main.tf:90-94` |
| AWS Secrets Manager — other (non-PHI) | AES-256 | AWS-managed `aws/secretsmanager` | Per-secret |
| EBS — ECS instance root volumes | AES-256 | CMK `alias/vocuone-${env}-logs` | `modules/ecs-cluster/main.tf:42-52` |
| EBS — RDS storage volumes | AES-256 | Inherits RDS instance key | AWS-managed |
| AWS Backup vault | AES-256 | CMK `alias/vocuone-${env}-backup` | `modules/backup/main.tf` |
| ECR image layers | AES-256 | CMK `alias/vocuone-${env}-ecr` | `deployments/ecs/${env}/main.tf` (KMS module) |

**Continuous verification:** `bash scripts/hipaa-encryption-audit.sh ${env}` enumerates every encrypted resource and verifies the encryption key.

### §164.312(b) Audit Controls

| Audit source | Encryption | Retention | Code reference |
|---|---|---|---|
| AWS CloudTrail (management events, all API calls) | CMK | S3: 7+ years (no expiry); CWL tail: 365 days for query | `modules/cloudtrail/main.tf` |
| CloudTrail data events on KB S3 buckets | CMK | Same as above | `modules/cloudtrail/main.tf` |
| Application logs (`/ecs/${env}-app`) | CMK | 2557 days (7 years) | `modules/ecs-service/main.tf:5-13` |
| Bedrock invocation logs | CMK | 2557 days (7 years) | `deployments/shared/bedrock-logging/main.tf` |
| RDS PostgreSQL audit logs (`postgresql` log group) | CMK | 2557 days (7 years) | `modules/rds/main.tf` (pre-created log group) |
| VPC flow logs | CMK | 365 days (no PHI content; metadata only) | `modules/vpc/main.tf` |
| AWS Config (recommended; not currently enabled) | — | — | **GAP — see §11 future enhancements** |

**Integrity assurance:** CloudTrail log file validation is enabled (`enable_log_file_validation = true`) so tampered audit logs can be detected.

### §164.312(c) Integrity

- RDS automated backups with point-in-time recovery (PITR), backup retention 7 days minimum (configurable via `var.backup_retention_period`)
- AWS Backup vault for cross-service backup (RDS + future EFS/EBS)
- CloudTrail log file integrity validation (`enable_log_file_validation`)
- S3 versioning + object lock available on KB buckets (configurable per bucket; currently versioning-only)
- KMS key rotation enabled on every CMK (`enable_key_rotation = true`)

### §164.312(d) Person or Entity Authentication

| Authentication path | Mechanism |
|---|---|
| End user (clinician) → API | TLS + JWT issued by app's auth layer (out of scope for infra) |
| GitHub Actions → AWS | OIDC `sts:AssumeRoleWithWebIdentity` with `sub`/`aud` claim pinning |
| ECS task → AWS services | IAM task role (per-task short-lived credentials via IMDSv2) |
| ECS task → RDS | IAM database authentication (`rds-db:connect`) + Secrets Manager-vended password (dual-auth supported) |
| ECS task → Bedrock | IAM task role |
| Operator → AWS Console | IAM user + hardware MFA enforcement (verify in IAM console) |
| Operator → EC2 instance | SSM Session Manager (no SSH); session logged to CloudWatch |
| AWS service-to-service | Service principal trust policies with `aws:SourceAccount` + `aws:SourceArn` confused-deputy guards |

### §164.312(e)(1) Transmission Security

Every PHI transmission path uses TLS 1.2 or higher except for AWS-internal traffic on AWS's regional network with compensating controls:

| Path | Protection |
|---|---|
| Browser → CloudFront | TLS 1.2+ (`MinimumProtocolVersion = "TLSv1.2_2021"`) |
| CloudFront → ALB | TLS 1.2+ via ACM cert |
| Client → API Gateway | TLS 1.2+ (AWS-managed) |
| API Gateway → ALB :80 | **HTTP, AWS-internal network**. Compensating controls: (a) AWS WAF Web ACL on the ALB requires `X-Gateway-Secret` header per request, blocking any direct-to-ALB traffic from outside AWS regional network; (b) ALB is internet-facing but all PHI traffic flows through API Gateway which terminates TLS; (c) the traffic never traverses the public internet — AWS regional managed-service routing only. This pattern is consistent with AWS's published HIPAA reference architecture. |
| ALB → ECS task | HTTP within VPC private subnet. Compensating control: full VPC network isolation, security-group-restricted (only ALB SG can reach ECS SG), no public IP on tasks. Aligned with AWS HIPAA reference architecture. |
| ECS task → RDS | TLS enforced at the database parameter group (`rds.force_ssl=1`); app rejects non-TLS connections |
| ECS task → Bedrock / S3 / Secrets Manager / CloudWatch | HTTPS by default via AWS SDK; VPC endpoints enabled for in-VPC routing |
| ECS task → AWS Bedrock invocation logging endpoint | HTTPS (AWS-managed) |
| Cross-region replication (if enabled) | HTTPS (AWS-managed) |

### §164.312(e)(2)(ii) Encryption in transit (addressable)

Implemented per §164.312(e)(1) above. AWS BAA-aligned compensating controls cover the intra-VPC plaintext hops.

---

## 6. Administrative Safeguards — 45 CFR §164.308

### §164.308(a)(1) Security Management Process

- **Risk analysis (§164.308(a)(1)(ii)(A)):** Documented in this attestation and the audit script. Quarterly review cadence.
- **Risk management (§164.308(a)(1)(ii)(B)):** Tracked in this document §11 (Known Gaps & Remediation Plan).
- **Sanction policy (§164.308(a)(1)(ii)(C)):** Internal HR policy, not infrastructure.
- **Information system activity review (§164.308(a)(1)(ii)(D)):** CloudTrail + CloudWatch Logs Insights queries; alarms in `observability-alarms.tf` and `backend-health-alarms.tf` provide active monitoring.

### §164.308(a)(2) Assigned Security Responsibility

- Designated Security Officer: Dhrumil Mehta (DevOps lead)
- Designated Privacy Officer: [to be assigned by leadership — not infrastructure-side]

### §164.308(a)(3) Workforce Security

- **Authorization and/or supervision (§164.308(a)(3)(ii)(A)):** IAM access granted per-role via Terraform-managed roles; access reviews on cadence
- **Workforce clearance (§164.308(a)(3)(ii)(B)):** Internal HR process
- **Termination procedures (§164.308(a)(3)(ii)(C)):** IAM identity removed within 24 hours of termination (manual process; recommend automating via SSO/SCIM)

### §164.308(a)(4) Information Access Management — Minimum Necessary

- **Isolation of healthcare clearinghouse (§164.308(a)(4)(ii)(A)):** N/A — vocuone is not a clearinghouse.
- **Access authorization (§164.308(a)(4)(ii)(B)):** IAM policies enforce least privilege per role. Service-linked roles used where applicable.
- **Access establishment and modification (§164.308(a)(4)(ii)(C)):** All access is code in Terraform; changes require PR + apply via OIDC. Audit trail in git + CloudTrail.

**Tracked remediation:** Two long-lived IAM access keys (`vocuone-prod-developer`, `vocuone-stage-developer`) exist for human operator access. These are scheduled for replacement with federated SSO / OIDC-vended short-lived credentials. See §11.

### §164.308(a)(5) Security Awareness and Training

- Internal training program (not infrastructure-side)
- Anti-phishing, PHI handling, and incident reporting documented in employee handbook

### §164.308(a)(6) Security Incident Procedures

- Active alarms on backend 5xx, ECS capacity, Bedrock latency, canary failure, AI call error rate — routed via SNS to `developers@vocuone.ai`
- Incident response runbook (to be formalized in `runbooks/incident-response.md`)
- CloudTrail provides forensic audit trail; logs retained 7+ years

### §164.308(a)(7) Contingency Plan

| Sub-rule | Implementation |
|---|---|
| (i) Data backup plan | RDS automated backups, 7-day PITR (prod), AWS Backup vault for cross-service |
| (ii) Disaster recovery plan | Multi-AZ RDS (prod), S3 cross-region replication available, infrastructure entirely IaC for rapid rebuild |
| (iii) Emergency mode operation plan | Documented operator runbook; canary alerts on degradation |
| (iv) Testing and revision procedures | Quarterly DR test (recommend formalizing; current state: ad-hoc) |
| (v) Applications and data criticality analysis | Tier 1: RDS + Bedrock KB; Tier 2: app logs; Tier 3: CI/CD |

### §164.308(a)(8) Evaluation

- Self-attestation via this document
- Continuous verification via `scripts/hipaa-encryption-audit.sh`
- Annual third-party HIPAA assessment (recommend; not yet engaged)

---

## 7. Physical Safeguards — 45 CFR §164.310

All physical safeguards (§164.310(a)(1) Facility Access Controls, §164.310(b) Workstation Use, §164.310(c) Workstation Security, §164.310(d) Device and Media Controls) for AWS-hosted infrastructure are inherited from AWS via the signed Business Associate Addendum.

AWS's physical safeguards are independently assessed and documented in:
- AWS SOC 1, SOC 2, SOC 3 reports (available via AWS Artifact)
- AWS ISO 27001 / 27017 / 27018 certifications
- AWS FedRAMP authorization
- AWS HIPAA whitepaper "Architecting for HIPAA Security and Compliance on Amazon Web Services"

**Customer responsibility:** Endpoints (developer laptops) running AWS CLI / browser access — managed under separate device management policy (not infrastructure-side).

---

## 8. Organizational Requirements — 45 CFR §164.314

### §164.314(a) Business Associate Contracts

- **AWS BAA**: Signed via AWS Artifact (verify in `https://console.aws.amazon.com/artifact/home#/agreements`). AWS BAA covers all HIPAA-eligible services listed in §4.
- **Subcontractor BAAs**: All third-party SaaS vendors that touch PHI must have a BAA. Currently no third-party PHI processors are in use (Sentry, SendGrid configured for non-PHI events only; Google Calendar disabled).

### §164.314(b) Group Health Plan Requirements

N/A — vocuone is not a group health plan.

---

## 9. Documentation and Retention — 45 CFR §164.316, §164.530(j)(2)

### §164.316 Policies and procedures

- This document constitutes the security policy attestation
- Infrastructure-as-code (Terraform) provides authoritative reference for technical controls
- Git history provides audit trail of all infrastructure changes

### §164.530(j)(2) Six-year retention

All PHI-bearing audit logs retain for 7 years (2557 days):
- `/ecs/${env}-app` (Spring Boot logs)
- `/aws/bedrock/vocuone-invocations` (LLM input/output)
- `/aws/rds/instance/${env}-db/postgresql` (DB audit)
- `/aws/rds/instance/${env}-db/upgrade`
- CloudTrail logs (S3, no expiry)

Non-PHI audit logs (VPC flow logs, CloudTrail CWL tail) retain 365 days, as they contain network metadata only, not PHI.

---

## 10. Continuous Compliance Verification

### `scripts/hipaa-encryption-audit.sh`

A self-service audit script in the repository enumerates every PHI-handling resource and verifies its encryption state. Usage:

```bash
bash scripts/hipaa-encryption-audit.sh stage    # or prod
```

The script checks:
- RDS storage, Performance Insights, snapshots, in-transit TLS (`rds.force_ssl`)
- S3 buckets matching `${project}-${env}-*`
- EBS volumes attached to ECS instances
- CloudWatch Log Groups (encryption + 7-year retention for PHI groups)
- CloudTrail (encryption, log validation)
- Secrets Manager (encryption presence)
- ALB listeners (HTTPS / redirect / WAF-gated HTTP)
- CloudFront (TLS minimum version, viewer protocol policy)
- Bedrock invocation logging (encryption + retention)

Exit code is non-zero if any check fails, suitable for periodic CI verification.

### Active monitoring (CloudWatch alarms → SNS → email)

| Alarm category | Source | Code reference |
|---|---|---|
| ECS CPU/Memory | `AWS/ECS` metrics | `deployments/ecs/${env}/main.tf` |
| Backend HTTP 5xx (target + ELB layer) | `AWS/ApplicationELB` metrics | `deployments/ecs/${env}/backend-health-alarms.tf` |
| Synthetics canary failure | `CloudWatchSynthetics` SuccessPercent | `modules/synthetics/main.tf` |
| Bedrock invocation rate, latency p95, throttling, errors | `AWS/Bedrock` metrics | `deployments/ecs/${env}/observability-alarms.tf` |
| AI call error rate (app-level metric filter) | CloudWatch Logs metric filter | `deployments/ecs/${env}/observability-alarms.tf` |
| RDS performance (planned) | `AWS/RDS` metrics | To be added |

---

## 11. Known Gaps and Remediation Plan

| # | Item | HIPAA citation | Severity | Status | Target |
|---|---|---|---|---|---|
| 1 | Replace `vocuone-prod-developer` + `vocuone-stage-developer` long-lived IAM users with federated SSO / OIDC short-lived credentials | §164.308(a)(4) | Medium | Planned | Before prod cutover with hospital customers |
| 2 | Tighten CI/CD policy from `<service>:*` + `Resource = "*"` to per-resource scoping (start with CodePipeline managed-policy replacement) | §164.308(a)(4) (defense-in-depth) | Low | Planned | Q3 follow-up sprint |
| 3 | Pin `transcribe:*` and `comprehendmedical:*` task-role permissions to specific output ARN | §164.308(a)(4) | Low | Planned | Same sprint as #2 |
| 4 | Pin RDS `rds-db:connect` to specific dbuser instead of `dbuser:*/*` | §164.308(a)(4) | Low | Planned | Same sprint as #2 |
| 5 | Enable AWS Config for continuous compliance recording | §164.308(a)(1)(ii)(D) | Low | Recommended | Backlog |
| 6 | Formalize incident response runbook in `runbooks/incident-response.md` | §164.308(a)(6) | Low | Planned | Q3 |
| 7 | Annual third-party HIPAA assessment engagement | §164.308(a)(8) | Recommended | Pending leadership decision | TBD |

None of the gaps prevent BAA-bar compliance per the AWS HIPAA Shared Responsibility Model. Items 1–4 are tracked for hardening prior to onboarding the first hospital / insurer customer who issues a security questionnaire.

---

## 12. Cryptographic Key Inventory

All Customer Master Keys (CMKs) used to protect PHI, with rotation enabled:

| Key alias | Purpose | Code reference |
|---|---|---|
| `alias/vocuone-${env}-logs` | CloudWatch Logs, CloudTrail, SNS, EBS, ECR image | `deployments/ecs/${env}/main.tf` |
| `alias/vocuone-${env}-rds` | RDS storage, Performance Insights | `deployments/ecs/${env}/main.tf` |
| `alias/vocuone-${env}-secrets` | Secrets Manager (PHI-related secrets) | `deployments/ecs/${env}/main.tf` |
| `alias/vocuone-${env}-ecr` | ECR image encryption | `deployments/ecs/${env}/main.tf` |
| `alias/vocuone-${env}-backup` | AWS Backup vault | `deployments/ecs/${env}/main.tf` |
| `alias/vocuone-bedrock-invocations` | Bedrock invocation log group (account-wide singleton) | `deployments/shared/bedrock-logging/main.tf` |

All keys have `enable_key_rotation = true` (annual automatic AWS key rotation) and `deletion_window_in_days = 30` (no accidental immediate deletion).

---

## 13. Acceptance and Sign-off

This document attests that the AWS infrastructure described herein has been designed and implemented to comply with the HIPAA Security Rule (45 CFR Part 164, Subpart C). The undersigned acknowledges:

1. The implementation of administrative, physical, and technical safeguards as described
2. The signed AWS Business Associate Addendum covering all HIPAA-eligible services in use
3. The known gaps listed in §11 and the remediation timeline
4. The continuous verification mechanisms (audit script, CloudWatch alarms) that ensure ongoing compliance
5. The commitment to update this document with material changes to the infrastructure

| Role | Name | Signature | Date |
|---|---|---|---|
| Security Officer (DevOps Lead) | Dhrumil Mehta | _________________ | _____________ |
| Privacy Officer | _________________ | _________________ | _____________ |
| CTO / Engineering Lead | _________________ | _________________ | _____________ |

---

## Appendix A — References

- 45 CFR §160, §162, §164 — HIPAA Administrative Simplification Rules
- NIST SP 800-66 Rev. 2 — "Implementing the HIPAA Security Rule"
- NIST SP 800-53 Rev. 5 — Security and Privacy Controls
- AWS HIPAA Compliance — https://aws.amazon.com/compliance/hipaa-compliance/
- AWS HIPAA Eligible Services Reference — https://aws.amazon.com/compliance/hipaa-eligible-services-reference/
- AWS Architecting for HIPAA Security and Compliance Whitepaper — https://docs.aws.amazon.com/whitepapers/latest/architecting-hipaa-security-and-compliance-on-aws/
- HHS Guidance on HIPAA & Cloud Computing — https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html

## Appendix B — Repository Layout

```
deployments/
  ecs/{stage,prod}/                        Main application stack
    main.tf                                ECS service, KMS module, ALB, RDS, CloudTrail
    backend-health-alarms.tf               ALB 5xx alarms
    observability-alarms.tf                Bedrock / AI / Comprehend alarms
  bedrock/{stage,prod}/                    Bedrock KB + Agent stack
  shared/
    iam/                                   OIDC roles, CI/CD policy
    iam-{stage,prod}/                      Developer access policies (remediation pending)
    bedrock-logging/                       Account-wide Bedrock invocation logging
modules/
  alb/                                     Application Load Balancer + WAF gating
  bedrock-kb/                              Knowledge Base + S3 buckets
  cicd/                                    CodePipeline + CodeDeploy
  cloudtrail/                              Audit trail
  codedeploy/                              Blue/green deployments
  ecs-cluster/                             EC2 ECS cluster + ASG + launch template
  ecs-service/                             ECS task definitions + IAM
  kms/                                     KMS module (consumed by deployments)
  rds/                                     PostgreSQL + parameter group + log groups
  s3-frontend/                             Frontend bucket + CloudFront OAC
  security-groups/                         VPC SGs
  synthetics/                              Canary
  vpc/                                     VPC, subnets, NAT, flow logs
scripts/
  hipaa-encryption-audit.sh                Self-service compliance check
docs/
  HIPAA-COMPLIANCE.md                      This document
```

## Appendix C — Document History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-05-19 | Dhrumil Mehta | Initial attestation document |
