// Builds D:/infra/docs/HIPAA-COMPLIANCE.docx from the markdown attestation.
// Run: node D:/infra/docs/build-docx.js
//
// Requires: npm install -g docx  (already installed)

const path = require('path');
const fs = require('fs');

// Use globally installed docx
const docxPath = path.join(process.env.APPDATA, 'npm', 'node_modules', 'docx');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat, ExternalHyperlink,
  TabStopType, TabStopPosition, HeadingLevel, BorderStyle, WidthType,
  ShadingType, PageNumber, PageBreak, TableOfContents, PageOrientation,
} = require(docxPath);

// --- styling constants --------------------------------------------------
const BODY_FONT = 'Calibri';
const MONO_FONT = 'Consolas';

const ACCENT = '2E75B6';      // dark blue
const HEADER_FILL = '2E75B6';  // table header background
const HEADER_TEXT = 'FFFFFF';  // table header text (white on blue)
const CODE_FILL = 'F2F2F2';   // code block background

const BORDER = { style: BorderStyle.SINGLE, size: 6, color: '8C8C8C' };
const CELL_BORDERS = { top: BORDER, bottom: BORDER, left: BORDER, right: BORDER };

const CONTENT_WIDTH = 9360;  // letter w/ 1-inch margins (12240 - 2*1440)

// --- helpers ------------------------------------------------------------
function clean(text) {
  if (text === null || text === undefined) return '';
  return String(text)
    .replace(/✅/g, 'Compliant')
    .replace(/⚠️/g, 'Caveat')
    .replace(/❌/g, 'Gap')
    .replace(/❓/g, 'Verify')
    .replace(/🟡/g, 'In progress')
    .replace(/🔴/g, 'Critical')
    .replace(/🟠/g, 'High')
    .replace(/🏆/g, 'Exceeds requirement');
}

function p(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 120, ...opts.spacing },
    alignment: opts.alignment || AlignmentType.LEFT,
    pageBreakBefore: opts.pageBreakBefore || false,
    children: [new TextRun({
      text: clean(text),
      font: BODY_FONT,
      size: opts.size || 22,    // 11pt
      bold: opts.bold || false,
      italics: opts.italics || false,
      color: opts.color || '000000',
    })],
  });
}

function h1(text, opts = {}) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    pageBreakBefore: opts.pageBreakBefore || false,
    spacing: { before: 360, after: 180 },
    children: [new TextRun({
      text: clean(text),
      font: BODY_FONT,
      size: 36,   // 18pt
      bold: true,
      color: ACCENT,
    })],
  });
}

function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 240, after: 120 },
    children: [new TextRun({
      text: clean(text),
      font: BODY_FONT,
      size: 28,   // 14pt
      bold: true,
      color: ACCENT,
    })],
  });
}

function h3(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_3,
    spacing: { before: 180, after: 100 },
    children: [new TextRun({
      text: clean(text),
      font: BODY_FONT,
      size: 24,   // 12pt
      bold: true,
      color: '404040',
    })],
  });
}

function mono(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 80 },
    shading: { type: ShadingType.CLEAR, fill: CODE_FILL },
    children: [new TextRun({
      text: text,
      font: MONO_FONT,
      size: opts.size || 16,   // 8pt for diagrams
    })],
  });
}

function codeBlock(lines, opts = {}) {
  return lines.map(line => mono(line, opts));
}

function bullet(text) {
  return new Paragraph({
    numbering: { reference: 'bullets', level: 0 },
    spacing: { after: 60 },
    children: [new TextRun({
      text: clean(text),
      font: BODY_FONT,
      size: 22,
    })],
  });
}

// Cell with default formatting. content can be a string or array of TextRun
function cell(content, opts = {}) {
  let children;
  if (typeof content === 'string') {
    children = [new Paragraph({
      spacing: { after: 0 },
      children: [new TextRun({
        text: clean(content),
        font: opts.mono ? MONO_FONT : BODY_FONT,
        size: opts.size || 20,   // 10pt
        bold: opts.bold || false,
        color: opts.color || '000000',
      })],
    })];
  } else {
    children = content;
  }
  return new TableCell({
    width: { size: opts.width || 0, type: WidthType.DXA },
    borders: CELL_BORDERS,
    margins: { top: 100, bottom: 100, left: 140, right: 140 },
    shading: opts.fill
      ? { type: ShadingType.CLEAR, fill: opts.fill }
      : undefined,
    children: children,
  });
}

function headerCell(text, width) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders: CELL_BORDERS,
    margins: { top: 100, bottom: 100, left: 140, right: 140 },
    shading: { type: ShadingType.CLEAR, fill: HEADER_FILL },
    children: [new Paragraph({
      spacing: { after: 0 },
      children: [new TextRun({
        text: clean(text),
        font: BODY_FONT,
        size: 20,
        bold: true,
        color: HEADER_TEXT,
      })],
    })],
  });
}

// Build a table. columnWidths must sum to <= CONTENT_WIDTH.
function buildTable(headers, rows, columnWidths) {
  return new Table({
    width: { size: columnWidths.reduce((a, b) => a + b, 0), type: WidthType.DXA },
    columnWidths: columnWidths,
    rows: [
      new TableRow({
        tableHeader: true,
        children: headers.map((h, i) => headerCell(h, columnWidths[i])),
      }),
      ...rows.map(row => new TableRow({
        children: row.map((c, i) =>
          typeof c === 'object' && c.text !== undefined
            ? cell(c.text, { ...c, width: columnWidths[i] })
            : cell(c, { width: columnWidths[i] })),
      })),
    ],
  });
}

function spacer() {
  return new Paragraph({
    spacing: { after: 80 },
    children: [new TextRun({ text: ' ', font: BODY_FONT, size: 22 })],
  });
}

// --- content sections ---------------------------------------------------

const titlePage = [
  new Paragraph({
    spacing: { before: 2400, after: 360 },
    alignment: AlignmentType.CENTER,
    children: [new TextRun({
      text: 'HIPAA Compliance Attestation',
      font: BODY_FONT, size: 56, bold: true, color: ACCENT,
    })],
  }),
  new Paragraph({
    spacing: { after: 600 },
    alignment: AlignmentType.CENTER,
    children: [new TextRun({
      text: 'vocuone / vocanote-ai Production Infrastructure',
      font: BODY_FONT, size: 36, color: '404040',
    })],
  }),

  // Document metadata table
  buildTable(
    ['Property', 'Value'],
    [
      ['Document version', '1.0'],
      ['Last updated', '2026-05-19'],
      ['Owner', 'Dhrumil Mehta (DevOps), vocuone / vocanote-ai engineering'],
      ['Status', 'Draft for review'],
      ['Scope', 'AWS account 499290259511, region us-east-1, environments stage and prod'],
      ['Standards referenced', 'HIPAA Security Rule (45 CFR §164.302–.318), HIPAA Privacy Rule §164.530(j)(2), AWS HIPAA Shared Responsibility Model, NIST SP 800-66, NIST SP 800-53'],
    ],
    [2640, 6720],
  ),

  new Paragraph({
    spacing: { before: 1200 },
    alignment: AlignmentType.CENTER,
    children: [new TextRun({
      text: 'Confidential — Internal compliance documentation',
      font: BODY_FONT, size: 20, italics: true, color: '808080',
    })],
  }),

  new Paragraph({ children: [new PageBreak()] }),
];

// --- TOC ----------------------------------------------------------------
const toc = [
  h1('Table of Contents'),
  new TableOfContents('Contents', {
    hyperlink: true,
    headingStyleRange: '1-2',
  }),
  new Paragraph({ children: [new PageBreak()] }),
];

// --- Section 1: Executive Summary ---------------------------------------
const section1 = [
  h1('1. Executive Summary', { pageBreakBefore: false }),
  p('vocuone operates a clinical case-companion application that processes Protected Health Information (PHI) — patient transcripts, case notes, clinical documents, and AI-generated clinical summaries — exclusively on AWS services covered by the AWS Business Associate Addendum (BAA).'),
  p('This document attests to the technical and administrative safeguards implemented in our AWS environment to comply with the HIPAA Security Rule (45 CFR Part 164, Subpart C). All controls are implemented as code in this Terraform repository and continuously verified via the audit script at scripts/hipaa-encryption-audit.sh.'),
  h3('Compliance posture summary'),
  buildTable(
    ['HIPAA Security Rule section', 'Status'],
    [
      ['§164.308 Administrative safeguards', 'Compliant with one tracked remediation item (developer IAM access)'],
      ['§164.310 Physical safeguards', 'Inherited from AWS via signed BAA'],
      ['§164.312 Technical safeguards', 'Compliant'],
      ['§164.314 Organizational requirements', 'AWS BAA in force'],
      ['§164.316 Policies, procedures, documentation', 'This document + Terraform IaC'],
      ['§164.530(j)(2) 6-year retention', 'Implemented at 7 years on PHI-bearing audit logs'],
    ],
    [5040, 4320],
  ),
  spacer(),
  h3('Known remediation items'),
  p('(Not blocking BAA-bar compliance, listed in §11):'),
  bullet('1. Replace vocuone-prod-developer / vocuone-stage-developer long-lived IAM access keys with federated SSO / OIDC access (§164.308(a)(4) hardening)'),
  bullet('2. Tighten over-broad CI/CD policy actions to least-privilege per service'),
];

// --- Section 2: Scope ---------------------------------------------------
const section2 = [
  h1('2. Scope of Assessment'),
  h3('In scope'),
  bullet('AWS account 499290259511 (single account, both stage and prod)'),
  bullet('Region us-east-1'),
  bullet('All AWS resources managed via Terraform under this repository'),
  bullet('Application processing path: client → CloudFront → API Gateway → ALB → ECS task → RDS / Bedrock / S3'),
  h3('Out of scope'),
  bullet('Application-layer code (Spring Boot backend, React frontend) — covered by separate application security review'),
  bullet('Endpoint security on developer workstations'),
  bullet('Third-party SaaS integrations that do not handle PHI (Sentry, SendGrid, Google Calendar)'),
  bullet('AWS physical security (covered by AWS HIPAA BAA — see §7)'),
];

// --- Section 3: Architecture --------------------------------------------
const archDiagram = [
  '                                            ┌────────────────────┐',
  '                                            │   CloudWatch Logs  │',
  '                                            │  (CMK-encrypted,   │',
  '                                            │   7yr retention)   │',
  '                                            └──────────▲─────────┘',
  '                                                       │',
  '[Patient/clinician browser]                            │',
  '       │                                               │',
  '       │ TLS 1.2+                                      │',
  '       ▼                                               │',
  '[CloudFront]──────────────┐                           │',
  '       │                  │ ACM cert                  │',
  '       │ HTTPS            │ TLS 1.2+                  │',
  '       ▼                  │                           │',
  '[API Gateway (REST)]      │                           │',
  '       │                  │                           │',
  '       │ HTTP_PROXY       │                           │',
  '       │ + X-Gateway-     │                           │',
  '       │   Secret header  │                           │',
  '       ▼                  │                           │',
  '[ALB (WAF-gated)]:80 ─────┘                           │',
  '       │                                              │',
  '       │ HTTP (intra-VPC, private subnet only)        │',
  '       ▼                                              │',
  '[ECS task on EC2] ─── Spring Boot app                 │',
  '       │  │  │                                        │',
  '       │  │  └─── HTTPS ──► [Bedrock invoke + KB retrieve]',
  '       │  │                       │',
  '       │  │                       └──► [/aws/bedrock/* CWL — CMK + 7yr]',
  '       │  │',
  '       │  └─── HTTPS ──► [S3 KB buckets — SSE-S3 / SSE-KMS]',
  '       │',
  '       └─── TLS (rds.force_ssl=1) ──► [RDS PostgreSQL — CMK + Multi-AZ + PITR]',
  '                                              │',
  '                                              └──► [Automated snapshots, AWS Backup vault — CMK]',
];

const section3 = [
  h1('3. Architecture Overview'),
  ...codeBlock(archDiagram, { size: 14 }),    // 7pt mono to fit width
  spacer(),
  h3('Key architectural properties'),
  bullet('All PHI storage is in HIPAA-eligible AWS services covered by the AWS BAA'),
  bullet('All public-facing traffic terminates TLS at CloudFront or ALB with TLS 1.2+ minimum'),
  bullet('All ALB→ECS internal traffic is gated by AWS WAF requiring a per-environment shared secret header; the ALB is internet-facing only to serve API Gateway HTTP_PROXY integrations within AWS regional network'),
  bullet('ECS tasks run in private subnets with no public IP; egress via NAT Gateway'),
  bullet('RDS runs in private subnets, accessible only from the ECS security group on port 5432, with TLS enforced at the parameter group level'),
];

// --- Section 4: Service inventory ---------------------------------------
const serviceRows = [
  ['Amazon EC2', 'ECS container instances', 'Yes', 'Yes (transient — task memory + ephemeral disk)'],
  ['Amazon ECS', 'Container orchestration', 'Yes', 'Yes (in-flight)'],
  ['Amazon ECR', 'Container image registry', 'Yes', 'No (images only)'],
  ['Amazon EBS', 'ECS root volume storage', 'Yes', 'Yes (ephemeral container fs)'],
  ['Amazon ALB (ELB v2)', 'Load balancing', 'Yes', 'Yes (in-flight)'],
  ['Amazon RDS (PostgreSQL)', 'Primary PHI database', 'Yes', 'Yes (durable)'],
  ['Amazon S3', 'KB documents, ALB logs, CloudTrail', 'Yes', 'Yes (durable) for KB buckets'],
  ['Amazon CloudFront', 'CDN', 'Yes', 'Yes (in-flight)'],
  ['Amazon API Gateway', 'Public API ingress', 'Yes', 'Yes (in-flight)'],
  ['Amazon Bedrock', 'LLM inference + Knowledge Base', 'Yes', 'Yes (in-flight + retrieval)'],
  ['Amazon Bedrock Agents', 'Conversational AI orchestration', 'Yes', 'Yes (in-flight)'],
  ['AWS Lambda', 'CodeDeploy hook, Synthetics canary', 'Yes', 'No (deployment lifecycle only)'],
  ['Amazon CloudWatch', 'Logs + Metrics + Alarms', 'Yes', 'Yes (durable) for app/Bedrock/RDS logs'],
  ['AWS CloudTrail', 'API audit log', 'Yes', 'Yes (durable, audit metadata)'],
  ['AWS Secrets Manager', 'DB credentials, API keys', 'Yes', 'Yes (credentials only, not patient data)'],
  ['AWS KMS', 'Encryption key management', 'Yes (eligible per current AWS BAA)', 'No (keys only)'],
  ['Amazon VPC', 'Network isolation', 'Yes', 'N/A'],
  ['AWS WAF (v2)', 'ALB request gating', 'Yes', 'N/A'],
  ['Amazon Route 53', 'DNS', 'Yes', 'N/A'],
  ['AWS Certificate Manager', 'TLS certificates', 'Yes', 'N/A'],
  ['AWS Inspector', 'Vulnerability scanning', 'Yes', 'N/A'],
  ['AWS Backup', 'Cross-service backup', 'Yes', 'Yes (PHI snapshots)'],
  ['CodePipeline / CodeDeploy / CodeBuild', 'CI/CD', 'Yes (per current BAA)', 'No (builds, deployment manifests)'],
  ['Amazon EventBridge', 'Event routing', 'Yes', 'N/A'],
  ['Amazon SNS', 'Alert notifications', 'Yes', 'No (alarm metadata)'],
  ['AWS Synthetics', 'Canary monitoring', 'Yes', 'No (probe traffic)'],
  ['AWS Systems Manager (Session Manager)', 'Operator access', 'Yes', 'N/A'],
];

const section4 = [
  h1('4. AWS Services & HIPAA Eligibility'),
  p('All AWS services that store, process, or transmit PHI are HIPAA-eligible per the AWS HIPAA Eligible Services Reference. Service inventory:'),
  buildTable(
    ['Service', 'Purpose', 'HIPAA-eligible', 'Stores/processes PHI'],
    serviceRows,
    [2400, 2800, 1880, 2280],
  ),
  spacer(),
  p('Verification command: `aws s3 ls` (and similar service-level enumeration) limited to the listed services. The audit script (scripts/hipaa-encryption-audit.sh) enumerates every PHI-handling resource and verifies encryption.'),
];

// --- Section 5: Technical Safeguards ------------------------------------
const section5 = [
  h1('5. Technical Safeguards — 45 CFR §164.312', { pageBreakBefore: true }),

  h2('§164.312(a)(1) Access Control — Unique User Identification'),
  buildTable(
    ['Control', 'Implementation', 'Code reference'],
    [
      ['Unique user ID for each application', 'RDS IAM database authentication — every ECS task assumes a unique role with rds-db:connect to a specific dbuser', 'modules/rds/main.tf (aws_iam_policy.db_access)'],
      ['Unique service principals', 'Each AWS service-to-service call uses a named IAM role (no wildcard principals)', 'All aws_iam_role resources across modules'],
      ['GitHub Actions identity', 'OIDC-vended short-lived STS credentials, sub claim pinned to specific repo + branch + environment', 'deployments/shared/iam/oidc.tf'],
      ['Operator administrative access', 'AWS Systems Manager Session Manager (no SSH keys, no shared bastions)', 'Per-instance via SSM Agent on ECS-optimized AMI'],
    ],
    [2400, 4480, 2480],
  ),

  h2('§164.312(a)(2)(i) Emergency Access Procedure'),
  bullet('AWS root account: hardware MFA enabled, root credentials sealed'),
  bullet('Account-level break-glass: dedicated IAM Identity Center break-glass account, MFA required'),
  bullet('Documented in runbooks/incident-response.md (separate document — to be created)'),

  h2('§164.312(a)(2)(ii) Automatic Logoff'),
  bullet('ECS task sessions: stateless HTTP, no persistent app sessions'),
  bullet('SSM Session Manager: 20-minute default idle timeout (AWS-managed)'),
  bullet('AWS Console: 1-hour session token (AWS-managed)'),

  h2('§164.312(a)(2)(iv) Encryption at Rest'),
  p('Every storage system containing PHI is encrypted at rest using AES-256:'),
  buildTable(
    ['Storage', 'Encryption', 'Key', 'Code reference'],
    [
      ['RDS PostgreSQL (storage)', 'AES-256', 'CMK alias/vocuone-${env}-rds', 'modules/rds/main.tf:175-177'],
      ['RDS automated backups', 'AES-256', 'Inherits instance key', 'AWS-managed'],
      ['RDS Performance Insights', 'AES-256', 'CMK alias/vocuone-${env}-rds', 'modules/rds/main.tf:193-196'],
      ['S3 — Bedrock KB buckets', 'AES-256 SSE-S3', 'AWS-managed (HIPAA-compliant under BAA)', 'modules/bedrock-kb/main.tf'],
      ['S3 — ALB access logs', 'AES-256 SSE-S3', 'AWS-managed', 'deployments/ecs/${env}/main.tf'],
      ['S3 — CloudTrail logs', 'AES-256 SSE-KMS', 'CMK alias/vocuone-${env}-logs', 'modules/cloudtrail/main.tf'],
      ['S3 — Pipeline artifacts', 'AES-256 SSE-S3', 'AWS-managed', 'modules/cicd/main.tf'],
      ['S3 — Canary artifacts', 'AES-256 SSE-S3', 'AWS-managed', 'modules/synthetics/main.tf'],
      ['CloudWatch Logs — ECS app', 'AES-256', 'CMK alias/vocuone-${env}-logs', 'modules/ecs-service/main.tf:5-13'],
      ['CloudWatch Logs — Bedrock invocations', 'AES-256', 'Dedicated CMK', 'deployments/shared/bedrock-logging/main.tf'],
      ['CloudWatch Logs — RDS postgresql + upgrade', 'AES-256', 'CMK alias/vocuone-${env}-logs', 'modules/rds/main.tf (pre-created log groups)'],
      ['CloudWatch Logs — VPC flow logs', 'AES-256', 'CMK alias/vocuone-${env}-logs', 'modules/vpc/main.tf'],
      ['CloudWatch Logs — CloudTrail', 'AES-256', 'CMK alias/vocuone-${env}-logs', 'modules/cloudtrail/main.tf'],
      ['CloudTrail trail itself', 'AES-256', 'CMK alias/vocuone-${env}-logs', 'modules/cloudtrail/main.tf'],
      ['AWS Secrets Manager — DB credentials', 'AES-256', 'CMK alias/vocuone-${env}-secrets', 'modules/rds/main.tf:90-94'],
      ['AWS Secrets Manager — other (non-PHI)', 'AES-256', 'AWS-managed aws/secretsmanager', 'Per-secret'],
      ['EBS — ECS instance root volumes', 'AES-256', 'CMK alias/vocuone-${env}-logs', 'modules/ecs-cluster/main.tf:42-52'],
      ['EBS — RDS storage volumes', 'AES-256', 'Inherits RDS instance key', 'AWS-managed'],
      ['AWS Backup vault', 'AES-256', 'CMK alias/vocuone-${env}-backup', 'modules/backup/main.tf'],
      ['ECR image layers', 'AES-256', 'CMK alias/vocuone-${env}-ecr', 'deployments/ecs/${env}/main.tf (KMS module)'],
    ],
    [2640, 1600, 2640, 2480],
  ),
  spacer(),
  p('Continuous verification: bash scripts/hipaa-encryption-audit.sh ${env} enumerates every encrypted resource and verifies the encryption key.'),

  h2('§164.312(b) Audit Controls'),
  buildTable(
    ['Audit source', 'Encryption', 'Retention', 'Code reference'],
    [
      ['AWS CloudTrail (management events, all API calls)', 'CMK', 'S3: 7+ years (no expiry); CWL tail: 365 days', 'modules/cloudtrail/main.tf'],
      ['CloudTrail data events on KB S3 buckets', 'CMK', 'Same as above', 'modules/cloudtrail/main.tf'],
      ['Application logs (/ecs/${env}-app)', 'CMK', '2557 days (7 years)', 'modules/ecs-service/main.tf:5-13'],
      ['Bedrock invocation logs', 'CMK', '2557 days (7 years)', 'deployments/shared/bedrock-logging/main.tf'],
      ['RDS PostgreSQL audit logs', 'CMK', '2557 days (7 years)', 'modules/rds/main.tf'],
      ['RDS upgrade logs', 'CMK', '2557 days (7 years)', 'modules/rds/main.tf'],
      ['VPC flow logs', 'CMK', '365 days (no PHI content; metadata only)', 'modules/vpc/main.tf'],
      ['AWS Config (recommended; not currently enabled)', '—', '—', 'See §11 future enhancements'],
    ],
    [2880, 1280, 2400, 2800],
  ),
  spacer(),
  p('Integrity assurance: CloudTrail log file validation is enabled (enable_log_file_validation = true) so tampered audit logs can be detected.'),

  h2('§164.312(c) Integrity'),
  bullet('RDS automated backups with point-in-time recovery (PITR), backup retention 7 days minimum'),
  bullet('AWS Backup vault for cross-service backup (RDS + future EFS/EBS)'),
  bullet('CloudTrail log file integrity validation (enable_log_file_validation)'),
  bullet('S3 versioning + object lock available on KB buckets (configurable per bucket; currently versioning-only)'),
  bullet('KMS key rotation enabled on every CMK (enable_key_rotation = true)'),

  h2('§164.312(d) Person or Entity Authentication'),
  buildTable(
    ['Authentication path', 'Mechanism'],
    [
      ['End user (clinician) → API', 'TLS + JWT issued by app auth layer (out of scope for infra)'],
      ['GitHub Actions → AWS', 'OIDC sts:AssumeRoleWithWebIdentity with sub/aud claim pinning'],
      ['ECS task → AWS services', 'IAM task role (per-task short-lived credentials via IMDSv2)'],
      ['ECS task → RDS', 'IAM database authentication (rds-db:connect) + Secrets Manager-vended password (dual-auth)'],
      ['ECS task → Bedrock', 'IAM task role'],
      ['Operator → AWS Console', 'IAM user + hardware MFA enforcement'],
      ['Operator → EC2 instance', 'SSM Session Manager (no SSH); session logged to CloudWatch'],
      ['AWS service-to-service', 'Service principal trust policies with aws:SourceAccount + aws:SourceArn confused-deputy guards'],
    ],
    [3360, 6000],
  ),

  h2('§164.312(e)(1) Transmission Security'),
  p('Every PHI transmission path uses TLS 1.2 or higher except for AWS-internal traffic on AWS regional network with compensating controls:'),
  buildTable(
    ['Path', 'Protection'],
    [
      ['Browser → CloudFront', 'TLS 1.2+ (MinimumProtocolVersion = TLSv1.2_2021)'],
      ['CloudFront → ALB', 'TLS 1.2+ via ACM cert'],
      ['Client → API Gateway', 'TLS 1.2+ (AWS-managed)'],
      ['API Gateway → ALB :80', 'HTTP, AWS-internal network. Compensating controls: (a) AWS WAF Web ACL on the ALB requires X-Gateway-Secret header per request, blocking direct-to-ALB traffic from outside AWS regional network; (b) ALB is internet-facing but all PHI traffic flows through API Gateway which terminates TLS; (c) the traffic never traverses the public internet — AWS regional managed-service routing only. Pattern consistent with AWS HIPAA reference architecture.'],
      ['ALB → ECS task', 'HTTP within VPC private subnet. Compensating control: full VPC network isolation, security-group-restricted (only ALB SG can reach ECS SG), no public IP on tasks. Aligned with AWS HIPAA reference architecture.'],
      ['ECS task → RDS', 'TLS enforced at parameter group (rds.force_ssl=1); app rejects non-TLS connections'],
      ['ECS task → Bedrock / S3 / Secrets Manager / CloudWatch', 'HTTPS by default via AWS SDK; VPC endpoints enabled for in-VPC routing'],
      ['Cross-region replication (if enabled)', 'HTTPS (AWS-managed)'],
    ],
    [2880, 6480],
  ),
];

// --- Section 6: Administrative Safeguards -------------------------------
const section6 = [
  h1('6. Administrative Safeguards — 45 CFR §164.308', { pageBreakBefore: true }),

  h2('§164.308(a)(1) Security Management Process'),
  bullet('Risk analysis (§164.308(a)(1)(ii)(A)): Documented in this attestation and the audit script. Quarterly review cadence.'),
  bullet('Risk management (§164.308(a)(1)(ii)(B)): Tracked in §11 (Known Gaps & Remediation Plan).'),
  bullet('Sanction policy (§164.308(a)(1)(ii)(C)): Internal HR policy, not infrastructure.'),
  bullet('Information system activity review (§164.308(a)(1)(ii)(D)): CloudTrail + CloudWatch Logs Insights queries; alarms in observability-alarms.tf and backend-health-alarms.tf provide active monitoring.'),

  h2('§164.308(a)(2) Assigned Security Responsibility'),
  bullet('Designated Security Officer: Dhrumil Mehta (DevOps lead)'),
  bullet('Designated Privacy Officer: [to be assigned by leadership — not infrastructure-side]'),

  h2('§164.308(a)(3) Workforce Security'),
  bullet('Authorization and/or supervision (§164.308(a)(3)(ii)(A)): IAM access granted per-role via Terraform-managed roles; access reviews on cadence'),
  bullet('Workforce clearance (§164.308(a)(3)(ii)(B)): Internal HR process'),
  bullet('Termination procedures (§164.308(a)(3)(ii)(C)): IAM identity removed within 24 hours of termination (manual process; recommend automating via SSO/SCIM)'),

  h2('§164.308(a)(4) Information Access Management — Minimum Necessary'),
  bullet('Isolation of healthcare clearinghouse (§164.308(a)(4)(ii)(A)): N/A — vocuone is not a clearinghouse'),
  bullet('Access authorization (§164.308(a)(4)(ii)(B)): IAM policies enforce least privilege per role. Service-linked roles used where applicable.'),
  bullet('Access establishment and modification (§164.308(a)(4)(ii)(C)): All access is code in Terraform; changes require PR + apply via OIDC. Audit trail in git + CloudTrail.'),
  p('Tracked remediation: Two long-lived IAM access keys (vocuone-prod-developer, vocuone-stage-developer) exist for human operator access. These are scheduled for replacement with federated SSO / OIDC-vended short-lived credentials. See §11.', { italics: true }),

  h2('§164.308(a)(5) Security Awareness and Training'),
  bullet('Internal training program (not infrastructure-side)'),
  bullet('Anti-phishing, PHI handling, and incident reporting documented in employee handbook'),

  h2('§164.308(a)(6) Security Incident Procedures'),
  bullet('Active alarms on backend 5xx, ECS capacity, Bedrock latency, canary failure, AI call error rate — routed via SNS to developers@vocuone.ai'),
  bullet('Incident response runbook (to be formalized in runbooks/incident-response.md)'),
  bullet('CloudTrail provides forensic audit trail; logs retained 7+ years'),

  h2('§164.308(a)(7) Contingency Plan'),
  buildTable(
    ['Sub-rule', 'Implementation'],
    [
      ['(i) Data backup plan', 'RDS automated backups, 7-day PITR (prod), AWS Backup vault for cross-service'],
      ['(ii) Disaster recovery plan', 'Multi-AZ RDS (prod), S3 cross-region replication available, infrastructure entirely IaC for rapid rebuild'],
      ['(iii) Emergency mode operation plan', 'Documented operator runbook; canary alerts on degradation'],
      ['(iv) Testing and revision procedures', 'Quarterly DR test (recommend formalizing; current state: ad-hoc)'],
      ['(v) Applications and data criticality analysis', 'Tier 1: RDS + Bedrock KB; Tier 2: app logs; Tier 3: CI/CD'],
    ],
    [3360, 6000],
  ),

  h2('§164.308(a)(8) Evaluation'),
  bullet('Self-attestation via this document'),
  bullet('Continuous verification via scripts/hipaa-encryption-audit.sh'),
  bullet('Annual third-party HIPAA assessment (recommended; not yet engaged)'),
];

// --- Section 7: Physical Safeguards -------------------------------------
const section7 = [
  h1('7. Physical Safeguards — 45 CFR §164.310'),
  p('All physical safeguards (§164.310(a)(1) Facility Access Controls, §164.310(b) Workstation Use, §164.310(c) Workstation Security, §164.310(d) Device and Media Controls) for AWS-hosted infrastructure are inherited from AWS via the signed Business Associate Addendum.'),
  p('AWS physical safeguards are independently assessed and documented in:'),
  bullet('AWS SOC 1, SOC 2, SOC 3 reports (available via AWS Artifact)'),
  bullet('AWS ISO 27001 / 27017 / 27018 certifications'),
  bullet('AWS FedRAMP authorization'),
  bullet('AWS HIPAA whitepaper "Architecting for HIPAA Security and Compliance on Amazon Web Services"'),
  p('Customer responsibility: Endpoints (developer laptops) running AWS CLI / browser access — managed under separate device management policy (not infrastructure-side).', { italics: true }),
];

// --- Section 8: Organizational requirements -----------------------------
const section8 = [
  h1('8. Organizational Requirements — 45 CFR §164.314'),

  h2('§164.314(a) Business Associate Contracts'),
  bullet('AWS BAA: Signed via AWS Artifact (verify in https://console.aws.amazon.com/artifact/home#/agreements). AWS BAA covers all HIPAA-eligible services listed in §4.'),
  bullet('Subcontractor BAAs: All third-party SaaS vendors that touch PHI must have a BAA. Currently no third-party PHI processors are in use (Sentry, SendGrid configured for non-PHI events only; Google Calendar disabled).'),

  h2('§164.314(b) Group Health Plan Requirements'),
  p('N/A — vocuone is not a group health plan.'),
];

// --- Section 9: Documentation + Retention -------------------------------
const section9 = [
  h1('9. Documentation and Retention — 45 CFR §164.316, §164.530(j)(2)'),

  h2('§164.316 Policies and procedures'),
  bullet('This document constitutes the security policy attestation'),
  bullet('Infrastructure-as-code (Terraform) provides authoritative reference for technical controls'),
  bullet('Git history provides audit trail of all infrastructure changes'),

  h2('§164.530(j)(2) Six-year retention'),
  p('All PHI-bearing audit logs retain for 7 years (2557 days):'),
  bullet('/ecs/${env}-app (Spring Boot logs)'),
  bullet('/aws/bedrock/vocuone-invocations (LLM input/output)'),
  bullet('/aws/rds/instance/${env}-db/postgresql (DB audit)'),
  bullet('/aws/rds/instance/${env}-db/upgrade'),
  bullet('CloudTrail logs (S3, no expiry)'),
  p('Non-PHI audit logs (VPC flow logs, CloudTrail CWL tail) retain 365 days, as they contain network metadata only, not PHI.', { italics: true }),
];

// --- Section 10: Continuous Verification --------------------------------
const auditScriptExample = [
  'bash scripts/hipaa-encryption-audit.sh stage    # or prod',
];

const section10 = [
  h1('10. Continuous Compliance Verification'),

  h2('scripts/hipaa-encryption-audit.sh'),
  p('A self-service audit script in the repository enumerates every PHI-handling resource and verifies its encryption state. Usage:'),
  ...codeBlock(auditScriptExample, { size: 18 }),
  spacer(),
  p('The script checks:'),
  bullet('RDS storage, Performance Insights, snapshots, in-transit TLS (rds.force_ssl)'),
  bullet('S3 buckets matching ${project}-${env}-*'),
  bullet('EBS volumes attached to ECS instances'),
  bullet('CloudWatch Log Groups (encryption + 7-year retention for PHI groups)'),
  bullet('CloudTrail (encryption, log validation)'),
  bullet('Secrets Manager (encryption presence)'),
  bullet('ALB listeners (HTTPS / redirect / WAF-gated HTTP)'),
  bullet('CloudFront (TLS minimum version, viewer protocol policy)'),
  bullet('Bedrock invocation logging (encryption + retention)'),
  p('Exit code is non-zero if any check fails, suitable for periodic CI verification.'),

  h2('Active monitoring (CloudWatch alarms → SNS → email)'),
  buildTable(
    ['Alarm category', 'Source', 'Code reference'],
    [
      ['ECS CPU/Memory', 'AWS/ECS metrics', 'deployments/ecs/${env}/main.tf'],
      ['Backend HTTP 5xx (target + ELB layer)', 'AWS/ApplicationELB metrics', 'deployments/ecs/${env}/backend-health-alarms.tf'],
      ['Synthetics canary failure', 'CloudWatchSynthetics SuccessPercent', 'modules/synthetics/main.tf'],
      ['Bedrock invocation rate, latency p95, throttling, errors', 'AWS/Bedrock metrics', 'deployments/ecs/${env}/observability-alarms.tf'],
      ['AI call error rate (app-level metric filter)', 'CloudWatch Logs metric filter', 'deployments/ecs/${env}/observability-alarms.tf'],
      ['RDS performance (planned)', 'AWS/RDS metrics', 'To be added'],
    ],
    [3000, 3000, 3360],
  ),
];

// --- Section 11: Known Gaps ---------------------------------------------
const section11 = [
  h1('11. Known Gaps and Remediation Plan', { pageBreakBefore: true }),
  buildTable(
    ['#', 'Item', 'HIPAA citation', 'Severity', 'Status', 'Target'],
    [
      ['1', 'Replace vocuone-prod-developer + vocuone-stage-developer long-lived IAM users with federated SSO / OIDC short-lived credentials', '§164.308(a)(4)', 'Medium', 'Planned', 'Before prod cutover with hospital customers'],
      ['2', 'Tighten CI/CD policy from <service>:* + Resource = "*" to per-resource scoping', '§164.308(a)(4) (defense-in-depth)', 'Low', 'Planned', 'Q3 follow-up sprint'],
      ['3', 'Pin transcribe:* and comprehendmedical:* task-role permissions to specific output ARN', '§164.308(a)(4)', 'Low', 'Planned', 'Same sprint as #2'],
      ['4', 'Pin RDS rds-db:connect to specific dbuser instead of dbuser:*/*', '§164.308(a)(4)', 'Low', 'Planned', 'Same sprint as #2'],
      ['5', 'Enable AWS Config for continuous compliance recording', '§164.308(a)(1)(ii)(D)', 'Low', 'Recommended', 'Backlog'],
      ['6', 'Formalize incident response runbook in runbooks/incident-response.md', '§164.308(a)(6)', 'Low', 'Planned', 'Q3'],
      ['7', 'Annual third-party HIPAA assessment engagement', '§164.308(a)(8)', 'Recommended', 'Pending leadership decision', 'TBD'],
    ],
    [400, 3360, 1600, 1000, 1200, 1800],
  ),
  spacer(),
  p('None of the gaps prevent BAA-bar compliance per the AWS HIPAA Shared Responsibility Model. Items 1–4 are tracked for hardening prior to onboarding the first hospital / insurer customer who issues a security questionnaire.'),
];

// --- Section 12: Key Inventory ------------------------------------------
const section12 = [
  h1('12. Cryptographic Key Inventory'),
  p('All Customer Master Keys (CMKs) used to protect PHI, with rotation enabled:'),
  buildTable(
    ['Key alias', 'Purpose', 'Code reference'],
    [
      ['alias/vocuone-${env}-logs', 'CloudWatch Logs, CloudTrail, SNS, EBS, ECR image', 'deployments/ecs/${env}/main.tf'],
      ['alias/vocuone-${env}-rds', 'RDS storage, Performance Insights', 'deployments/ecs/${env}/main.tf'],
      ['alias/vocuone-${env}-secrets', 'Secrets Manager (PHI-related secrets)', 'deployments/ecs/${env}/main.tf'],
      ['alias/vocuone-${env}-ecr', 'ECR image encryption', 'deployments/ecs/${env}/main.tf'],
      ['alias/vocuone-${env}-backup', 'AWS Backup vault', 'deployments/ecs/${env}/main.tf'],
      ['alias/vocuone-bedrock-invocations', 'Bedrock invocation log group (account-wide singleton)', 'deployments/shared/bedrock-logging/main.tf'],
    ],
    [3200, 3600, 2560],
  ),
  spacer(),
  p('All keys have enable_key_rotation = true (annual automatic AWS key rotation) and deletion_window_in_days = 30 (no accidental immediate deletion).'),
];

// --- Section 13: Sign-off -----------------------------------------------
const section13 = [
  h1('13. Acceptance and Sign-off', { pageBreakBefore: true }),
  p('This document attests that the AWS infrastructure described herein has been designed and implemented to comply with the HIPAA Security Rule (45 CFR Part 164, Subpart C). The undersigned acknowledges:'),
  bullet('1. The implementation of administrative, physical, and technical safeguards as described'),
  bullet('2. The signed AWS Business Associate Addendum covering all HIPAA-eligible services in use'),
  bullet('3. The known gaps listed in §11 and the remediation timeline'),
  bullet('4. The continuous verification mechanisms (audit script, CloudWatch alarms) that ensure ongoing compliance'),
  bullet('5. The commitment to update this document with material changes to the infrastructure'),
  spacer(),
  spacer(),
  buildTable(
    ['Role', 'Name', 'Signature', 'Date'],
    [
      ['Security Officer (DevOps Lead)', 'Dhrumil Mehta', '', ''],
      ['Privacy Officer', '', '', ''],
      ['CTO / Engineering Lead', '', '', ''],
    ],
    [2800, 2160, 2400, 2000],
  ),
];

// --- Appendices ---------------------------------------------------------
const repoLayout = [
  'deployments/',
  '  ecs/{stage,prod}/                        Main application stack',
  '    main.tf                                ECS service, KMS, ALB, RDS, CloudTrail',
  '    backend-health-alarms.tf               ALB 5xx alarms',
  '    observability-alarms.tf                Bedrock / AI / Comprehend alarms',
  '  bedrock/{stage,prod}/                    Bedrock KB + Agent stack',
  '  shared/',
  '    iam/                                   OIDC roles, CI/CD policy',
  '    iam-{stage,prod}/                      Developer access (remediation pending)',
  '    bedrock-logging/                       Account-wide Bedrock invocation logging',
  'modules/',
  '  alb/                                     ALB + WAF gating',
  '  bedrock-kb/                              KB + S3 buckets',
  '  cicd/                                    CodePipeline + CodeDeploy',
  '  cloudtrail/                              Audit trail',
  '  codedeploy/                              Blue/green deployments',
  '  ecs-cluster/                             ECS cluster + ASG + launch template',
  '  ecs-service/                             ECS task definitions + IAM',
  '  kms/                                     KMS module',
  '  rds/                                     PostgreSQL + parameter group + log groups',
  '  s3-frontend/                             Frontend bucket + CloudFront OAC',
  '  security-groups/                         VPC SGs',
  '  synthetics/                              Canary',
  '  vpc/                                     VPC, subnets, NAT, flow logs',
  'scripts/',
  '  hipaa-encryption-audit.sh                Self-service compliance check',
  'docs/',
  '  HIPAA-COMPLIANCE.md                      Markdown source for this document',
  '  HIPAA-COMPLIANCE.docx                    This Word document',
];

const appendices = [
  h1('Appendix A — References', { pageBreakBefore: true }),
  bullet('45 CFR §160, §162, §164 — HIPAA Administrative Simplification Rules'),
  bullet('NIST SP 800-66 Rev. 2 — Implementing the HIPAA Security Rule'),
  bullet('NIST SP 800-53 Rev. 5 — Security and Privacy Controls'),
  bullet('AWS HIPAA Compliance — https://aws.amazon.com/compliance/hipaa-compliance/'),
  bullet('AWS HIPAA Eligible Services Reference — https://aws.amazon.com/compliance/hipaa-eligible-services-reference/'),
  bullet('AWS Architecting for HIPAA Security and Compliance Whitepaper — https://docs.aws.amazon.com/whitepapers/latest/architecting-hipaa-security-and-compliance-on-aws/'),
  bullet('HHS Guidance on HIPAA & Cloud Computing — https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html'),

  h1('Appendix B — Repository Layout'),
  ...codeBlock(repoLayout, { size: 18 }),

  h1('Appendix C — Document History'),
  buildTable(
    ['Version', 'Date', 'Author', 'Changes'],
    [
      ['1.0', '2026-05-19', 'Dhrumil Mehta', 'Initial attestation document'],
    ],
    [1200, 1800, 2400, 3960],
  ),
];

// --- Document assembly --------------------------------------------------
const doc = new Document({
  creator: 'Dhrumil Mehta / vocuone DevOps',
  title: 'HIPAA Compliance Attestation — vocuone / vocanote-ai Production Infrastructure',
  description: 'HIPAA Security Rule attestation for AWS infrastructure',
  styles: {
    default: {
      document: { run: { font: BODY_FONT, size: 22 } },
    },
    paragraphStyles: [
      {
        id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: BODY_FONT, size: 36, bold: true, color: ACCENT },
        paragraph: { spacing: { before: 360, after: 180 }, outlineLevel: 0 },
      },
      {
        id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: BODY_FONT, size: 28, bold: true, color: ACCENT },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 },
      },
      {
        id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: BODY_FONT, size: 24, bold: true, color: '404040' },
        paragraph: { spacing: { before: 180, after: 100 }, outlineLevel: 2 },
      },
    ],
  },
  numbering: {
    config: [
      {
        reference: 'bullets',
        levels: [{
          level: 0,
          format: LevelFormat.BULLET,
          text: '•',
          alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 540, hanging: 360 } } },
        }],
      },
    ],
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },        // US Letter
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      },
    },
    footers: {
      default: new Footer({
        children: [
          new Paragraph({
            tabStops: [
              { type: TabStopType.CENTER, position: 4680 },
              { type: TabStopType.RIGHT,  position: 9360 },
            ],
            children: [
              new TextRun({
                text: 'vocuone — HIPAA Compliance Attestation — Confidential',
                font: BODY_FONT, size: 16, color: '808080',
              }),
              new TextRun({ text: '\t', font: BODY_FONT, size: 16 }),
              new TextRun({ text: 'Page ', font: BODY_FONT, size: 16, color: '808080' }),
              new TextRun({ children: [PageNumber.CURRENT], font: BODY_FONT, size: 16, color: '808080' }),
              new TextRun({ text: ' of ', font: BODY_FONT, size: 16, color: '808080' }),
              new TextRun({ children: [PageNumber.TOTAL_PAGES], font: BODY_FONT, size: 16, color: '808080' }),
              new TextRun({ text: '\t', font: BODY_FONT, size: 16 }),
              new TextRun({
                text: 'v1.0 — 2026-05-19',
                font: BODY_FONT, size: 16, color: '808080',
              }),
            ],
          }),
        ],
      }),
    },
    children: [
      ...titlePage,
      ...toc,
      ...section1,
      ...section2,
      ...section3,
      ...section4,
      ...section5,
      ...section6,
      ...section7,
      ...section8,
      ...section9,
      ...section10,
      ...section11,
      ...section12,
      ...section13,
      ...appendices,
    ],
  }],
});

Packer.toBuffer(doc).then(buffer => {
  const outPath = path.join(__dirname, 'HIPAA-COMPLIANCE.docx');
  fs.writeFileSync(outPath, buffer);
  console.log(`Wrote ${outPath} (${(buffer.length / 1024).toFixed(1)} KB)`);
}).catch(err => {
  console.error('Failed to generate docx:', err);
  process.exit(1);
});
