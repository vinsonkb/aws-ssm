#!/usr/bin/env bash
set -euo pipefail
#
# Deploy SSM Session Wrapper Script to EC2 Instances
# This script deploys the session wrapper to specified instances
#

REGION="${1:-ap-southeast-1}"
INSTANCE_IDS="${2:-}"

if [ -z "$INSTANCE_IDS" ]; then
    echo "Usage: $0 <region> <instance-id1,instance-id2,...>"
    echo ""
    echo "Example:"
    echo "  $0 ap-southeast-1 i-0123456789abcdef0,i-0fedcba9876543210"
    echo ""
    echo "Or deploy to all instances with SSM agent:"
    echo "  $0 ap-southeast-1 all"
    exit 1
fi

echo "🚀 Deploying SSM Session Wrapper Script"
echo "=============================================="
echo "Region: $REGION"
echo ""

# Get list of instances
if [ "$INSTANCE_IDS" == "all" ]; then
    echo "🔍 Finding all SSM-managed instances..."
    INSTANCES=$(aws ssm describe-instance-information \
        --region "$REGION" \
        --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId' \
        --output text | tr '\t' ',')
else
    INSTANCES="$INSTANCE_IDS"
fi

if [ -z "$INSTANCES" ]; then
    echo "❌ No instances found"
    exit 1
fi

echo "📦 Target instances: $INSTANCES"
echo ""

# Read the wrapper script and encode it
WRAPPER_SCRIPT_BASE64=$(cat ssm-session-wrapper.sh | base64)

# Run the command via SSM Run Command using base64 encoded content
echo "📤 Sending deployment command via SSM Run Command..."
COMMAND_ID=$(aws ssm send-command \
    --region "$REGION" \
    --document-name "AWS-RunShellScript" \
    --instance-ids $(echo "$INSTANCES" | tr ',' ' ') \
    --parameters commands="[
\"#!/bin/bash\",
\"set -euo pipefail\",
\"echo 'Deploying SSM session wrapper...'\",
\"mkdir -p /usr/local/bin\",
\"mkdir -p /var/log/ssm-sessions\",
\"chmod 755 /var/log/ssm-sessions\",
\"echo '$WRAPPER_SCRIPT_BASE64' | base64 -d > /usr/local/bin/ssm-session-wrapper.sh\",
\"chmod +x /usr/local/bin/ssm-session-wrapper.sh\",
\"echo 'Wrapper script deployed successfully'\",
\"ls -lh /usr/local/bin/ssm-session-wrapper.sh\"
]" \
    --comment "Deploy SSM session wrapper script" \
    --query 'Command.CommandId' \
    --output text)

echo "✅ Command sent: $COMMAND_ID"
echo ""
echo "⏳ Waiting for command to complete..."
sleep 5

# Check command status
for INSTANCE in $(echo "$INSTANCES" | tr ',' ' '); do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Instance: $INSTANCE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    STATUS=$(aws ssm get-command-invocation \
        --region "$REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE" \
        --query 'Status' \
        --output text 2>/dev/null || echo "Pending")

    echo "Status: $STATUS"

    if [ "$STATUS" == "Success" ]; then
        OUTPUT=$(aws ssm get-command-invocation \
            --region "$REGION" \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE" \
            --query 'StandardOutputContent' \
            --output text)
        echo ""
        echo "$OUTPUT"
        echo "✅ Deployment successful on $INSTANCE"
    elif [ "$STATUS" == "Failed" ]; then
        ERROR=$(aws ssm get-command-invocation \
            --region "$REGION" \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE" \
            --query 'StandardErrorContent' \
            --output text)
        echo ""
        echo "❌ Deployment failed on $INSTANCE"
        echo "Error: $ERROR"
    else
        echo "⏳ Still running... Check later with:"
        echo "   aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE"
    fi
done

echo ""
echo "=============================================="
echo "✅ Deployment Complete!"
echo "=============================================="
echo ""
echo "🔍 To check deployment status later:"
echo "   aws ssm list-command-invocations --command-id $COMMAND_ID --region $REGION"
