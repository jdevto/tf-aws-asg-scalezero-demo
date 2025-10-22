# AWS Auto Scaling Scale-to-Zero Demo

A comprehensive Terraform demonstration of AWS Auto Scaling with scheduled scaling to zero capacity on weekends. This demo showcases both target tracking scaling based on CPU utilization and scheduled actions for cost optimization.

## 🏗️ Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                        Internet Gateway                         │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────┐
│                    Application Load Balancer                   │
│                    (Internet-facing)                            │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────┐
│                    Target Group                                 │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────┐
│                Auto Scaling Group                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   EC2       │  │   EC2       │  │   EC2       │            │
│  │ Instance    │  │ Instance    │  │ Instance    │            │
│  │ (nginx)     │  │ (nginx)     │  │ (nginx)     │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Features

- **Target Tracking Scaling**: Automatically scales based on CPU utilization (50% target)
- **Scheduled Scaling**: Scales to zero on weekends (Friday 6 PM - Monday 6 AM Sydney time)
- **Load Balancing**: Application Load Balancer distributes traffic across instances
- **Health Checks**: Automatic replacement of unhealthy instances
- **Cost Optimization**: Zero cost during weekends
- **Dynamic Web Content**: Real-time instance metadata and scaling information
- **Load Testing**: Comprehensive load testing script with CPU-intensive endpoint
- **CPU Load Generation**: Built-in `/cgi-bin/cpu-load` endpoint for realistic scaling tests
- **Security**: IMDSv2 enforced for secure metadata access
- **Error Handling**: Robust error handling with fallback mechanisms
- **IP Restriction**: ALB access restricted to your current public IP address
- **Least Privilege IAM**: Custom IAM policies with minimal required permissions
- **Dynamic Region Detection**: Automatically uses the configured AWS provider region
- **Configurable AZ Selection**: Uses specified availability zones (defaults to ap-southeast-2a, ap-southeast-2b)
- **Managed CloudWatch Logs**: All log groups created and managed by Terraform
- **ALB Access Logging**: S3-based access logging with lifecycle management

## 📋 Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Bash shell (for load testing script)
- Optional: Apache Bench (`ab`) for advanced load testing

## 🛠️ Deployment

### 1. Clone and Initialize

```bash
git clone <repository-url>
cd tf-aws-asg-scalezero-demo
```

### 2. Configure AWS Provider

Ensure your AWS credentials are configured:

```bash
aws configure
# or
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="your-preferred-region"
```

**Note**: The infrastructure will automatically use the region configured in your AWS provider. Availability zones default to ap-southeast-2a and ap-southeast-2b, but can be customized via the `availability_zones` variable.

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

**Note**: The ALB security group is automatically configured to only allow access from your current public IP address. This is retrieved dynamically during deployment.

### 4. Access the Application

After deployment, you'll get the ALB DNS name in the output. Access your application at:

```bash
# Get the application URL from Terraform output
terraform output application_url

# Or get just the ALB DNS name
terraform output alb_dns_name
```

## ⚡ Quick Start - See Scaling in Action

**Want to see scaling immediately?** Here's the fastest way:

```bash
# 1. Deploy the infrastructure
terraform apply

# 2. Lower CPU target to see scaling with minimal load
terraform apply -var="cpu_target_value=10"

# 3. Generate CPU load using the built-in endpoint
for i in {1..10}; do
  curl http://$(terraform output -raw alb_dns_name)/cgi-bin/cpu-load &
done

# 4. Watch scaling in AWS Console
terraform output load_test_instructions
```

**Why this works**: Static HTML doesn't generate CPU load, but the `/cgi-bin/cpu-load` endpoint does!

## 🧪 Testing Auto Scaling

### Load Testing Script

The included `load-test.sh` script provides comprehensive load testing capabilities. Use Terraform output variables to get the ALB DNS name automatically:

```bash
# Basic usage with Terraform output
./load-test.sh -d $(terraform output -raw alb_dns_name)

# Advanced testing with more concurrent users
./load-test.sh -d $(terraform output -raw alb_dns_name) -c 20 -t 600

# Gradual ramp-up test
./load-test.sh -d $(terraform output -raw alb_dns_name) -u 120

# With explicit ASG name for better monitoring
./load-test.sh -d $(terraform output -raw alb_dns_name) -a $(terraform output -raw asg_name)

# Alternative: Use the application URL output
./load-test.sh -d $(terraform output -raw application_url | sed 's|http://||')
```

**Pro tip**: You can also use the built-in load test instructions from Terraform output:

```bash
# Display comprehensive load testing instructions
terraform output load_test_instructions
```

### Manual Testing

You can also test manually by:

1. **CPU Load Test**: SSH into an instance and run:

   ```bash
   # Generate CPU load
   yes > /dev/null &
   ```

2. **HTTP Load Test**: Use curl or Apache Bench:

   ```bash
   # Simple load test using Terraform output
   ALB_DNS=$(terraform output -raw alb_dns_name)
   for i in {1..100}; do curl -s http://$ALB_DNS > /dev/null & done

   # Apache Bench (if installed)
   ab -n 1000 -c 10 http://$(terraform output -raw alb_dns_name)/
   ```

3. **CPU-Intensive Load Test**: Generate actual CPU load to trigger scaling:

   ```bash
   # Test the CPU-intensive endpoint (after instance refresh)
   curl http://$(terraform output -raw alb_dns_name)/cgi-bin/cpu-load

   # Generate sustained CPU load
   for i in {1..20}; do
     curl http://$(terraform output -raw alb_dns_name)/cgi-bin/cpu-load &
   done
   ```

## 📊 Monitoring

### AWS Console Monitoring

1. **Auto Scaling Groups**: Monitor instance count and scaling activities
2. **EC2 Instances**: View instance health and metrics
3. **CloudWatch**: CPU utilization, request count, and custom metrics
4. **Application Load Balancer**: Target health and request distribution

**Quick Access**: Use Terraform outputs to get direct links to AWS Console:

```bash
# Get monitoring URLs from Terraform output
terraform output load_test_instructions
```

### Key Metrics to Watch

- `ASGAverageCPUUtilization`: Target tracking metric
- `RequestCount`: ALB request metrics
- `TargetResponseTime`: Application performance
- `HealthyHostCount`: Target group health

## ⏰ Scheduled Scaling

The demo includes two scheduled actions:

1. **Scale to Zero**: Friday 6 PM Sydney time (`0 7 * * FRI` UTC)
2. **Restore Capacity**: Monday 6 AM Sydney time (`0 19 * * MON` UTC)

### Customizing Schedule

Modify the cron expressions in `variables.tf`:

```hcl
variable "scale_to_zero_cron" {
  description = "Cron expression for scaling to zero"
  type        = string
  default     = "0 7 * * FRI"  # Friday 6 PM Sydney time
}

variable "restore_capacity_cron" {
  description = "Cron expression for restoring capacity"
  type        = string
  default     = "0 19 * * MON"  # Monday 6 AM Sydney time
}
```

## 🔧 Configuration Options

### Auto Scaling Parameters

```hcl
variable "asg_min_size" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of instances"
  type        = number
  default     = 2
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage"
  type        = number
  default     = 50.0
}
```

### Instance Configuration

```hcl
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
```

## 💰 Cost Considerations

### Cost Breakdown (approximate, varies by region)

- **t3.micro instances**: ~$8-10/month each (varies by region)
- **Application Load Balancer**: ~$16-20/month (varies by region)
- **NAT Gateway**: ~$45-50/month (varies by region, if using one per AZ)
- **Data transfer**: Variable based on usage and region

### Cost Optimization

- **Weekend scaling**: Saves ~60% of EC2 costs
- **Single NAT Gateway**: Use `one_nat_gateway_per_az = false` to reduce NAT costs
- **Spot Instances**: Consider using Spot instances for non-critical workloads
- **Region Selection**: Choose regions with lower costs for your use case

## 🧹 Cleanup

To avoid ongoing charges, destroy the infrastructure:

```bash
terraform destroy
```

**Note**: This will delete all resources. Make sure to backup any important data first.

## 🔒 Security Features

### IAM Least Privilege Implementation

This demo implements the principle of least privilege with custom IAM policies:

#### **SSM Session Manager Policy**

- **SSMMessagesChannelAccess**: `ssmmessages:CreateControlChannel`, `ssmmessages:CreateDataChannel`, `ssmmessages:OpenControlChannel`, `ssmmessages:OpenDataChannel`
- **SSMInstanceInformationWrite**: `ssm:UpdateInstanceInformation` (tagged resources only)
- **SSMCommandExecution**: `ssm:SendCommand` (tagged resources only)

#### **CloudWatch Metrics Policy**

- **CloudWatchMetricsWrite**: `cloudwatch:PutMetricData` (AWS/EC2 namespace only)
- **CloudWatchLogsGroupCreate**: `logs:CreateLogGroup` (project-specific)
- **CloudWatchLogsStreamWrite**: `logs:CreateLogStream`, `logs:PutLogEvents` (project-specific)
- **CloudWatchLogsStreamRead**: `logs:DescribeLogStreams` (project-specific)

#### **Auto Scaling Group Read Policy**

- **AutoScalingInstancesRead**: `autoscaling:DescribeAutoScalingInstances` (tagged resources only)

#### **EC2 Metadata Access Policy**

- **EC2InstancesRead**: `ec2:DescribeInstances` (tagged resources only)
- **EC2InstanceAttributesRead**: `ec2:DescribeInstanceAttribute` (tagged resources only)

### Security Benefits

- ✅ **No Broad Policies**: Replaced AWS managed policies with specific custom policies
- ✅ **Resource Tagging**: All policies use resource tags for additional security
- ✅ **Namespace Restrictions**: CloudWatch metrics restricted to AWS/EC2 namespace
- ✅ **Log Group Isolation**: CloudWatch logs isolated to project-specific log groups
- ✅ **Conditional Access**: All policies include conditions for additional security layers
- ✅ **Statement IDs**: Each permission statement has a unique SID for easy auditing
- ✅ **Read/Write Separation**: Permissions are separated by read and write operations
- ✅ **Granular Control**: Each specific action is isolated in its own statement

## 🔍 Troubleshooting

### Common Issues

1. **Instances not scaling**:
   - **Static content doesn't generate CPU load**: nginx serving HTML uses minimal CPU (2-4%)
   - **Solution**: Use the CPU-intensive endpoint `/cgi-bin/cpu-load` or lower CPU target temporarily
   - **Check**: CloudWatch metrics show actual CPU utilization

2. **Health check failures**: Verify security groups and application health

3. **Scheduled actions not working**: Check cron expressions and timezone

4. **Load balancer not responding**: Verify ALB security group rules

5. **Scaling policy not triggering**:
   - **Target tracking scaling** requires sustained CPU above target (default 50%)
   - **Quick test**: `terraform apply -var="cpu_target_value=10"` to see scaling in action
   - **Monitor**: Use `terraform output load_test_instructions` for direct AWS Console links

### Debugging Commands

Use Terraform outputs to get resource information for debugging:

```bash
# Get all outputs for debugging
terraform output

# Get specific resource information
ASG_NAME=$(terraform output -raw asg_name)
TARGET_GROUP_ARN=$(terraform output -raw target_group_arn)
REGION=$(terraform output -raw aws_region)

# Check ASG status
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --region $REGION

# Check instance health
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN --region $REGION

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region $REGION
```

## 📚 Learning Objectives

This demo demonstrates:

1. **Auto Scaling Concepts**: Target tracking vs. scheduled scaling
2. **Load Balancing**: Application Load Balancer configuration
3. **Health Checks**: Instance and application health monitoring
4. **Cost Optimization**: Scheduled scaling for non-production environments
5. **Infrastructure as Code**: Terraform best practices
6. **Monitoring**: CloudWatch metrics and AWS Console monitoring

## 🤝 Contributing

Feel free to submit issues, feature requests, or pull requests to improve this demo.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔗 Related Resources

- [AWS Auto Scaling Documentation](https://docs.aws.amazon.com/autoscaling/)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [CloudWatch Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
