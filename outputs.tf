output "cloudwatch_log_groups" {
  description = "CloudWatch log groups created and managed by Terraform"
  value = {
    ec2_instances   = aws_cloudwatch_log_group.ec2_instances.arn
    alb_access_logs = aws_cloudwatch_log_group.alb_access_logs.arn
  }
}

output "s3_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.arn
}

output "iam_policies" {
  description = "IAM policies created for least privilege access"
  value = {
    ssm_session_manager = aws_iam_policy.ssm_session_manager.arn
    cloudwatch_metrics  = aws_iam_policy.cloudwatch_metrics.arn
    asg_read_only       = aws_iam_policy.asg_read_only.arn
    ec2_metadata_access = aws_iam_policy.ec2_metadata_access.arn
  }
}

output "aws_region" {
  description = "Current AWS region"
  value       = data.aws_region.current.region
}

output "aws_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "my_public_ip" {
  description = "Your current public IP address"
  value       = chomp(data.http.my_public_ip.response_body)
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# =============================================================================
# AUTO SCALING OUTPUTS
# =============================================================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.this.zone_id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.this.arn
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.this.arn
}

output "application_url" {
  description = "URL to access the application"
  value       = "http://${aws_lb.this.dns_name}"
}

output "load_test_instructions" {
  description = "Instructions for running the load test"
  value       = <<-EOT
    To run the load test:

    1. Make sure the load-test.sh script is executable:
       chmod +x load-test.sh

    2. Run the load test with the ALB DNS name:
       ./load-test.sh -d ${aws_lb.this.dns_name}

    3. For advanced testing with Apache Bench:
       ./load-test.sh -d ${aws_lb.this.dns_name} -c 20 -t 600

    Note: ALB access is restricted to your IP: ${chomp(data.http.my_public_ip.response_body)}

    Monitor the Auto Scaling Group in AWS Console:
    https://console.aws.amazon.com/ec2autoscaling/home?region=${data.aws_region.current.region}#/details

    Monitor CloudWatch metrics:
    https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.region}#metricsV2:
  EOT
}

output "scheduled_scaling_info" {
  description = "Information about scheduled scaling"
  value       = <<-EOT
    Scheduled Scaling Configuration:

    Scale to Zero: ${var.scale_to_zero_cron} (Friday 6 PM Sydney time)
    Restore Capacity: ${var.restore_capacity_cron} (Monday 6 AM Sydney time)

    Target CPU Utilization: ${var.cpu_target_value}%

    Current ASG Settings:
    - Min Size: ${var.asg_min_size}
    - Max Size: ${var.asg_max_size}
    - Desired Capacity: ${var.asg_desired_capacity}
  EOT
}
