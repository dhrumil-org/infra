// Builds D:/infra/docs/HIPAA-COMPLIANCE.docx from the slim attestation.
// Run: node D:/infra/docs/build-docx.js
// Requires: npm install -g docx

const path = require('path');
const fs = require('fs');

const docxPath = path.join(process.env.APPDATA, 'npm', 'node_modules', 'docx');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Footer, AlignmentType, LevelFormat, TabStopType,
  HeadingLevel, BorderStyle, WidthType, ShadingType, PageNumber, PageBreak,
  TableOfContents,
} = require(docxPath);

const BODY_FONT = 'Calibri';
const MONO_FONT = 'Consolas';
const ACCENT = '2E75B6';
const HEADER_FILL = '2E75B6';
const HEADER_TEXT = 'FFFFFF';
const CODE_FILL = 'F2F2F2';
const BORDER = { style: BorderStyle.SINGLE, size: 6, color: '8C8C8C' };
const CELL_BORDERS = { top: BORDER, bottom: BORDER, left: BORDER, right: BORDER };

// -- helpers ------------------------------------------------------------
function p(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 120 },
    children: [new TextRun({
      text: text || '',
      font: BODY_FONT,
      size: opts.size || 22,
      bold: opts.bold,
      italics: opts.italics,
      color: opts.color || '000000',
    })],
  });
}

function h1(text, opts = {}) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    pageBreakBefore: opts.pageBreakBefore,
    spacing: { before: 360, after: 180 },
    children: [new TextRun({ text, font: BODY_FONT, size: 36, bold: true, color: ACCENT })],
  });
}

function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 240, after: 120 },
    children: [new TextRun({ text, font: BODY_FONT, size: 28, bold: true, color: ACCENT })],
  });
}

function mono(text, size = 16) {
  return new Paragraph({
    spacing: { after: 60 },
    shading: { type: ShadingType.CLEAR, fill: CODE_FILL },
    children: [new TextRun({ text, font: MONO_FONT, size })],
  });
}

function bullet(text) {
  return new Paragraph({
    numbering: { reference: 'bullets', level: 0 },
    spacing: { after: 60 },
    children: [new TextRun({ text, font: BODY_FONT, size: 22 })],
  });
}

function cell(text, width, opts = {}) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders: CELL_BORDERS,
    margins: { top: 100, bottom: 100, left: 140, right: 140 },
    shading: opts.fill ? { type: ShadingType.CLEAR, fill: opts.fill } : undefined,
    children: [new Paragraph({
      spacing: { after: 0 },
      children: [new TextRun({
        text: text || '',
        font: opts.mono ? MONO_FONT : BODY_FONT,
        size: opts.size || 20,
        bold: opts.bold,
        color: opts.color || '000000',
      })],
    })],
  });
}

function tbl(headers, rows, widths) {
  return new Table({
    width: { size: widths.reduce((a, b) => a + b, 0), type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({
        tableHeader: true,
        children: headers.map((h, i) => cell(h, widths[i], { fill: HEADER_FILL, color: HEADER_TEXT, bold: true })),
      }),
      ...rows.map(r => new TableRow({ children: r.map((c, i) => cell(c, widths[i])) })),
    ],
  });
}

function spacer() {
  return new Paragraph({ spacing: { after: 80 }, children: [new TextRun({ text: ' ', font: BODY_FONT, size: 22 })] });
}

// -- content ------------------------------------------------------------

const titlePage = [
  new Paragraph({
    spacing: { before: 2400, after: 360 },
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: 'HIPAA Compliance Attestation', font: BODY_FONT, size: 56, bold: true, color: ACCENT })],
  }),
  new Paragraph({
    spacing: { after: 600 },
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: 'vocuone', font: BODY_FONT, size: 36, color: '404040' })],
  }),
  tbl(['Property', 'Value'], [
    ['Version', '1.0'],
    ['Last updated', '2026-05-19'],
    ['Owner', 'DevOps Lead'],
    ['Status', 'Draft for review'],
    ['Scope', 'AWS account 499290259511, region us-east-1, envs stage + prod'],
    ['Standards', 'HIPAA Security Rule (45 CFR §164.302–.318), §164.530(j)(2), AWS HIPAA Shared Responsibility Model, NIST SP 800-66'],
  ], [2640, 6720]),
  new Paragraph({
    spacing: { before: 1200 },
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: 'Confidential — Internal compliance documentation', font: BODY_FONT, size: 20, italics: true, color: '808080' })],
  }),
  new Paragraph({ children: [new PageBreak()] }),
];

const toc = [
  h1('Table of Contents'),
  new TableOfContents('Contents', { hyperlink: true, headingStyleRange: '1-2' }),
  new Paragraph({ children: [new PageBreak()] }),
];

const sec1 = [
  h1('1. Executive Summary'),
  p('vocuone runs a clinical case-companion app processing PHI exclusively on HIPAA-eligible AWS services under a signed BAA. All technical safeguards are implemented as code in this Terraform repository and continuously verified by scripts/hipaa-encryption-audit.sh.'),
  tbl(['HIPAA Section', 'Status'], [
    ['§164.308 Administrative', 'Compliant'],
    ['§164.310 Physical', 'Inherited from AWS via BAA'],
    ['§164.312 Technical', 'Compliant'],
    ['§164.314 Organizational', 'AWS BAA in force'],
    ['§164.316 / §164.530(j)(2) Docs + 7yr retention', 'Compliant'],
  ], [4680, 4680]),
];

const sec2 = [
  h1('2. Scope'),
  p('In scope: AWS account 499290259511, us-east-1, stage + prod environments. Traffic path: client → CloudFront → API Gateway → ALB → ECS task → RDS / Bedrock / S3.'),
  p('Out of scope: Application code (separate review), endpoint security, AWS physical security (BAA-inherited).'),
];

const archLines = [
  '[Browser] —TLS1.2+→ [CloudFront] —TLS→ [ALB :443]',
  '[Browser] —TLS1.2+→ [API Gateway] —HTTP*→ [ALB :80] —HTTP→ [ECS task]',
  '                                                              │',
  '       ┌──────────────────────────────────────────────────────┤',
  '       ▼                ▼                ▼                    ▼',
  '  [RDS Postgres]   [Bedrock KB]    [Secrets Mgr]      [CloudWatch Logs]',
  '   (CMK, TLS)      (SSE-S3)         (CMK)             (CMK, 7yr ret.)',
  '       │                                                      ▲',
  '       └──► Automated backups + AWS Backup vault (CMK)        │',
  '                                                              │',
  '[All API calls] ────────────────────► [CloudTrail S3 (CMK) + CWL tail]',
  '',
  '* API Gateway → ALB :80 hop is plaintext on AWS-internal network only;',
  '  gated by WAF requiring X-Gateway-Secret header. Direct-to-ALB blocked.',
];

const sec3 = [
  h1('3. Architecture'),
  ...archLines.map(l => mono(l, 16)),
  spacer(),
  p('Key properties: every PHI store uses AES-256 (CMK where customer-managed); all public-facing TLS 1.2+; ECS tasks in private subnets with no public IP; RDS reachable only from ECS security group with rds.force_ssl=1; WAF gates the ALB; CloudTrail log file validation on.'),
];

const sec4 = [
  h1('4. AWS Services & HIPAA Eligibility'),
  p('Every service handling PHI is on the current AWS HIPAA Eligible Services Reference list.'),
  tbl(['Service', 'Purpose', 'PHI?'], [
    ['EC2 + ECS + EBS', 'App compute', 'Transient'],
    ['RDS PostgreSQL', 'Primary patient DB', 'Durable'],
    ['S3 (KB buckets)', 'KB documents', 'Durable'],
    ['Bedrock + Bedrock Agents', 'LLM inference, KB retrieval', 'In-flight + retrieval'],
    ['CloudFront + API Gateway + ALB + WAF', 'Public ingress', 'In-flight'],
    ['Lambda', 'CodeDeploy hook, Synthetics canary', 'No'],
    ['CloudWatch + CloudTrail', 'Audit + logs', 'Durable (audit)'],
    ['Secrets Manager', 'DB creds', 'Creds only'],
    ['KMS', 'Encryption keys', 'No (keys)'],
    ['AWS Backup', 'Cross-service backup', 'Durable (snapshots)'],
    ['VPC, Route 53, ACM, Inspector, SSM, EventBridge, SNS, Synthetics, CodePipeline/Deploy/Build', 'Supporting', 'No / N/A'],
  ], [2880, 4560, 1920]),
  spacer(),
  p('Audit script confirms only HIPAA-eligible services are touched.'),
];

const sec5 = [
  h1('5. Technical Safeguards (§164.312)', { pageBreakBefore: true }),

  h2('Encryption at rest (§164.312(a)(2)(iv))'),
  p('Every PHI store is AES-256 encrypted:'),
  tbl(['Store', 'Key'], [
    ['RDS storage + Perf Insights + automated snapshots', 'CMK alias/vocuone-${env}-rds'],
    ['EBS — ECS root volumes', 'CMK alias/vocuone-${env}-logs'],
    ['S3 — Bedrock KB / ALB logs / pipeline / canary', 'AES-256 SSE-S3 (BAA-acceptable)'],
    ['S3 — CloudTrail', 'SSE-KMS, CMK alias/vocuone-${env}-logs'],
    ['CWL — app, Bedrock, RDS postgresql, VPC flow, CloudTrail', 'CMK alias/vocuone-${env}-logs (Bedrock has dedicated CMK)'],
    ['Secrets Manager (PHI-bearing)', 'CMK alias/vocuone-${env}-secrets'],
    ['AWS Backup vault', 'CMK alias/vocuone-${env}-backup'],
    ['ECR images', 'CMK alias/vocuone-${env}-ecr'],
  ], [4560, 4800]),
  spacer(),
  p('All CMKs have key rotation enabled and a 30-day deletion window. Continuous verification: bash scripts/hipaa-encryption-audit.sh ${env}.'),

  h2('Encryption in transit (§164.312(e))'),
  tbl(['Path', 'Protection'], [
    ['Browser → CloudFront → ALB', 'TLS 1.2+ (ACM certs, ELBSecurityPolicy-TLS13-1-2-2021-06)'],
    ['Client → API Gateway', 'TLS 1.2+ (AWS-managed)'],
    ['API Gateway → ALB :80', 'HTTP on AWS regional network; WAF gate (X-Gateway-Secret); compensating control per AWS HIPAA reference architecture'],
    ['ALB → ECS task', 'HTTP intra-VPC private subnet; SG-restricted; AWS-standard pattern'],
    ['ECS → RDS', 'TLS enforced (rds.force_ssl=1)'],
    ['ECS → AWS services (Bedrock, S3, Secrets Mgr, CloudWatch)', 'HTTPS by default (AWS SDK)'],
  ], [3360, 6000]),

  h2('Access control (§164.312(a)(1))'),
  bullet('Apps: ECS task IAM roles with per-task credentials via IMDSv2; RDS IAM database auth + Secrets Manager-vended password (dual auth).'),
  bullet('CI/CD: GitHub Actions OIDC sts:AssumeRoleWithWebIdentity, sub/aud claims pinned to repo + branch + environment. No long-lived CI keys.'),
  bullet('Operators: SSM Session Manager (no SSH); MFA on console; CloudTrail logged.'),
  bullet('Service-to-service: trust policies with aws:SourceAccount + aws:SourceArn confused-deputy guards.'),

  h2('Audit controls + integrity (§164.312(b), (c))'),
  bullet('CloudTrail (all API events + KB S3 data events) → S3 (no expiry) + CWL tail (365d); log file validation on.'),
  bullet('App/Bedrock/RDS audit log groups: CMK + 2557d (7yr) retention per §164.530(j)(2).'),
  bullet('KMS key rotation, S3 versioning on KB buckets, RDS PITR.'),

  h2('Authentication (§164.312(d))'),
  p('JWT for end users; OIDC for CI; IAM roles for services; MFA + SSM for operators.'),
];

const sec6 = [
  h1('6. Administrative Safeguards (§164.308)'),
  tbl(['Sub-section', 'Implementation'], [
    ['(a)(1) Security mgmt', 'Risk analysis = this doc + audit script; quarterly review'],
    ['(a)(2) Security Officer', 'DevOps Lead (named in Sign-off)'],
    ['(a)(3) Workforce security', 'IAM access via Terraform; termination removes IAM identity ≤24h'],
    ['(a)(4) Min necessary', 'Per-role IAM policies; access changes via PR + OIDC apply'],
    ['(a)(6) Incident procedures', 'CloudWatch alarms → SNS → on-call; CloudTrail for forensics'],
    ['(a)(7) Contingency', 'Multi-AZ RDS (prod), PITR 7d, AWS Backup vault, full IaC for rebuild'],
    ['(a)(8) Evaluation', 'Self-attestation + continuous audit script; third-party assessment planned'],
  ], [3360, 6000]),
];

const sec7 = [
  h1('7. Physical Safeguards (§164.310)'),
  p('Inherited from AWS via the signed BAA. AWS SOC 1/2/3, ISO 27001/17/18, FedRAMP authorizations cover facility access, workstation use, device/media controls for the underlying infrastructure. Customer-side endpoint security under separate device-management policy.'),
];

const sec8 = [
  h1('8. Organizational Requirements (§164.314)'),
  p('AWS BAA signed via AWS Artifact, covering all HIPAA-eligible services in use. No subcontractor BAAs currently needed — Sentry/SendGrid/Google Calendar are configured for non-PHI events only.'),
];

const sec9 = [
  h1('9. Documentation & Retention (§164.316, §164.530(j)(2))'),
  bullet('Policy: this document + Terraform code as source of truth'),
  bullet('PHI-bearing audit logs: 2557d (7 years) retention — app, Bedrock, RDS postgres, CloudTrail S3'),
  bullet('Non-PHI logs (VPC flow, CT tail): 365d'),
  bullet('Git history = full audit trail of infrastructure changes'),
];

const sec10 = [
  h1('10. Continuous Verification'),
  p('Audit script (scripts/hipaa-encryption-audit.sh): enumerates every PHI-handling resource, verifies encryption + retention; non-zero exit on failure; CI-runnable.'),
  p('Active monitoring (CloudWatch alarms → SNS → email):', { bold: true }),
  bullet('Backend HTTP 5xx (ALB target + ELB layer)'),
  bullet('ECS CPU / memory'),
  bullet('Bedrock latency p95, invocation throttling, errors'),
  bullet('Synthetics canary failures'),
  bullet('App-level AI call error rate (metric filter on /ecs/${env}-app)'),
];

const sec11 = [
  h1('11. KMS Key Inventory'),
  tbl(['Alias', 'Purpose'], [
    ['alias/vocuone-${env}-logs', 'CloudWatch Logs, CloudTrail, SNS, EBS, ECR'],
    ['alias/vocuone-${env}-rds', 'RDS storage + Perf Insights'],
    ['alias/vocuone-${env}-secrets', 'Secrets Manager (PHI)'],
    ['alias/vocuone-${env}-ecr', 'ECR image layers'],
    ['alias/vocuone-${env}-backup', 'AWS Backup vault'],
    ['alias/vocuone-bedrock-invocations', 'Bedrock invocation logs (account-wide singleton)'],
  ], [4080, 5280]),
  spacer(),
  p('All CMKs: rotation enabled, 30-day deletion window.'),
];

const sec12 = [
  h1('12. Sign-off', { pageBreakBefore: true }),
  p('The undersigned acknowledges the safeguards described, the signed AWS BAA, and the continuous-verification mechanism.'),
  spacer(),
  tbl(['Role', 'Name', 'Signature', 'Date'], [
    ['Security Officer (DevOps Lead)', '', '', ''],
    ['Privacy Officer', '', '', ''],
    ['CTO / Engineering Lead', '', '', ''],
  ], [2800, 2160, 2400, 2000]),
];

const appx = [
  h1('Appendix — References'),
  bullet('45 CFR §160, §162, §164 — HIPAA Rules'),
  bullet('NIST SP 800-66 Rev. 2 — HIPAA implementation guide'),
  bullet('AWS HIPAA Compliance — https://aws.amazon.com/compliance/hipaa-compliance/'),
  bullet('AWS HIPAA Eligible Services Reference — https://aws.amazon.com/compliance/hipaa-eligible-services-reference/'),
  bullet('HHS Guidance on HIPAA & Cloud Computing — https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html'),
];

// -- assemble -----------------------------------------------------------

const doc = new Document({
  creator: 'vocuone DevOps',
  title: 'HIPAA Compliance Attestation — vocuone',
  styles: {
    default: { document: { run: { font: BODY_FONT, size: 22 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: BODY_FONT, size: 36, bold: true, color: ACCENT },
        paragraph: { spacing: { before: 360, after: 180 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: BODY_FONT, size: 28, bold: true, color: ACCENT },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 } },
    ],
  },
  numbering: {
    config: [{
      reference: 'bullets',
      levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 540, hanging: 360 } } } }],
    }],
  },
  sections: [{
    properties: {
      page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } },
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          tabStops: [{ type: TabStopType.CENTER, position: 4680 }, { type: TabStopType.RIGHT, position: 9360 }],
          children: [
            new TextRun({ text: 'vocuone — HIPAA Compliance Attestation — Confidential', font: BODY_FONT, size: 16, color: '808080' }),
            new TextRun({ text: '\t', font: BODY_FONT, size: 16 }),
            new TextRun({ text: 'Page ', font: BODY_FONT, size: 16, color: '808080' }),
            new TextRun({ children: [PageNumber.CURRENT], font: BODY_FONT, size: 16, color: '808080' }),
            new TextRun({ text: ' of ', font: BODY_FONT, size: 16, color: '808080' }),
            new TextRun({ children: [PageNumber.TOTAL_PAGES], font: BODY_FONT, size: 16, color: '808080' }),
            new TextRun({ text: '\t', font: BODY_FONT, size: 16 }),
            new TextRun({ text: 'v1.0 — 2026-05-19', font: BODY_FONT, size: 16, color: '808080' }),
          ],
        })],
      }),
    },
    children: [
      ...titlePage, ...toc, ...sec1, ...sec2, ...sec3, ...sec4, ...sec5,
      ...sec6, ...sec7, ...sec8, ...sec9, ...sec10, ...sec11, ...sec12, ...appx,
    ],
  }],
});

Packer.toBuffer(doc).then(buffer => {
  const outPath = path.join(__dirname, 'HIPAA-COMPLIANCE.docx');
  fs.writeFileSync(outPath, buffer);
  console.log(`Wrote ${outPath} (${(buffer.length / 1024).toFixed(1)} KB)`);
}).catch(err => { console.error(err); process.exit(1); });
