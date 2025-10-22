#!/bin/bash

# AWS Auto Scaling Load Test Script
# This script generates HTTP load to demonstrate Auto Scaling behavior

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ALB_DNS=""
REGION="ap-southeast-2"
CONCURRENT_USERS=10
DURATION=300
RAMP_UP_TIME=60
ASG_NAME=""

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --dns ALB_DNS        Application Load Balancer DNS name (required)"
    echo "  -r, --region REGION      AWS region (default: ap-southeast-2)"
    echo "  -c, --concurrent USERS    Number of concurrent users (default: 10)"
    echo "  -t, --duration SECONDS   Test duration in seconds (default: 300)"
    echo "  -u, --ramp-up SECONDS    Ramp-up time in seconds (default: 60)"
    echo "  -a, --asg-name NAME      Auto Scaling Group name (auto-detected if not provided)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -d my-alb-1234567890.ap-southeast-2.elb.amazonaws.com"
    echo "  $0 -d my-alb-1234567890.ap-southeast-2.elb.amazonaws.com -c 20 -t 600"
    echo "  $0 -d my-alb-1234567890.ap-southeast-2.elb.amazonaws.com -a my-asg-name"
    echo ""
    echo "Prerequisites:"
    echo "  - curl (for basic load testing)"
    echo "  - ab (Apache Bench) - optional but recommended"
    echo "  - AWS CLI configured (for monitoring)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dns)
            ALB_DNS="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -c|--concurrent)
            CONCURRENT_USERS="$2"
            shift 2
            ;;
        -t|--duration)
            DURATION="$2"
            shift 2
            ;;
        -u|--ramp-up)
            RAMP_UP_TIME="$2"
            shift 2
            ;;
        -a|--asg-name)
            ASG_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ALB_DNS" ]]; then
    print_error "ALB DNS name is required"
    show_usage
    exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    print_error "curl is required but not installed"
    exit 1
fi

# Check if ab (Apache Bench) is available
if command -v ab &> /dev/null; then
    USE_AB=true
    print_success "Apache Bench (ab) found - will use for advanced load testing"
else
    USE_AB=false
    print_warning "Apache Bench (ab) not found - using curl for basic load testing"
fi

# Check if AWS CLI is available
if command -v aws &> /dev/null; then
    USE_AWS_CLI=true
    print_success "AWS CLI found - will monitor Auto Scaling Group"
else
    USE_AWS_CLI=false
    print_warning "AWS CLI not found - monitoring will be limited"
fi

# Function to get ASG information
get_asg_info() {
    if [[ "$USE_AWS_CLI" == true ]]; then
        # Use provided ASG name or find one with Project tag
        if [[ -z "$ASG_NAME" ]]; then
            ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" \
                --query "AutoScalingGroups[?Tags[?Key=='Project']].AutoScalingGroupName" \
                --output text | head -1)
        fi

        if [[ -n "$ASG_NAME" ]]; then
            # Get current capacity
            CURRENT_CAPACITY=$(aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names "$ASG_NAME" \
                --region "$REGION" \
                --query 'AutoScalingGroups[0].DesiredCapacity' \
                --output text)

            # Get instance count
            INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names "$ASG_NAME" \
                --region "$REGION" \
                --query 'AutoScalingGroups[0].Instances | length(@)' \
                --output text)

            echo "ASG: $ASG_NAME | Desired: $CURRENT_CAPACITY | Instances: $INSTANCE_COUNT"
        else
            echo "ASG: Not found"
        fi
    else
        echo "ASG: AWS CLI not available"
    fi
}

# Function to perform basic load test with curl
basic_load_test() {
    local url="http://$ALB_DNS"
    local start_time=$(date +%s)
    local end_time=$((start_time + DURATION))

    print_status "Starting basic load test with curl..."
    print_status "Target: $url"
    print_status "Duration: $DURATION seconds"
    print_status "Concurrent users: $CONCURRENT_USERS"

    # Create a function to run curl in background
    run_curl() {
        local count=0
        while [[ $(date +%s) -lt $end_time ]]; do
            curl -s -o /dev/null -w "%{http_code}" "$url" > /dev/null 2>&1
            count=$((count + 1))
            sleep 0.1
        done
        echo $count
    }

    # Start multiple curl processes
    pids=()
    for ((i=1; i<=CONCURRENT_USERS; i++)); do
        run_curl &
        pids+=($!)
    done

    # Monitor progress
    local elapsed=0
    while [[ $elapsed -lt $DURATION ]]; do
        sleep 10
        elapsed=$((elapsed + 10))
        local progress=$((elapsed * 100 / DURATION))
        print_status "Progress: $progress% ($elapsed/$DURATION seconds) | $(get_asg_info)"
    done

    # Wait for all processes to complete
    total_requests=0
    for pid in "${pids[@]}"; do
        wait $pid
        requests=$(jobs -p | wc -l)
        total_requests=$((total_requests + requests))
    done

    print_success "Basic load test completed"
}

# Function to perform advanced load test with Apache Bench
advanced_load_test() {
    local url="http://$ALB_DNS"

    print_status "Starting advanced load test with Apache Bench..."
    print_status "Target: $url"
    print_status "Concurrent users: $CONCURRENT_USERS"
    print_status "Total requests: $((CONCURRENT_USERS * 100))"

    # Run Apache Bench
    ab -n $((CONCURRENT_USERS * 100)) -c $CONCURRENT_USERS -g /tmp/ab_results.tsv "$url" > /tmp/ab_output.txt 2>&1

    if [[ $? -eq 0 ]]; then
        print_success "Advanced load test completed"

        # Parse results
        local requests_per_second=$(grep "Requests per second" /tmp/ab_output.txt | awk '{print $4}')
        local time_per_request=$(grep "Time per request" /tmp/ab_output.txt | head -1 | awk '{print $4}')
        local failed_requests=$(grep "Failed requests" /tmp/ab_output.txt | awk '{print $3}')

        echo ""
        print_success "Results Summary:"
        echo "  Requests per second: $requests_per_second"
        echo "  Time per request: ${time_per_request}ms"
        echo "  Failed requests: $failed_requests"

        # Clean up
        rm -f /tmp/ab_output.txt /tmp/ab_results.tsv
    else
        print_error "Apache Bench test failed"
        cat /tmp/ab_output.txt
        rm -f /tmp/ab_output.txt /tmp/ab_results.tsv
    fi
}

# Function to perform gradual ramp-up test
ramp_up_test() {
    local url="http://$ALB_DNS"
    local ramp_up_steps=5
    local step_duration=$((RAMP_UP_TIME / ramp_up_steps))
    local step_users=$((CONCURRENT_USERS / ramp_up_steps))

    print_status "Starting gradual ramp-up test..."
    print_status "Target: $url"
    print_status "Ramp-up time: $RAMP_UP_TIME seconds"
    print_status "Final concurrent users: $CONCURRENT_USERS"

    for ((step=1; step<=ramp_up_steps; step++)); do
        local current_users=$((step * step_users))
        print_status "Step $step/$ramp_up_steps: $current_users concurrent users for $step_duration seconds"

        # Start load for this step
        pids=()
        for ((i=1; i<=current_users; i++)); do
            (
                local count=0
                local step_end=$(($(date +%s) + step_duration))
                while [[ $(date +%s) -lt $step_end ]]; do
                    curl -s -o /dev/null "$url" > /dev/null 2>&1
                    count=$((count + 1))
                    sleep 0.1
                done
            ) &
            pids+=($!)
        done

        # Wait for step to complete
        sleep $step_duration

        # Kill background processes
        for pid in "${pids[@]}"; do
            kill $pid 2>/dev/null || true
        done

        print_status "Step $step completed | $(get_asg_info)"
    done

    print_success "Ramp-up test completed"
}

# Main execution
echo "=========================================="
echo "AWS Auto Scaling Load Test"
echo "=========================================="
echo ""

# Test ALB connectivity
print_status "Testing ALB connectivity..."
if curl -s -o /dev/null -w "%{http_code}" "http://$ALB_DNS" | grep -q "200"; then
    print_success "ALB is responding (HTTP 200)"
else
    print_error "ALB is not responding properly"
    exit 1
fi

echo ""
print_status "Initial ASG state: $(get_asg_info)"
echo ""

# Choose test type based on available tools
if [[ "$USE_AB" == true ]]; then
    echo "Choose test type:"
    echo "1) Basic load test (curl)"
    echo "2) Advanced load test (Apache Bench)"
    echo "3) Gradual ramp-up test (curl)"
    echo "4) All tests"
    echo ""
    read -p "Enter choice (1-4): " choice

    case $choice in
        1)
            basic_load_test
            ;;
        2)
            advanced_load_test
            ;;
        3)
            ramp_up_test
            ;;
        4)
            basic_load_test
            echo ""
            advanced_load_test
            echo ""
            ramp_up_test
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
else
    echo "Choose test type:"
    echo "1) Basic load test (curl)"
    echo "2) Gradual ramp-up test (curl)"
    echo "3) Both tests"
    echo ""
    read -p "Enter choice (1-3): " choice

    case $choice in
        1)
            basic_load_test
            ;;
        2)
            ramp_up_test
            ;;
        3)
            basic_load_test
            echo ""
            ramp_up_test
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
fi

echo ""
print_success "Load testing completed!"
echo ""
print_status "Final ASG state: $(get_asg_info)"
echo ""
print_status "Monitor your Auto Scaling Group in the AWS Console:"
print_status "https://console.aws.amazon.com/ec2autoscaling/home?region=$REGION#/details"
print_status ""
print_status "Monitor CloudWatch metrics:"
print_status "https://console.aws.amazon.com/cloudwatch/home?region=$REGION#metricsV2:"
print_status ""
print_status "Check your application at: http://$ALB_DNS"
