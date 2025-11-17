#!/usr/bin/env bash
set -euo pipefail
#
# SSM Session Manager Logging Setup Script
# This script configures SSM Session Manager with comprehensive logging
#
# Features:
# 1. S3 bucket for session logs storage
# 2. CloudWatch Logs for real-time monitoring
# 3. Session preferences with command logging
# 4. IAM policies for instances
#
# Usage:
#   ./setup-ssm-logging.sh [REGION] [S3_BUCKET_NAME] [CLOUDWATCH_LOG_GROUP]
#
# Examples:
#   # Use defaults (generic naming with account ID)
#   ./setup-ssm-logging.sh ap-southeast-1
#
#   # Custom names for production "onetime" environment
#   ./setup-ssm-logging.sh ap-southeast-1 ssm-onetime-logs-vortech-dev /aws/ssm/onetime-sessions-dev
#
#   # Custom names for staging environment
#   ./setup-ssm-logging.sh ap-southeast-1 ssm-logs-vortech-staging /aws/ssm/sessions-staging
#

REGION="${1:-ap-southeast-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Allow custom bucket name or use generic default
S3_BUCKET_NAME="${2:-ssm-session-logs-${ACCOUNT_ID}-${REGION}}"

# Allow custom log group or use generic default
CLOUDWATCH_LOG_GROUP="${3:-/aws/ssm/sessions}"

echo "🔧 SSM Session Manager Logging Setup"
echo "=============================================="
echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo "S3 Bucket: $S3_BUCKET_NAME"
echo "CloudWatch Log Group: $CLOUDWATCH_LOG_GROUP"
echo "=============================================="
echo ""

# 1. Create S3 bucket for session logs
echo "📦 Creating S3 bucket for session logs..."
if aws s3 ls "s3://$S3_BUCKET_NAME" 2>/dev/null; then
    echo "✅ Bucket already exists: $S3_BUCKET_NAME"
else
    if [ "$REGION" == "us-east-1" ]; then
        aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled

    # Block public access
    aws s3api put-public-access-block --bucket "$S3_BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    # Enable encryption
    aws s3api put-bucket-encryption --bucket "$S3_BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'

    echo "✅ Created S3 bucket: $S3_BUCKET_NAME"
fi
echo ""

# 2. Create CloudWatch Log Group
echo "📊 Creating CloudWatch Log Group..."
if aws logs describe-log-groups --log-group-name-prefix "$CLOUDWATCH_LOG_GROUP" \
    --region "$REGION" --query 'logGroups[0]' --output text | grep -q "$CLOUDWATCH_LOG_GROUP"; then
    echo "✅ Log group already exists: $CLOUDWATCH_LOG_GROUP"
else
    aws logs create-log-group --log-group-name "$CLOUDWATCH_LOG_GROUP" --region "$REGION"

    # Set retention to 90 days
    aws logs put-retention-policy --log-group-name "$CLOUDWATCH_LOG_GROUP" \
        --retention-in-days 90 --region "$REGION"

    echo "✅ Created CloudWatch Log Group: $CLOUDWATCH_LOG_GROUP"
fi
echo ""

# 3. Configure SSM Session Manager Preferences
echo "⚙️  Configuring SSM Session Manager preferences..."
cat > /tmp/ssm-preferences.json <<EOF
{
  "schemaVersion": "1.0",
  "description": "Session Manager preferences with comprehensive logging",
  "sessionType": "Standard_Stream",
  "inputs": {
    "s3BucketName": "$S3_BUCKET_NAME",
    "s3KeyPrefix": "session-logs/",
    "s3EncryptionEnabled": true,
    "cloudWatchLogGroupName": "$CLOUDWATCH_LOG_GROUP",
    "cloudWatchEncryptionEnabled": false,
    "cloudWatchStreamingEnabled": true,
    "kmsKeyId": "",
    "runAsEnabled": false,
    "runAsDefaultUser": "",
    "idleSessionTimeout": "20",
    "maxSessionDuration": "240",
    "shellProfile": {
      "windows": "",
      "linux": "exec /usr/local/bin/ssm-session-wrapper.sh"
    }
  }
}
EOF

aws ssm update-document --name "SSM-SessionManagerRunShell" \
    --content "file:///tmp/ssm-preferences.json" \
    --document-version '$LATEST' \
    --region "$REGION" 2>/dev/null || \
aws ssm create-document --name "SSM-SessionManagerRunShell" \
    --content "file:///tmp/ssm-preferences.json" \
    --document-type "Session" \
    --region "$REGION"

echo "✅ SSM Session Manager preferences configured"
echo ""

# 4. Create/Update IAM policy for EC2 instances
echo "🔐 Creating IAM policy for EC2 instance role..."
POLICY_NAME="SSM-SessionManager-Logging-Policy"
cat > /tmp/instance-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SSMSessionLogsS3Upload",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/session-logs/*"
    },
    {
      "Sid": "SSMSessionLogsS3Encryption",
      "Effect": "Allow",
      "Action": [
        "s3:GetEncryptionConfiguration"
      ],
      "Resource": "arn:aws:s3:::$S3_BUCKET_NAME"
    },
    {
      "Sid": "SSMSessionLogsCloudWatch",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$CLOUDWATCH_LOG_GROUP",
        "arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$CLOUDWATCH_LOG_GROUP:*"
      ]
    },
    {
      "Sid": "SSMCore",
      "Effect": "Allow",
      "Action": [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Metadata",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Check if policy exists
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
    # Update existing policy
    CURRENT_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" --query 'Policy.DefaultVersionId' --output text)
    aws iam create-policy-version --policy-arn "$POLICY_ARN" \
        --policy-document file:///tmp/instance-policy.json \
        --set-as-default

    # Delete old version if there are too many
    VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?!IsDefaultVersion].VersionId' --output text)
    for VERSION in $VERSIONS; do
        if [ "$VERSION" != "$CURRENT_VERSION" ]; then
            aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION" 2>/dev/null || true
        fi
    done

    echo "✅ Updated IAM policy: $POLICY_NAME"
else
    # Create new policy
    aws iam create-policy --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/instance-policy.json \
        --description "Allows EC2 instances to log SSM sessions to S3 and CloudWatch"

    echo "✅ Created IAM policy: $POLICY_NAME"
fi
echo ""

echo "=============================================="
echo "✅ SSM Session Manager Logging Setup Complete!"
echo "=============================================="
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Attach the IAM policy to your EC2 instance role:"
echo "   aws iam attach-role-policy --role-name <YOUR_INSTANCE_ROLE> \\"
echo "     --policy-arn $POLICY_ARN"
echo ""
echo "2. Deploy the session wrapper script to your EC2 instances:"
echo "   - Copy ssm-session-wrapper.sh to /usr/local/bin/ on each instance"
echo "   - Make it executable: sudo chmod +x /usr/local/bin/ssm-session-wrapper.sh"
echo ""
echo "3. Test the configuration:"
echo "   aws ssm start-session --target <instance-id> \\"
echo "     --document-name SSM-SessionManagerRunShell"
echo ""
echo "4. View logs:"
echo "   - S3: s3://$S3_BUCKET_NAME/session-logs/"
echo "   - CloudWatch: $CLOUDWATCH_LOG_GROUP"
echo "   - Instance local: /var/log/ssm-sessions/"
echo ""
echo "=============================================="

# Cleanup
rm -f /tmp/ssm-preferences.json /tmp/instance-policy.json
