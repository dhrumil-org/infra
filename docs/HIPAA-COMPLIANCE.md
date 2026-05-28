# HIPAA Compliance Attestation — vocuone / vocanote-ai

| Property | Value |
|---|---|
| Version | 1.0 |
| Last updated | 2026-05-19 |
| Owner | Dhrumil Mehta (DevOps Lead) |
| Status | Draft for review |
| Scope | AWS account `499290259511`, region `us-east-1`, envs `stage` + `prod` |
| Standards | HIPAA Security Rule (45 CFR §164.302–.318), §164.530(j)(2), AWS HIPAA Shared Responsibility Model, NIST SP 800-66 |

---

## 1. Executive Summary

vocuone runs a clinical case-companion app processing PHI exclusively on HIPAA-eligible AWS services under a signed BAA. All technical safeguards are implemented as code in this Terraform repository and continuously verified by `scripts/hipaa-encryption-audit.sh`.

| HIPAA Section | Status |
|---|---|
| §164.308 Administrative | Compliant, one tracked remediation item |
| §164.310 Physical | Inherited from AWS via BAA |
| §164.312 Technical | Compliant |
| §164.314 Organizational | AWS BAA in force |
| §164.316 / §164.530(j)(2) Docs + 7yr retention | Compliant |

**One open item before customer onboarding:** Replace two long-lived developer IAM access keys with federated SSO / OIDC (§11).

---

## 2. Scope

**In scope:** AWS account `499290259511`, us-east-1, stage + prod environments. Traffic path: client → CloudFront → API Gateway → ALB → ECS task → RDS / Bedrock / S3.

**Out of scope:** Application code (separate review), endpoint security, AWS physical security (BAA-inherited).

---

## 3. Architecture

```
[Browser] —TLS1.2+→ [CloudFront] —TLS→ [ALB :443]
[Browser] —TLS1.2+→ [API Gateway] —HTTP*→ [ALB :80] —HTTP→ [ECS task]
                                                              │
       ┌──────────────────────────────────────────────────────┤
       ▼                ▼                ▼                    ▼
  [RDS Postgres]   [Bedrock KB]    [Secrets Mgr]      [CloudWatch Logs]
   (CMK, TLS)      (SSE-S3)         (CMK)             (CMK, 7yr ret.)
       │                                                      ▲
       └──► Automated backups + AWS Backup vault (CMK)         │
                                                              │
[All API calls] ────────────────────► [CloudTrail S3 (CMK) + CWL tail]

* API Gateway → ALB :80 hop is plaintext on AWS-internal network only;
  gated by WAF requiring X-Gateway-Secret header. Direct-to-ALB blocked.
```

**Key properties:** every PHI store uses AES-256 (CMK where customer-managed); all public-facing TLS 1.2+; ECS tasks in private subnets with no public IP; RDS reachable only from ECS security group with `rds.force_ssl=1`; WAF gates the ALB; CloudTrail log file validation on.

---

## 4. AWS Services & HIPAA Eligibility

Every service handling PHI is on the current AWS HIPAA Eligible Services Reference list.

| Service | Purpose | PHI? |
|---|---|---|
| EC2 + ECS + EBS | App compute | Transient |
| RDS PostgreSQL | Primary patient DB | Durable |
| S3 (KB buckets) | KB documents | Durable |
| Bedrock + Bedrock Agents | LLM inference, KB retrieval | In-flight + retrieval |
| CloudFront + API Gateway + ALB + WAF | Public ingress | In-flight |
| Lambda | CodeDeploy hook, Synthetics canary | No |
| CloudWatch + CloudTrail | Audit + logs | Durable (audit) |
| Secrets Manager | DB creds | Creds only |
| KMS | Encryption keys | No (keys) |
| AWS Backup | Cross-service backup | Durable (snapshots) |
| VPC, Route 53, ACM, Inspector, SSM, EventBridge, SNS, Synthetics, CodePipeline/Deploy/Build | Supporting | No (or N/A) |

Audit script confirms only HIPAA-eligible services are touched.

---

## 5. Technical Safeguards (§164.312)

### Encryption at rest (§164.312(a)(2)(iv))

Every PHI store is AES-256 encrypted:

| Store | Key |
|---|---|
| RDS storage + Perf Insights + automated snapshots | CMK `alias/vocuone-${env}-rds` |
| EBS — ECS root volumes | CMK `alias/vocuone-${env}-logs` |
| S3 — Bedrock KB / ALB logs / pipeline / canary | AES-256 SSE-S3 (BAA-acceptable) |
| S3 — CloudTrail | SSE-KMS, CMK `alias/vocuone-${env}-logs` |
| CWL — app, Bedrock, RDS postgresql, VPC flow, CloudTrail | CMK `alias/vocuone-${env}-logs` (or dedicated Bedrock CMK) |
| Secrets Manager (PHI-bearing) | CMK `alias/vocuone-${env}-secrets` |
| AWS Backup vault | CMK `alias/vocuone-${env}-backup` |
| ECR images | CMK `alias/vocuone-${env}-ecr` |

All CMKs have key rotation enabled and a 30-day deletion window. Continuous verification: `bash scripts/hipaa-encryption-audit.sh ${env}`.

### Encryption in transit (§164.312(e))

| Path | Protection |
|---|---|
| Browser → CloudFront → ALB | TLS 1.2+ (ACM certs, `ELBSecurityPolicy-TLS13-1-2-2021-06`) |
| Client → API Gateway | TLS 1.2+ (AWS-managed) |
| API Gateway → ALB :80 | HTTP on AWS regional network; WAF gate (X-Gateway-Secret); compensating control per AWS HIPAA reference architecture |
| ALB → ECS task | HTTP intra-VPC private subnet; SG-restricted; AWS-standard pattern |
| ECS → RDS | TLS enforced (`rds.force_ssl=1`) |
| ECS → AWS services (Bedrock, S3, Secrets Mgr, CloudWatch) | HTTPS by default (AWS SDK) |

### Access control (§164.312(a)(1))

- **Apps**: ECS task IAM roles with per-task credentials via IMDSv2; RDS IAM database auth + Secrets Manager-vended password (dual auth).
- **CI/CD**: GitHub Actions OIDC `sts:AssumeRoleWithWebIdentity`, `sub`/`aud` claims pinned to repo + branch + environment. No long-lived CI keys.
- **Operators**: SSM Session Manager (no SSH); MFA on console; CloudTrail logged.
- **Service-to-service**: trust policies with `aws:SourceAccount` + `aws:SourceArn` confused-deputy guards.

### Audit controls + integrity (§164.312(b), (c))

- CloudTrail (all API events + KB S3 data events) → S3 (no expiry) + CWL tail (365d); log file validation on.
- App/Bedrock/RDS audit log groups: CMK + 2557d (7yr) retention per §164.530(j)(2).
- KMS key rotation, S3 versioning on KB buckets, RDS PITR.

### Authentication (§164.312(d))

JWT for end users; OIDC for CI; IAM roles for services; MFA + SSM for operators.

---

## 6. Administrative Safeguards (§164.308)

| Sub-section | Implementation |
|---|---|
| (a)(1) Security mgmt | Risk analysis = this doc + audit script; quarterly review |
| (a)(2) Security Officer | Dhrumil Mehta (DevOps) |
| (a)(3) Workforce security | IAM access via Terraform; termination removes IAM identity ≤24h |
| (a)(4) Min necessary | Per-role IAM policies; access changes via PR + OIDC apply; one open remediation (§11) |
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
- Non-PHI logs (VPC flow, CT tail): 365d
- Git history = full audit trail of infrastructure changes

---

## 10. Continuous Verification

**Audit script** (`scripts/hipaa-encryption-audit.sh`): enumerates every PHI-handling resource, verifies encryption + retention; non-zero exit on failure; CI-runnable.

**Active monitoring** (CloudWatch alarms → SNS → email):
- Backend HTTP 5xx (ALB target + ELB layer)
- ECS CPU / memory
- Bedrock latency p95, invocation throttling, errors
- Synthetics canary failures
- App-level AI call error rate (metric filter on `/ecs/${env}-app`)

---

## 11. Known Gaps & Remediation

| # | Item | Citation | Severity | Target |
|---|---|---|---|---|
| 1 | Replace `vocuone-{prod,stage}-developer` long-lived IAM users with federated SSO / OIDC | §164.308(a)(4) | Medium | Before first hospital customer |
| 2 | Tighten CI/CD policy from `<svc>:*` + `Resource = "*"` to per-resource scoping | §164.308(a)(4) | Low | Q3 |
| 3 | Pin `transcribe:*` / `comprehendmedical:*` task perms to specific output ARN | §164.308(a)(4) | Low | Q3 |
| 4 | Pin RDS `rds-db:connect` to specific dbuser | §164.308(a)(4) | Low | Q3 |
| 5 | Enable AWS Config for continuous compliance recording | §164.308(a)(1) | Low | Backlog |
| 6 | Formalize `runbooks/incident-response.md` | §164.308(a)(6) | Low | Q3 |
| 7 | Annual third-party HIPAA assessment | §164.308(a)(8) | Recommended | Leadership decision |

None block BAA compliance. Items 1–4 hardening is gated to first hospital/insurer customer onboarding.

---

## 12. KMS Key Inventory

| Alias | Purpose |
|---|---|
| `alias/vocuone-${env}-logs` | CloudWatch Logs, CloudTrail, SNS, EBS, ECR |
| `alias/vocuone-${env}-rds` | RDS storage + Perf Insights |
| `alias/vocuone-${env}-secrets` | Secrets Manager (PHI) |
| `alias/vocuone-${env}-ecr` | ECR image layers |
| `alias/vocuone-${env}-backup` | AWS Backup vault |
| `alias/vocuone-bedrock-invocations` | Bedrock invocation logs (account-wide singleton) |

All CMKs: rotation enabled, 30-day deletion window.

---

## 13. Sign-off

The undersigned acknowledges the safeguards described, the signed AWS BAA, the gap-remediation timeline, and the continuous-verification mechanism.

| Role | Name | Signature | Date |
|---|---|---|---|
| Security Officer (DevOps Lead) | Dhrumil Mehta | | |
| Privacy Officer | | | |
| CTO / Engineering Lead | | | |

---

## Appendix — References

- 45 CFR §160, §162, §164 — HIPAA Rules
- NIST SP 800-66 Rev. 2 — HIPAA implementation guide
- AWS HIPAA Compliance — https://aws.amazon.com/compliance/hipaa-compliance/
- AWS HIPAA Eligible Services Reference — https://aws.amazon.com/compliance/hipaa-eligible-services-reference/
- HHS Guidance on HIPAA & Cloud Computing — https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html
