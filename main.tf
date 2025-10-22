# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current public IP
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com/"
}

# Get current AWS region from provider
data "aws_region" "current" {}

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get ELB service account for current region
data "aws_elb_service_account" "main" {}

# =============================================================================
# VPC AND NETWORKING
# =============================================================================

# VPC
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Elastic IPs for NAT Gateway
resource "aws_eip" "nat" {
  count = var.one_nat_gateway_per_az ? length(var.availability_zones) : 1

  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = merge(local.tags, {
    Name = var.one_nat_gateway_per_az ? "${var.project_name}-nat-eip-${count.index + 1}" : "${var.project_name}-nat-eip"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "this" {
  count = var.one_nat_gateway_per_az ? length(var.availability_zones) : 1

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = var.one_nat_gateway_per_az ? aws_subnet.public[count.index].id : aws_subnet.public[0].id

  tags = merge(local.tags, {
    Name = var.one_nat_gateway_per_az ? "${var.project_name}-nat-gateway-${count.index + 1}" : "${var.project_name}-nat-gateway"
  })

  depends_on = [aws_internet_gateway.this]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.one_nat_gateway_per_az ? aws_nat_gateway.this[count.index].id : aws_nat_gateway.this[0].id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-rt-${count.index + 1}"
  })
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Security Group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from my IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  ingress {
    description = "HTTPS from my IP"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-alb-sg"
  })
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-ec2-"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-sg"
  })
}

# =============================================================================
# IAM ROLE AND INSTANCE PROFILE
# =============================================================================

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_instance_role" {
  name = "${var.project_name}-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-instance-role"
  })
}

# Custom policy for SSM Session Manager
resource "aws_iam_policy" "ssm_session_manager" {
  name        = "${var.project_name}-ssm-session-manager"
  description = "Minimal permissions for SSM Session Manager access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMMessagesChannelAccess"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMInstanceInformationWrite"
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ssm:ResourceTag/Project" = var.project_name
          }
        }
      },
      {
        Sid    = "SSMCommandExecution"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ssm:ResourceTag/Project" = var.project_name
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-ssm-session-manager-policy"
  })
}

# Custom policy for CloudWatch metrics
resource "aws_iam_policy" "cloudwatch_metrics" {
  name        = "${var.project_name}-cloudwatch-metrics"
  description = "Minimal permissions for CloudWatch metrics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetricsWrite"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "AWS/EC2"
          }
        }
      },
      {
        Sid    = "CloudWatchLogsStreamWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ec2_instances.arn}:*"
      },
      {
        Sid    = "CloudWatchLogsStreamRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.ec2_instances.arn}:*"
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-cloudwatch-metrics-policy"
  })
}

# Custom policy for Auto Scaling Group information
resource "aws_iam_policy" "asg_read_only" {
  name        = "${var.project_name}-asg-read-only"
  description = "Minimal permissions to read Auto Scaling Group information"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AutoScalingInstancesRead"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/Project" = var.project_name
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-asg-read-only-policy"
  })
}

# Custom policy for EC2 instance metadata access
resource "aws_iam_policy" "ec2_metadata_access" {
  name        = "${var.project_name}-ec2-metadata-access"
  description = "Minimal permissions for EC2 instance metadata access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2InstancesRead"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project_name
          }
        }
      },
      {
        Sid    = "EC2InstanceAttributesRead"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstanceAttribute"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project_name
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-metadata-access-policy"
  })
}

# Attach custom policies to the role
resource "aws_iam_role_policy_attachment" "ssm_session_manager" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ssm_session_manager.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_metrics" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.cloudwatch_metrics.arn
}

resource "aws_iam_role_policy_attachment" "asg_read_only" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.asg_read_only.arn
}

resource "aws_iam_role_policy_attachment" "ec2_metadata_access" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = aws_iam_policy.ec2_metadata_access.arn
}

# Instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-instance-profile"
  })
}

# =============================================================================
# CLOUDWATCH LOG GROUPS
# =============================================================================

# CloudWatch Log Group for EC2 instances
resource "aws_cloudwatch_log_group" "ec2_instances" {
  name              = "/aws/ec2/${var.project_name}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-logs"
  })
}

# CloudWatch Log Group for Application Load Balancer
resource "aws_cloudwatch_log_group" "alb_access_logs" {
  name              = "/aws/applicationloadbalancer/${var.project_name}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-alb-logs"
  })
}

# S3 Bucket for ALB Access Logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.project_name}-alb-logs-${data.aws_caller_identity.current.account_id}"

  force_destroy = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-alb-logs-bucket"
  })
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "delete_old_logs"
    status = "Enabled"

    expiration {
      days = 1
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy for ALB Access Logs
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl"
        ]
        Resource = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}

# =============================================================================
# APPLICATION LOAD BALANCER
# =============================================================================

# Application Load Balancer
resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-alb"
  })

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

# Target Group
resource "aws_lb_target_group" "this" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-target-group"
  })
}

# ALB Listener
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-alb-listener"
  })
}

# =============================================================================
# LAUNCH TEMPLATE
# =============================================================================

# Data source for latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Launch Template
resource "aws_launch_template" "this" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(file("${path.module}/user-data.sh"))

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.tags, {
      Name = "${var.project_name}-instance"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# AUTO SCALING GROUP
# =============================================================================

# Auto Scaling Group
resource "aws_autoscaling_group" "this" {
  name                      = "${var.project_name}-asg"
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns         = [aws_lb_target_group.this.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# SCALING POLICIES
# =============================================================================

# Target Tracking Policy for CPU-based scaling
resource "aws_autoscaling_policy" "target_tracking" {
  name                   = "${var.project_name}-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = var.cpu_target_value
    disable_scale_in = false
  }
}

# Scheduled Action - Scale to Zero on Friday 6 PM (Sydney time)
resource "aws_autoscaling_schedule" "scale_to_zero" {
  scheduled_action_name  = "${var.project_name}-scale-to-zero"
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
  recurrence             = var.scale_to_zero_cron
  autoscaling_group_name = aws_autoscaling_group.this.name
}

# Scheduled Action - Restore Capacity on Monday 6 AM (Sydney time)
resource "aws_autoscaling_schedule" "restore_capacity" {
  scheduled_action_name  = "${var.project_name}-restore-capacity"
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
  desired_capacity       = var.asg_desired_capacity
  recurrence             = var.restore_capacity_cron
  autoscaling_group_name = aws_autoscaling_group.this.name
}
