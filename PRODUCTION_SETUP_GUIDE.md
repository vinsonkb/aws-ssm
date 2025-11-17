# Production Setup Guide - SSM Session Manager with JIT Access

**Complete, tested setup guide with all production fixes applied**

**Last Updated:** November 16, 2025
**Tested On:** Account 937206802878, Region ap-southeast-1, Instance i-0ee0bc84a481f7852

---

## 🎯 What This Guide Provides

✅ **Verified setup steps** - All tested in production
✅ **Critical IAM policy fixes** - Correct CloudWatch log group configuration
✅ **Timing expectations** - IAM propagation, S3 upload delays
✅ **Troubleshooting solutions** - Real issues and fixes
✅ **Best practices** - Script reusability, renewal workflows

---

## 📋 Prerequisites

### Required Information

Before starting, gather this information:

| Item | How to Find | Example |
|------|-------------|---------|
| **AWS Account ID** | `aws sts get-caller-identity --query Account --output text` | `937206802878` |
| **AWS Region** | Your target region | `ap-southeast-1` |
| **EC2 Instance ID** | `aws ssm describe-instance-information --query 'InstanceInformationList[?PingStatus==\`Online\`].InstanceId'` | `i-0ee0bc84a481f7852` |
| **Instance IAM Role** | `aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'` | `SSM-Enhanced-Instance-Dev-Role` |

### Tools Required

```bash
# Verify you have these installed
aws --version     # Need v2.x
jq --version      # Need 1.6+
bash --version    # Need 4.0+
```

---

## 🏗️ Architecture Overview

### Your SSM Document Configuration

Check what you currently have:

```bash
aws ssm get-document \
  --name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --query 'Content' \
  --output text | jq '.inputs'
```

**Expected output:**
```json
{
  "s3BucketName": "ssm-onetime-logs-vortech-dev",
  "s3KeyPrefix": "sessions/",
  "cloudWatchLogGroupName": "/aws/ssm/onetime-sessions-dev",
  "cloudWatchStreamingEnabled": true
}
```

**📝 Write down your values:**
- S3 Bucket: `_______________________`
- S3 Prefix: `_______________________`
- CloudWatch Log Group: `_______________________`

---

## ⚙️ Step 1: Create/Update Instance IAM Policy

### Critical: CloudWatch Log Group Must Match!

The IAM policy **MUST** use the **EXACT** log group name from your SSM document.

#### 1.1 Create the Policy

**⚠️ IMPORTANT:** Replace these values with YOUR configuration:
- Replace `ssm-onetime-logs-vortech-dev` with YOUR S3 bucket name
- Replace `/aws/ssm/onetime-sessions-dev` with YOUR CloudWatch log group name
- Replace `937206802878` with YOUR account ID
- Replace `ap-southeast-1` with YOUR region

```bash
# Set your values
ACCOUNT_ID="937206802878"
REGION="ap-southeast-1"
S3_BUCKET="ssm-onetime-logs-vortech-dev"
CLOUDWATCH_LOG_GROUP="/aws/ssm/onetime-sessions-dev"

# Create policy document
cat > /tmp/ssm-logging-policy.json <<EOF
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
      "Resource": "arn:aws:s3:::${S3_BUCKET}/sessions/*"
    },
    {
      "Sid": "SSMSessionLogsS3Encryption",
      "Effect": "Allow",
      "Action": [
        "s3:GetEncryptionConfiguration"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET}"
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
        "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:${CLOUDWATCH_LOG_GROUP}",
        "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:${CLOUDWATCH_LOG_GROUP}:*"
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

# Create or update the policy
POLICY_NAME="SSM-Enhanced-Logging-Policy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

# Check if policy exists
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "✅ Policy exists, creating new version..."

  # Delete old non-default versions (max 5 versions allowed)
  OLD_VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" \
    --query 'Versions[?!IsDefaultVersion].VersionId' --output text)

  for VERSION in $OLD_VERSIONS; do
    aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION" 2>/dev/null || true
  done

  # Create new version
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document file:///tmp/ssm-logging-policy.json \
    --set-as-default

  echo "✅ Policy updated to new version"
else
  echo "✅ Creating new policy..."
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file:///tmp/ssm-logging-policy.json \
    --description "Allows EC2 instances to log SSM sessions to S3 and CloudWatch"

  echo "✅ Policy created: $POLICY_ARN"
fi
```

#### 1.2 Verify Policy Content

```bash
# Verify the policy has correct log group
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/SSM-Enhanced-Logging-Policy"
VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" --query 'Policy.DefaultVersionId' --output text)

aws iam get-policy-version \
  --policy-arn "$POLICY_ARN" \
  --version-id "$VERSION" \
  --query 'PolicyVersion.Document.Statement[?Sid==`SSMSessionLogsCloudWatch`].Resource' \
  --output json

# Should show YOUR CloudWatch log group name!
```

---

## ⚙️ Step 2: Attach Policy to Instance Role

### 2.1 Find Instance Role Name

```bash
# Get instance profile ARN
INSTANCE_ID="i-0ee0bc84a481f7852"
INSTANCE_PROFILE_ARN=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text)

echo "Instance Profile ARN: $INSTANCE_PROFILE_ARN"

# Extract profile name
PROFILE_NAME=$(echo "$INSTANCE_PROFILE_ARN" | grep -oP 'instance-profile/\K[^/]+')

# Get actual role name from profile
INSTANCE_ROLE=$(aws iam get-instance-profile \
  --instance-profile-name "$PROFILE_NAME" \
  --query 'InstanceProfile.Roles[0].RoleName' \
  --output text)

echo "Instance Role Name: $INSTANCE_ROLE"
```

**📝 Your instance role:** `_______________________`

### 2.2 Attach Logging Policy

```bash
# Attach the policy to instance role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/SSM-Enhanced-Logging-Policy"

aws iam attach-role-policy \
  --role-name "$INSTANCE_ROLE" \
  --policy-arn "$POLICY_ARN"

echo "✅ Policy attached to $INSTANCE_ROLE"
```

### 2.3 Verify Attachment

```bash
# List all policies on the role
aws iam list-attached-role-policies \
  --role-name "$INSTANCE_ROLE" \
  --output table

# Should show:
# - AmazonSSMManagedInstanceCore
# - SSM-Enhanced-Logging-Policy
```

---

## ⚙️ Step 3: Test CloudWatch Logging (Critical!)

### Why This Matters

Many setups have CloudWatch enabled but **logs don't appear** because:
- ❌ Wrong log group name in IAM policy
- ❌ Missing CloudWatch permissions
- ❌ CloudWatch streaming disabled in document

### 3.1 Start Test Session in Terminal 1

```bash
# Create a quick test user (3 minutes)
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

./jit-admin-session-v1.0.5 \
  -u test-cloudwatch \
  -i i-0ee0bc84a481f7852 \
  -d 3 \
  --new-user \
  --create-keys \
  --configure-profile test-cloudwatch \
  --region ap-southeast-1

# Wait 10 seconds for IAM propagation
sleep 10

# Start session
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile test-cloudwatch
```

### 3.2 Monitor CloudWatch in Terminal 2

**Open a SECOND terminal** and run:

```bash
# Tail CloudWatch logs (should show real-time output)
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --region ap-southeast-1
```

### 3.3 Run Test Commands in Terminal 1

```bash
# In the session, type these commands:
whoami
pwd
echo "CloudWatch logging test"
date
```

### 3.4 Verify in Terminal 2

**You should see output appear within 1-5 seconds:**

```
Script started on 2025-11-16 06:30:00+00:00
whoami
ssm-user
pwd
/usr/bin
echo "CloudWatch logging test"
CloudWatch logging test
date
Sat Nov 16 06:30:15 UTC 2025
```

### 3.5 Troubleshooting if No Logs Appear

```bash
# Check CloudWatch log group exists
aws logs describe-log-groups \
  --log-group-name-prefix /aws/ssm/onetime-sessions-dev \
  --region ap-southeast-1

# Check for log streams
aws logs describe-log-streams \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --region ap-southeast-1 \
  --order-by LastEventTime \
  --descending \
  --max-items 5

# If NO log streams exist:
# 1. IAM policy has wrong log group name
# 2. Instance role doesn't have the policy
# 3. CloudWatch streaming disabled in document
```

### 3.6 Cleanup Test User

```bash
# Exit the session first
exit

# Purge test user
./jit-admin-session-v1.0.5 --purge-session test-cloudwatch --region ap-southeast-1
```

---

## ⚙️ Step 4: Understand Timing & Delays

### IAM Policy Propagation

**When you create/renew user access:**

```bash
./jit-admin-session-v1.0.5 -u USER -i INSTANCE -d 30 --purge-existing
# ✅ Policy created/updated instantly
# ⏳ Wait 5-10 seconds for global IAM propagation
# ✅ Then user can connect
```

**Timeline:**
```
T+0:00  Command runs, policy created
T+0:05  Policy propagated to some regions
T+0:10  Policy fully propagated globally  ← Safe to connect
T+0:15  User tries too early → May get AccessDenied
T+0:20  User tries again → Success!
```

**Best Practice:**
```bash
# Renew access
./jit-admin-session-v1.0.5 -u USER -i INSTANCE -d 60 --purge-existing

# Wait for IAM propagation
sleep 10

# Now connect (or user can reuse their script)
bash USER-access.sh  # ✅ Works!
```

### S3 Log Upload Delay

**S3 logs take 5-15 minutes** after session ends (AWS batching).

**Timeline:**
```
Session ends          T+0:00
CloudWatch logs       T+0:01  ✅ Available immediately
S3 upload queued      T+0:05
S3 batch upload       T+5:00  ← Typical
S3 log available      T+8:00  ✅ Average time
```

**Use CloudWatch for immediate logs:**
```bash
# Real-time (1-5 second delay)
aws logs tail /aws/ssm/onetime-sessions-dev --follow

# S3 for archival (5-15 minute delay)
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/
```

---

## 🎯 Daily Usage

### Creating New User (First Time)

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

# Create user with script (for easy access)
./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 240 \
  --new-user \
  --create-keys \
  --output-script setup-john-dev.sh \
  --region ap-southeast-1

# Send setup-john-dev.sh to user
# User runs: bash setup-john-dev.sh
```

### Renewing Existing User

```bash
# Simple renewal (user reuses same script)
./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 240 \
  --purge-existing \
  --region ap-southeast-1

# Wait 10 seconds for IAM propagation
sleep 10

# User can now reconnect with their existing script
# bash setup-john-dev.sh  (same script works!)
```

**❓ Do I need `--output-script` every time?**
**❌ NO!** The script is reusable. Only generate it once.

**❓ Do I need `--create-keys` for renewals?**
**❌ NO!** Keys remain valid. Only use `--purge-existing`.

### Revoking Access

```bash
# Immediately terminate sessions and remove access
./jit-admin-session-v1.0.5 --purge-session john-dev --region ap-southeast-1

# This removes:
# - All IAM policies
# - All active sessions
# - All access keys (with confirmation)
```

---

## 🔍 Verification Checklist

### After Setup, Verify:

```bash
# 1. Instance has correct IAM role
aws ec2 describe-instances --instance-ids i-0ee0bc84a481f7852 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn'

# 2. Role has logging policy
aws iam list-attached-role-policies --role-name YOUR-ROLE-NAME

# 3. Policy has correct log group
aws iam get-policy-version --policy-arn arn:aws:iam::ACCOUNT:policy/SSM-Enhanced-Logging-Policy \
  --version-id $(aws iam get-policy --policy-arn arn:aws:iam::ACCOUNT:policy/SSM-Enhanced-Logging-Policy --query 'Policy.DefaultVersionId' --output text) \
  --query 'PolicyVersion.Document.Statement[?Sid==`SSMSessionLogsCloudWatch`].Resource'

# 4. SSM document exists
aws ssm describe-document --name SSM-SessionManagerRunShell --region ap-southeast-1

# 5. CloudWatch logging works (critical!)
# Create test session and verify logs appear in CloudWatch within 5 seconds
```

---

## ⚠️ Common Issues & Solutions

### Issue 1: AccessDeniedException Immediately After Renewal

**Symptom:**
```bash
./jit-admin-session-v1.0.5 -u USER ... --purge-existing
bash USER-access.sh
# Error: AccessDeniedException
```

**Cause:** IAM policy not propagated yet (takes 5-10 seconds)

**Solution:**
```bash
# Renew
./jit-admin-session-v1.0.5 -u USER ... --purge-existing

# Wait for IAM
sleep 10

# Try again
bash USER-access.sh  # ✅ Works now
```

### Issue 2: No CloudWatch Logs

**Symptom:** Sessions work but `aws logs tail` shows nothing

**Diagnosis:**
```bash
# Check policy has correct log group
aws iam get-policy-version ... | grep -A5 SSMSessionLogsCloudWatch

# Should match your SSM document log group exactly!
```

**Solution:** Update IAM policy with correct log group (see Step 1)

### Issue 3: No S3 Logs After 20 Minutes

**Diagnosis:**
```bash
# Check S3 permissions in policy
aws iam get-policy-version ... | grep -A5 SSMSessionLogsS3

# Check S3 bucket name matches document
aws ssm get-document --name SSM-SessionManagerRunShell | jq '.inputs.s3BucketName'
```

**Solution:** Update IAM policy with correct S3 bucket name

### Issue 4: User Can Reconnect After Time Expired

**This is NORMAL!** IAM deletion takes 30-90 seconds to propagate globally.

**Expected behavior:**
```
Timer expires     → Policy deleted
User reconnects   → May work (IAM not propagated)
After 30-90 sec   → AccessDeniedException ✅
```

**The script now terminates sessions 3 times over 60 seconds to handle this.**

---

## 📊 Log Checking Commands

### Check CloudWatch (Real-Time)

```bash
# Tail all logs
aws logs tail /aws/ssm/onetime-sessions-dev --follow --region ap-southeast-1

# Filter by user (if username appears in logs)
aws logs tail /aws/ssm/onetime-sessions-dev --follow --filter-pattern "username" --region ap-southeast-1
```

### Check S3 (5-15 Min Delay)

```bash
# List recent logs
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --region ap-southeast-1 | tail -20

# Download specific log
aws s3 cp s3://ssm-onetime-logs-vortech-dev/sessions/USER-SESSION.log ./session.log

# View log
cat ./session.log
```

### Use Log Checker Script

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

# Check all logs for a user
./check-session-logs.sh username ap-southeast-1
```

---

## 🎓 Best Practices

1. **Always use `--document-name SSM-SessionManagerRunShell`**
   - Enforced by IAM policy
   - Required for logging to work

2. **Generate setup scripts once, reuse forever**
   - Use `--output-script` on first creation
   - Use `--purge-existing` for renewals
   - Same script works every time

3. **Wait 10 seconds after renewal before connecting**
   - IAM propagation is not instant
   - Prevents AccessDenied errors

4. **Use CloudWatch for immediate log access**
   - 1-5 second delay
   - S3 takes 5-15 minutes

5. **Set appropriate access durations**
   - Testing: 3-5 minutes
   - Development: 4 hours (240 min)
   - Never set longer than needed

6. **Revoke access immediately when done**
   - Use `--purge-session` to cleanup
   - Removes policies, keys, and sessions

---

## 📚 Related Documentation

- **[Complete Use Case Guide](Guide/JIT-ADMIN-COMPLETE-GUIDE.md)** - 10 real-world scenarios
- **[Quick Reference](Guide/QUICK-REFERENCE.md)** - One-page cheat sheet
- **[Troubleshooting Logs & Timing](Guide/TROUBLESHOOTING-LOGS-AND-TIMING.md)** - Deep dive on delays
- **[How to See Logs](HOW_TO_SEE_LOGS.md)** - Log access guide

---

## ✅ Setup Complete!

After following this guide, you should have:

- ✅ Instance IAM role with correct logging policy
- ✅ CloudWatch logs working (real-time)
- ✅ S3 logs working (5-15 min delay)
- ✅ JIT access script configured
- ✅ Understanding of timing/delays

**Test everything with a 3-minute test user and verify logs appear!**

---

**Guide Version:** 1.0 (Production-Tested)
**Last Updated:** November 16, 2025
**Tested By:** Vinson (Account 937206802878)
