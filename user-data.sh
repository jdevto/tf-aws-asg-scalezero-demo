#!/bin/bash

# AWS Auto Scaling Demo - User Data Script
# This script installs nginx and creates a dynamic web page showing instance metadata
# Uses IMDSv2 for secure metadata access with fallback to IMDSv1

# Log all output to standard AWS user-data log location
exec > >(tee /var/log/user-data.log) 2>&1

# Exit on any error
set -e

echo "Starting user-data script execution at $(date)"
echo "=========================================="

# Update system
echo "Updating system packages..."
yum update -y
echo "System update completed"

# Install required packages
echo "Installing required packages (nginx, unzip)..."
yum install -y nginx unzip
echo "Required packages installed successfully"

# Install AWS CLI v2 with proper error handling
echo "Installing AWS CLI v2..."
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
if [ $? -eq 0 ]; then
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    echo "AWS CLI v2 installed successfully"
else
    echo "Failed to download AWS CLI v2, falling back to yum install"
    yum install -y awscli
fi

# Function to get IMDSv2 token
get_imds_token() {
    curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        --max-time 5 || echo ""
}

# Function to get metadata with IMDSv2
get_metadata() {
    local path="$1"
    local token="$2"
    local result=$(curl -s -H "X-aws-ec2-metadata-token: $token" \
        "http://169.254.169.254/latest/meta-data/$path" \
        --max-time 5 2>/dev/null)

    # Check if result contains HTML error page
    if echo "$result" | grep -q "<!DOCTYPE html"; then
        echo "N/A"
    else
        echo "$result"
    fi
}

# Get IMDSv2 token
echo "Getting IMDSv2 token..."
TOKEN=$(get_imds_token)

# Get instance metadata using IMDSv2
echo "Retrieving instance metadata using IMDSv2..."
INSTANCE_ID=$(get_metadata "instance-id" "$TOKEN")
AZ=$(get_metadata "placement/availability-zone" "$TOKEN")
PRIVATE_IP=$(get_metadata "local-ipv4" "$TOKEN")
PUBLIC_IP=$(get_metadata "public-ipv4" "$TOKEN")
REGION=$(get_metadata "placement/region" "$TOKEN")

echo "Retrieved metadata:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Availability Zone: $AZ"
echo "  Private IP: $PRIVATE_IP"
echo "  Public IP: $PUBLIC_IP"
echo "  Region: $REGION"

# Get Auto Scaling Group information with error handling
echo "Getting Auto Scaling Group information..."
ASG_NAME="N/A"
if command -v aws >/dev/null 2>&1 && [ "$INSTANCE_ID" != "N/A" ] && [ "$REGION" != "N/A" ]; then
    ASG_NAME=$(aws autoscaling describe-auto-scaling-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'AutoScalingInstances[0].AutoScalingGroupName' \
        --output text 2>/dev/null || echo "N/A")
fi

# Fallback to IMDSv1 if IMDSv2 fails
if [ "$INSTANCE_ID" = "N/A" ] || [ -z "$TOKEN" ]; then
    echo "IMDSv2 failed, trying IMDSv1..."
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id --max-time 5 2>/dev/null | grep -v "<!DOCTYPE html" || echo "N/A")
    AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone --max-time 5 2>/dev/null | grep -v "<!DOCTYPE html" || echo "N/A")
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 --max-time 5 2>/dev/null | grep -v "<!DOCTYPE html" || echo "N/A")
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 --max-time 5 2>/dev/null | grep -v "<!DOCTYPE html" || echo "N/A")
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region --max-time 5 2>/dev/null | grep -v "<!DOCTYPE html" || echo "N/A")
fi

# Create dynamic HTML content
echo "Creating dynamic HTML content..."
cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Auto Scaling Demo</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 50%, #1e3c72 100%);
            color: #ffffff;
            min-height: 100vh;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.15);
            padding: 30px;
            border-radius: 20px;
            backdrop-filter: blur(15px);
            box-shadow: 0 12px 40px 0 rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        h1 {
            text-align: center;
            margin-bottom: 30px;
            font-size: 2.8em;
            text-shadow: 2px 2px 8px rgba(0,0,0,0.5);
            color: #00ffff;
            font-weight: 700;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .info-card {
            background: rgba(255, 255, 255, 0.12);
            padding: 25px;
            border-radius: 15px;
            border-left: 5px solid #00d4ff;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        .info-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.3);
        }
        .info-card h3 {
            margin-top: 0;
            color: #00d4ff;
            font-size: 1.2em;
            font-weight: 600;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-healthy { background-color: #00ff88; box-shadow: 0 0 10px rgba(0, 255, 136, 0.5); }
        .status-scaling { background-color: #ffaa00; box-shadow: 0 0 10px rgba(255, 170, 0, 0.5); }
        .status-error { background-color: #ff4444; box-shadow: 0 0 10px rgba(255, 68, 68, 0.5); }
        .refresh-info {
            text-align: center;
            margin-top: 25px;
            font-style: italic;
            opacity: 0.9;
            color: #b3d9ff;
        }
        .demo-info {
            background: rgba(255, 255, 255, 0.12);
            padding: 25px;
            border-radius: 15px;
            margin-top: 25px;
            border-left: 5px solid #ff6b6b;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
        }
        .demo-info h3 {
            color: #ff6b6b;
            margin-top: 0;
            font-size: 1.2em;
            font-weight: 600;
        }
        .demo-info ul {
            margin: 10px 0;
            padding-left: 20px;
        }
        .demo-info li {
            margin: 8px 0;
            line-height: 1.5;
        }
        .demo-info li strong {
            color: #00d4ff;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 AWS Auto Scaling Demo</h1>

        <div class="info-grid">
            <div class="info-card">
                <h3>📊 Instance Information</h3>
                <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
                <p><strong>Availability Zone:</strong> $AZ</p>
                <p><strong>Private IP:</strong> $PRIVATE_IP</p>
                <p><strong>Public IP:</strong> $PUBLIC_IP</p>
                <p><strong>Region:</strong> $REGION</p>
            </div>

            <div class="info-card">
                <h3>⚖️ Auto Scaling Status</h3>
                <p><strong>Auto Scaling Group:</strong> $ASG_NAME</p>
                <p><span class="status-indicator status-healthy"></span><strong>Status:</strong> Healthy & Running</p>
                <p><strong>Current Time:</strong> <span id="current-time"></span></p>
                <p><strong>Uptime:</strong> <span id="uptime"></span></p>
            </div>
        </div>

        <div class="demo-info">
            <h3>🎯 Demo Features</h3>
            <ul>
                <li><strong>Target Tracking:</strong> Scales based on CPU utilization (50% target)</li>
                <li><strong>Scheduled Scaling:</strong> Scales to zero on weekends (Fri 6PM - Mon 6AM Sydney time)</li>
                <li><strong>Load Balancing:</strong> Traffic distributed across multiple instances</li>
                <li><strong>Health Checks:</strong> Automatic replacement of unhealthy instances</li>
                <li><strong>Cost Optimization:</strong> Zero cost during weekends</li>
            </ul>
        </div>

        <div class="refresh-info">
            <p>This page refreshes every 30 seconds to show real-time information</p>
            <p>Last updated: <span id="last-updated"></span></p>
        </div>
    </div>

    <script>
        function updateTime() {
            const now = new Date();
            document.getElementById('current-time').textContent = now.toLocaleString();
            document.getElementById('last-updated').textContent = now.toLocaleString();
        }

        function updateUptime() {
            const startTime = new Date();
            setInterval(() => {
                const now = new Date();
                const diff = now - startTime;
                const hours = Math.floor(diff / 3600000);
                const minutes = Math.floor((diff % 3600000) / 60000);
                const seconds = Math.floor((diff % 60000) / 1000);
                document.getElementById('uptime').textContent =
                    `${hours}h ${minutes}m ${seconds}s`;
            }, 1000);
        }

        // Initial update
        updateTime();
        updateUptime();

        // Update every second
        setInterval(updateTime, 1000);

        // Refresh page every 30 seconds
        setTimeout(() => {
            window.location.reload();
        }, 30000);
    </script>
</body>
</html>
EOF

echo "HTML content created successfully"

# Start and enable nginx
echo "Starting nginx..."
systemctl start nginx
systemctl enable nginx
echo "Nginx service started and enabled"

# Verify nginx is running
if systemctl is-active --quiet nginx; then
    echo "Nginx started successfully"
else
    echo "Failed to start nginx"
    exit 1
fi

# Create a simple health check endpoint
cat > /usr/share/nginx/html/health << EOF
OK
EOF

# Create a CPU-intensive CGI script for load testing
mkdir -p /usr/share/nginx/html/cgi-bin
cat > /usr/share/nginx/html/cgi-bin/cpu-load << 'EOF'
#!/bin/bash
# CPU-intensive script for load testing
echo "Content-Type: text/plain"
echo ""
echo "Starting CPU load test..."
# Generate CPU load for 10 seconds using mathematical calculations
timeout 10 bash -c 'while true; do
    for i in {1..1000}; do
        echo "scale=1000; 4*a(1)" | bc -l > /dev/null 2>&1
    done
done' || true
echo "CPU load test completed at $(date)"
EOF

chmod +x /usr/share/nginx/html/cgi-bin/cpu-load

# Configure nginx to serve CGI scripts
cat > /etc/nginx/conf.d/cgi.conf << 'EOF'
location /cgi-bin/ {
    root /usr/share/nginx/html;
    fastcgi_pass unix:/var/run/fcgiwrap.socket;
    include /etc/nginx/fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
}
EOF

# Install fcgiwrap for CGI support
yum install -y fcgiwrap
systemctl enable fcgiwrap
systemctl start fcgiwrap
systemctl reload nginx

# Set proper permissions
chmod 644 /usr/share/nginx/html/index.html
chmod 644 /usr/share/nginx/html/health

# Log the deployment
echo "$(date): Instance $INSTANCE_ID deployed successfully" >> /var/log/user-data.log
echo "$(date): Instance ID: $INSTANCE_ID, AZ: $AZ, Private IP: $PRIVATE_IP" >> /var/log/user-data.log
echo "$(date): ASG: $ASG_NAME, Region: $REGION" >> /var/log/user-data.log

# Test the health endpoint
if curl -f http://localhost/health >/dev/null 2>&1; then
    echo "Health check endpoint is working"
else
    echo "Health check endpoint failed"
fi

echo "User data script completed successfully"
echo "=========================================="
echo "Script execution finished at $(date)"
