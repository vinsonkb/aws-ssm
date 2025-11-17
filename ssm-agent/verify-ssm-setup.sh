REGION="ap-southeast-1"
INSTANCE_ID="i-0ee0bc84a481f7852"  # Change to your instance

echo "=========================================="
echo "SSM Setup Verification"
echo "=========================================="
echo ""

# 1. Check SSM Document
echo "1. Checking SSM Document configuration..."
WRAPPER_CONFIG=$(aws ssm get-document \
  --name SSM-SessionManagerRunShell \
  --region "$REGION" \
  --query 'Content' \
  --output text 2>/dev/null | jq -r '.inputs.shellProfile.linux')

if [ "$WRAPPER_CONFIG" = "exec /usr/local/bin/ssm-session-wrapper.sh" ]; then
  echo "   ✅ SSM Document configured with wrapper"
else
  echo "   ❌ SSM Document NOT configured with wrapper"
  echo "   Current: $WRAPPER_CONFIG"
fi
echo ""

# 2. Check if instance is online
echo "2. Checking instance SSM status..."
SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region "$REGION" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null)

if [ "$SSM_STATUS" = "Online" ]; then
  echo "   ✅ Instance is Online in SSM"
else
  echo "   ❌ Instance not online (Status: $SSM_STATUS)"
  exit 1
fi
echo ""

# 3. Check wrapper file on instance
echo "3. Checking wrapper script on instance..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["if [ -f /usr/local/bin/ssm-session-wrapper.sh ]; then echo INSTALLED; ls -lh /usr/local/bin/ssm-session-wrapper.sh; else echo NOT_INSTALLED; fi"]' \
  --region "$REGION" \
  --query 'Command.CommandId' \
  --output text)

sleep 5

RESULT=$(aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'StandardOutputContent' \
  --output text)

echo "$RESULT"
echo ""

# 4. Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
if echo "$RESULT" | grep -q "INSTALLED"; then
  echo "✅ Wrapper is INSTALLED and ready to use"
else
  echo "❌ Wrapper is NOT installed - run deploy script"
fi