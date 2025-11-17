#!/bin/bash
# install-ssm-all.sh

REGION="ap-southeast-1"
IAM_ROLE="SSM-Enhanced-Instance-Dev-Role"

echo "Installing SSM Agent on all instances..."
echo ""

while IFS=$'\t' read -r INSTANCE_ID INSTANCE_NAME; do
  echo "=========================================="
  echo "Processing: $INSTANCE_NAME ($INSTANCE_ID)"
  echo "=========================================="
  
  # Step 1: Attach IAM role
  echo "1. Attaching IAM role..."
  aws ec2 associate-iam-instance-profile \
    --instance-id "$INSTANCE_ID" \
    --iam-instance-profile Name="$IAM_ROLE" \
    --region "$REGION" 2>/dev/null && echo "   ✅ IAM role attached" || echo "   ⚠️  IAM role already attached or failed"
  
  # Step 2: Install/start SSM Agent (for Amazon Linux - pre-installed)
  echo "2. Ensuring SSM Agent is running..."
  COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl start amazon-ssm-agent","sudo systemctl enable amazon-ssm-agent","sudo systemctl status amazon-ssm-agent"]' \
    --region "$REGION" \
    --query 'Command.CommandId' \
    --output text 2>/dev/null)
  
  if [ -n "$COMMAND_ID" ]; then
    echo "   ✅ SSM Agent start command sent (Command ID: $COMMAND_ID)"
  else
    echo "   ⚠️  Instance not yet registered in SSM (will register in 5-10 min)"
  fi
  
  # Step 3: Deploy wrapper script (if instance is SSM-ready)
  echo "3. Deploying session wrapper..."
  sleep 5  # Wait a bit for SSM to register
  
  if aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
      --region "$REGION" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null | grep -q "Online"; then
    
    cd /Users/vinson/Documents/0_Other_Services/SSM/logging
    ./deploy-wrapper-to-instances.sh "$INSTANCE_ID"
    echo "   ✅ Wrapper deployed"
  else
    echo "   ⚠️  Instance not online in SSM yet - skip wrapper (deploy manually later)"
  fi
  
  echo ""
done < instances.txt

echo "=========================================="
echo "✅ Installation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Wait 5-10 minutes for instances to register with SSM"
echo "2. Verify with: aws ssm describe-instance-information --region $REGION"
echo "3. Deploy wrapper to any instances that were skipped"