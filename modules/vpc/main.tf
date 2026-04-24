################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-${var.env}-vpc"
  }
}

################################################################################
# Public Subnets
################################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-${var.env}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

################################################################################
# Private Subnets
################################################################################

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project}-${var.env}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-${var.env}-igw"
  }
}

################################################################################
# NAT Gateway (single for stage, one per AZ for prod)
################################################################################

resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"

  tags = {
    Name = "${var.project}-${var.env}-nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project}-${var.env}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Route Tables
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project}-${var.env}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count = length(aws_subnet.private)

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[min(count.index, var.nat_gateway_count - 1)].id
  }

  tags = {
    Name = "${var.project}-${var.env}-private-rt-${count.index}"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

################################################################################
# VPC Flow Logs (HIPAA requirement)
################################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.project}-${var.env}-flow-logs"
  retention_in_days = 365
  kms_key_id        = var.flow_logs_kms_key_arn

  tags = {
    Name = "${var.project}-${var.env}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project}-${var.env}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project}-${var.env}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = {
    Name = "${var.project}-${var.env}-vpc-flow-log"
  }
}

################################################################################
# VPC Endpoints — PHI services stay off public internet
################################################################################

resource "aws_security_group" "endpoints" {
  count = var.enable_bedrock_endpoints ? 1 : 0

  name        = "${var.project}-${var.env}-vpc-endpoints-sg"
  description = "Allow HTTPS from within VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-vpc-endpoints-sg"
  }
}

# S3 — Gateway endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_bedrock_endpoints ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(
    aws_route_table.public[*].id,
    aws_route_table.private[*].id,
  )

  tags = { Name = "${var.project}-${var.env}-s3-endpoint" }
}

# Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_bedrock_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-${var.env}-secretsmanager-endpoint" }
}

# Transcribe (medical audio — PHI)
resource "aws_vpc_endpoint" "transcribe" {
  count = var.enable_bedrock_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.transcribe"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-${var.env}-transcribe-endpoint" }
}

resource "aws_vpc_endpoint" "transcribestreaming" {
  count = var.enable_bedrock_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.transcribestreaming"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-${var.env}-transcribestreaming-endpoint" }
}

# Bedrock
resource "aws_vpc_endpoint" "bedrock_runtime" {
  count = var.enable_bedrock_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-${var.env}-bedrock-runtime-endpoint" }
}

resource "aws_vpc_endpoint" "bedrock_agent_runtime" {
  count = var.enable_bedrock_endpoints ? 1 : 0

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agent-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-${var.env}-bedrock-agent-runtime-endpoint" }
}
