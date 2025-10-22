variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "asg-scale-zero-demo"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

variable "one_nat_gateway_per_az" {
  description = "Should be true if you want one NAT Gateway per availability zone. Otherwise, one NAT Gateway will be used for all AZs."
  type        = bool
  default     = false
}

# =============================================================================
# AUTO SCALING VARIABLES
# =============================================================================

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Group"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for Auto Scaling"
  type        = number
  default     = 50.0
}

variable "scale_to_zero_cron" {
  description = "Cron expression for scaling to zero (Friday 6 PM Sydney time)"
  type        = string
  default     = "0 7 * * FRI" # 7 AM UTC = 6 PM Sydney (AEST/AEDT)
}

variable "restore_capacity_cron" {
  description = "Cron expression for restoring capacity (Monday 6 AM Sydney time)"
  type        = string
  default     = "0 19 * * MON" # 7 PM UTC Sunday = 6 AM Monday Sydney (AEST/AEDT)
}
