# Architecture Diagram Brief — vocuone HIPAA Infrastructure

Purpose: enough detail to reproduce the production architecture diagram in any drawing tool (draw.io, Lucidchart, Excalidraw, Visio, Figma). Used in the HIPAA compliance attestation as the canonical reference.

---

## Layout — three vertical lanes

```
┌─────────────────────┬──────────────────────────────┬──────────────────────────┐
│  EXTERNAL (public)  │      AWS REGIONAL (us-east-1) — VPC               │ AUDIT │
│                     │                                                    │       │
│                     │  ┌─────────── VPC vocuone-${env} ───────────────┐ │       │
│                     │  │  PUBLIC subnets        PRIVATE subnets        │ │       │
│                     │  └────────────────────────────────────────────────┘ │       │
└─────────────────────┴──────────────────────────────┴──────────────────────────┘
```

Use **three columns**:
1. **External** — anything outside AWS (browsers, end users)
2. **AWS Regional** — the bulk of the architecture, with a nested VPC box
3. **Audit / Observability** — CloudTrail, CloudWatch Logs, SNS, AWS Backup

---

## Nodes (boxes)

Group by column. Use **AWS official icons** if available (or shapes if not).

### External column (top to bottom)

| Node | Shape | Notes |
|---|---|---|
| Browser / Clinician | User icon | Endpoint terminating TLS |

### AWS Regional column — outside the VPC

| Node | Shape | Notes |
|---|---|---|
| CloudFront | AWS edge service icon | TLS 1.2+, ACM cert |
| API Gateway (REST) | AWS service icon | Public ingress, HTTP_PROXY to ALB |
| AWS WAF Web ACL | Shield/firewall icon | Attached to ALB; requires `X-Gateway-Secret` header |
| KMS keys (multiple) | Key icon | Show as a cluster: `${env}-logs`, `${env}-rds`, `${env}-secrets`, `${env}-ecr`, `${env}-backup`, `bedrock-invocations` |
| Secrets Manager | Lock icon | DB credentials |
| Bedrock (KB + Agent) | AI/ML icon | LLM inference + KB retrieval |
| S3 — KB buckets (3) | Bucket icon | `vocuone-${env}-kb-data`, `-source`, `-assets`; SSE-S3 |
| ECR | Container registry icon | Image layers CMK-encrypted |

### AWS Regional column — inside the VPC

**Public subnet (top of VPC box):**

| Node | Shape | Notes |
|---|---|---|
| ALB (Application Load Balancer) | ELB icon | Internet-facing; listeners :443 HTTPS, :80 HTTP (WAF-gated), :8443 HTTPS (test) |
| NAT Gateway | Gateway icon | Egress from private subnets |
| Internet Gateway | IGW icon | At VPC boundary |

**Private subnet (bottom of VPC box):**

| Node | Shape | Notes |
|---|---|---|
| ECS cluster (EC2 launch type) | Cluster icon | `vocuone-${env}-cluster`, ASG with encrypted EBS volumes |
| ECS task (Spring Boot app) | Container icon | Show 1–N replicas |
| RDS PostgreSQL (Multi-AZ in prod) | DB icon | CMK-encrypted, `force_ssl=1`, IAM auth |
| RDS subnet group | Outline | Spans 2 AZs |

### Audit / Observability column

| Node | Shape | Notes |
|---|---|---|
| CloudTrail | Log icon | Management + KB S3 data events; log file validation on |
| CloudTrail S3 bucket | Bucket icon | SSE-KMS, no expiry |
| CloudWatch Logs (groups) | Log icon | Cluster: `/ecs/${env}-app`, `/aws/bedrock/*`, `/aws/rds/instance/*`, `/aws/vpc/${env}-flow-logs`, `/cloudtrail/${env}` |
| AWS Backup vault | Vault icon | CMK; backs up RDS |
| SNS topic | Notification icon | `vocuone-${env}-alerts` |
| Email (developers@vocuone.ai) | Email icon | SNS subscription endpoint |
| CloudWatch Alarms | Alarm icon | Cluster: backend 5xx, ECS CPU/mem, Bedrock p95, canary, AI error rate |
| Synthetics canary | Probe icon | `vocuone-${env}-api-canary`, hourly |

---

## Arrows (connections) — labeled with protocol + auth

| From | To | Label | Style |
|---|---|---|---|
| Browser | CloudFront | `TLS 1.2+` | Solid green (PHI in transit) |
| Browser | API Gateway | `TLS 1.2+` | Solid green |
| CloudFront | ALB :443 | `HTTPS, ACM cert` | Solid green |
| API Gateway | ALB :80 | `HTTP, X-Gateway-Secret header (AWS regional net)` | **Dashed orange** (intra-AWS plaintext, compensating control) |
| WAF | ALB | `attached` | Dotted thin |
| ALB | ECS task | `HTTP intra-VPC private` | **Dashed orange** (VPC-isolated plaintext) |
| ECS task | RDS | `TLS 1.2+ (rds.force_ssl=1), IAM auth` | Solid green |
| ECS task | Bedrock | `HTTPS, IAM task role` | Solid green |
| ECS task | S3 KB buckets | `HTTPS, IAM task role` | Solid green |
| ECS task | Secrets Manager | `HTTPS, IAM task role` | Solid green |
| ECS task | CloudWatch Logs | `HTTPS via VPC endpoint` | Solid green |
| Bedrock | CloudWatch Logs (`/aws/bedrock/*`) | `Logs publish` | Thin grey |
| RDS | CloudWatch Logs (`postgresql`) | `Logs publish` | Thin grey |
| RDS | AWS Backup vault | `automated backups` | Thin grey |
| All AWS calls | CloudTrail | `audit events` | Thin grey, dashed |
| CloudWatch Alarms | SNS topic | `alarm action` | Thin blue |
| SNS topic | Email | `notification` | Thin blue |
| Synthetics canary | ALB :443 (probe) | `hourly health check, HTTPS` | Thin purple |
| NAT Gateway | Internet Gateway | egress | Thin grey |
| Private subnet egress | NAT Gateway | AWS API egress | Thin grey |

---

## Color coding

| Color | Meaning |
|---|---|
| **Solid green** | PHI in transit over TLS — auditor focus |
| **Dashed orange** | Plaintext within AWS internal network (compensating control applies) |
| Thin blue | Alarm / notification fan-out |
| Thin purple | Synthetic probe traffic |
| Thin grey | Audit / log / backup data flows |
| Thin grey dashed | Service-to-service audit events |

Boxes:
- **Pale red fill**: anything storing PHI durably (RDS, S3 KB, CloudWatch Logs, AWS Backup, CloudTrail S3)
- **Pale blue fill**: AWS service principal endpoints
- **White fill**: ephemeral compute (ALB, ECS task)
- **Pale yellow fill**: external clients

---

## Annotations on the diagram

Add small text labels near these elements:

| Element | Annotation |
|---|---|
| Every PHI store | `AES-256, KMS CMK rotation enabled` |
| ALB :80 listener | `HTTP — only reachable via API Gateway carrying X-Gateway-Secret; WAF blocks all other ingress` |
| ECS instance volumes | `CMK-encrypted root EBS` |
| RDS | `Multi-AZ, encrypted, force_ssl=1, IAM auth, PITR 7d` |
| CloudWatch Logs cluster | `CMK + 7yr retention (PHI groups), 1yr (non-PHI)` |
| CloudTrail S3 | `SSE-KMS + log file validation + no expiry` |
| VPC | `Custom VPC, no public IPs on tasks, NAT egress only` |

---

## Mermaid version (paste into any Mermaid-compatible tool)

If you want a quick render without a designer, paste this into https://mermaid.live or any markdown viewer that supports Mermaid:

```mermaid
flowchart LR
    subgraph External["External"]
        Browser([Browser / Clinician])
    end

    subgraph AWS["AWS us-east-1 — Account 499290259511"]
        CF[CloudFront]
        AGW[API Gateway]
        WAF{WAF Web ACL<br/>X-Gateway-Secret}

        subgraph VPC["VPC vocuone-prod"]
            subgraph Pub["Public subnets"]
                ALB[ALB<br/>:443 / :80 / :8443]
                NAT[NAT Gateway]
            end
            subgraph Priv["Private subnets"]
                ECS[ECS task<br/>Spring Boot app]
                RDS[(RDS PostgreSQL<br/>Multi-AZ, CMK, force_ssl)]
            end
        end

        Bedrock[Bedrock<br/>KB + Agent]
        S3[(S3 KB buckets<br/>SSE-S3)]
        Sec[Secrets Manager<br/>CMK]
        ECR[(ECR<br/>CMK)]
        KMS{{KMS CMKs<br/>logs / rds / secrets<br/>ecr / backup / bedrock}}
    end

    subgraph Audit["Audit & Observability"]
        CT[CloudTrail<br/>+ S3 + CWL]
        CWL[CloudWatch Logs<br/>CMK + 7yr]
        Backup[AWS Backup vault<br/>CMK]
        Alarms[CloudWatch Alarms]
        SNS[SNS alerts]
        Email[developers@vocuone.ai]
        Canary[Synthetics canary]
    end

    Browser ==TLS 1.2+==> CF
    Browser ==TLS 1.2+==> AGW
    CF ==HTTPS==> ALB
    AGW -.HTTP + secret hdr.-> ALB
    WAF -.attached.-> ALB
    ALB -.HTTP intra-VPC.-> ECS
    ECS ==TLS, IAM auth==> RDS
    ECS ==HTTPS==> Bedrock
    ECS ==HTTPS==> S3
    ECS ==HTTPS==> Sec
    ECS ==HTTPS==> CWL
    Bedrock --> CWL
    RDS --> CWL
    RDS --> Backup
    Canary --HTTPS probe--> ALB
    Alarms --> SNS --> Email
    CT -.audit.- AWS

    classDef phi fill:#fdd,stroke:#c33
    classDef aws fill:#dde,stroke:#557
    classDef ext fill:#ffd,stroke:#aa3
    class RDS,S3,CWL,Backup,CT phi
    class CF,AGW,ALB,ECS,Bedrock,Sec,ECR,KMS,Alarms,SNS,Canary,NAT,WAF aws
    class Browser,Email ext
```

---

## Recommendation

For the HIPAA submission, **export at 1920×1080 PNG** (or SVG for sharper render) and embed on a single landscape page of the .docx (or attach separately). Auditors prefer:

- One canonical diagram per submission (not multiple)
- All PHI flows clearly labeled with protocol + auth mechanism
- The compensating controls (WAF, VPC isolation) explicitly annotated
- KMS keys shown so reviewers can trace which key protects which store

**Easiest path:** paste the Mermaid block into https://mermaid.live, tweak labels, click Export → PNG (transparent), drop into the Word doc above the §3 architecture section.
