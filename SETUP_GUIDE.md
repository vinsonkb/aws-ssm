# 🚀 Complete SSM Session Manager Setup Guide

This guide walks you through the complete setup of AWS SSM Session Manager with comprehensive logging and enforced document usage.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start (Automated)](#quick-start-automated)
3. [Manual Setup (Step-by-Step)](#manual-setup-step-by-step)
4. [Verification & Testing](#verification--testing)
5. [Daily Usage](#daily-usage)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### ✅ Required Tools
- AWS CLI v2 (`aws --version`)
- jq (`jq --version`)
- Bash 4.0+
- AWS credentials with admin permissions

### ✅ Required AWS Resources
- EC2 instances with SSM Agent installed
- IAM permissions to:
  - Create/manage IAM users and policies
  - Create/manage S3 buckets
  - Create/manage CloudWatch Log Groups
  - Access Systems Manager (SSM)

### ✅ Check Your Current Setup

Run this to see available instances:

```bash
# List all SSM-managed instances
aws ssm describe-instance-information \
  --region ap-southeast-1 \
  --query 'InstanceInformationList[?PingStatus==`Online`].[InstanceId,PlatformName,IPAddress]' \
  --output table

# Expected output:
# ---------------------------------------------------------
# |           DescribeInstanceInformation                  |
# +----------------------+------------------+--------------+
# |  i-0ee0bc84a481f7852 |  Amazon Linux 2  |  10.0.1.123 |
# +----------------------+------------------+--------------+
```

**✅ Your Instance ID:** `i-0ee0bc84a481f7852`

---

## Quick Start (Automated)

### Option 1: Run Self-Check Script (Recommended)

This automated script will:
- ✅ Validate your AWS environment
- ✅ Check instance availability
- ✅ Create a test user with 5-minute access
- ✅ Run test commands and verify logging
- ✅ Clean up after testing

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/logging

# Run self-check with your instance
./self-check-ssm-logging.sh ap-southeast-1 i-0ee0bc84a481f7852

# Or let it auto-detect instances
./self-check-ssm-logging.sh ap-southeast-1
```

**What it does:**
1. Lists available instances (if not provided)
2. Validates instance is online
3. Checks for existing S3 bucket, CloudWatch logs
4. Creates test user with temporary access
5. Starts interactive session where you can run:
   - `whoami`
   - `ls -la`
   - `pwd`
   - `date`
   - `exit`
6. Verifies logs in CloudWatch, S3, and instance
7. Cleans up test user

---

## Manual Setup (Step-by-Step)

### Step 1: Setup Logging Infrastructure

#### 1.1 Run Setup Script

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/logging
./setup-ssm-logging.sh ap-southeast-1
```

**This creates:**
- S3 Bucket: `ssm-onetime-logs-vortech-dev`
- CloudWatch Log Group: `/aws/ssm/onetime-sessions-dev`
- SSM Document: `SSM-SessionManagerRunShell`
- IAM Policy: `SSM-Enhanced-Logging-Policy`

#### 1.2 Verify Resources Created

```bash
# Check S3 bucket
aws s3 ls s3://ssm-onetime-logs-vortech-dev --region ap-southeast-1

# Check CloudWatch Log Group
aws logs describe-log-groups \
  --log-group-name-prefix /aws/ssm/onetime-sessions-dev \
  --region ap-southeast-1

# Check IAM Policy
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam get-policy \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/SSM-Enhanced-Logging-Policy
```

---

### Step 2: Configure EC2 Instance IAM Role

#### 2.1 Find Your Instance's IAM Role

```bash
# Get instance role name
aws ec2 describe-instances \
  --instance-ids i-0ee0bc84a481f7852 \
  --region ap-southeast-1 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text

# Example output:
# arn:aws:iam::123456789012:instance-profile/MyEC2Role
# The role name is: MyEC2Role
```

**📝 Write down your role name:** `_________________`

#### 2.2 Attach Logging Policy to Role

```bash
# Replace with your actual role name from above
INSTANCE_ROLE="SSM-Enhanced-Instance-Dev-Role"  # Your actual role
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam attach-role-policy \
  --role-name "$INSTANCE_ROLE" \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/SSM-Enhanced-Logging-Policy

echo "✅ Policy attached to role: $INSTANCE_ROLE"
```

#### 2.3 Verify Policy Attached

```bash
aws iam list-attached-role-policies \
  --role-name "$INSTANCE_ROLE" \
  --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
  --output table

# Should show SSM-Enhanced-Logging-Policy in the list
```

---

### Step 3: Deploy Session Wrapper to Instances

This script logs every command executed during sessions.

#### 3.1 Deploy to Your Instance

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/logging

# Deploy to specific instance
./deploy-wrapper-to-instances.sh ap-southeast-1 i-0ee0bc84a481f7852

# Or deploy to ALL online instances
./deploy-wrapper-to-instances.sh ap-southeast-1 all
```

#### 3.2 Verify Deployment

```bash
# Check if wrapper script is deployed
aws ssm send-command \
  --instance-ids i-0ee0bc84a481f7852 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["ls -lh /usr/local/bin/ssm-session-wrapper.sh"]' \
  --region ap-southeast-1 \
  --output json | jq -r '.Command.CommandId'

# Save the CommandId from output, then check result:
COMMAND_ID="<paste-command-id-here>"

aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id i-0ee0bc84a481f7852 \
  --region ap-southeast-1 \
  --query 'StandardOutputContent' \
  --output text

# Should show: -rwxr-xr-x ... /usr/local/bin/ssm-session-wrapper.sh
```

---

### Step 4: Create Test User with JIT Access

#### 4.1 Create Test User

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

# Create user with 30-minute access
./jit-admin-session-v1.0.5 \
  -u test-user-$(whoami) \
  -i i-0ee0bc84a481f7852 \
  -d 30 \
  --new-user \
  --create-keys \
  --configure-profile test-session \
  --region ap-southeast-1
```
```
./jit-admin-session-v1.0.5 -u vinson-03 -i i-0ee0bc84a481f7852 -d 3 \
  --new-user --create-keys --configure-profile devops --output-script setup-vinson-03.sh
```

**Output will show:**
```
✅ Created IAM user: test-user-vinson
✅ Access keys created.
✅ Local profile [test-session] configured.
✅ Policy attached: OneTimeSSM-onetime-abc123def456

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 USER CONNECTION COMMAND
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Send this command to test-user-vinson:

  aws ssm start-session --target i-0ee0bc84a481f7852 --document-name SSM-SessionManagerRunShell --region ap-southeast-1 --profile test-session

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Verification & Testing

### Test 1: Connect with Enforced Document (Should Work ✅)

```bash
# This WILL work - uses required document name
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile test-session
```

**When connected, run these commands:**

```bash
whoami                          # Should show: ssm-user
pwd                             # Show current directory
ls -la                          # List files
echo "Test from $(whoami)"      # Test echo
date                            # Show date/time
exit                            # Exit session
```

### Test 2: Try WITHOUT Document Name (Should Fail ❌)

```bash
# This will FAIL - no document name specified
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --region ap-southeast-1 \
  --profile test-session

# Expected error:
# An error occurred (AccessDeniedException) when calling the StartSession operation:
# User: arn:aws:iam::xxx:user/test-user-vinson is not authorized to perform:
# ssm:StartSession on resource: arn:aws:ec2:xxx:xxx:instance/i-0ee0bc84a481f7852
```

✅ **If you get this error, enforcement is working correctly!**

### Test 3: Verify Logs Were Captured

#### 3.1 Check CloudWatch Logs

```bash
# View recent session logs (real-time streaming)
aws logs tail /aws/ssm/onetime-sessions-dev --follow --region ap-southeast-1

# Or filter by user
aws logs filter-log-events \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --filter-pattern "test-user" \
  --region ap-southeast-1 \
  --max-items 10 \
  --query 'events[*].message' \
  --output text
```

**Note:** CloudWatch logs appear in real-time (1-5 second delay).

#### 3.2 Check S3 Logs

```bash
# List session logs in S3
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --recursive \
  --human-readable \
  --summarize \
  --region ap-southeast-1

# Download latest log file
aws s3 cp \
  s3://ssm-onetime-logs-vortech-dev/sessions/ \
  ./downloaded-logs/ \
  --recursive \
  --region ap-southeast-1
```

**Note:** S3 logs upload in batches every 5-15 minutes after session ends (AWS batching behavior).

#### 3.3 Check Instance Local Logs

```bash
# Connect to instance and check logs
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile test-session

# Once connected, run:
sudo ls -lh /var/log/ssm-sessions/
sudo cat /var/log/ssm-sessions/session-test-user-*.log
```

**Expected log format:**

```
==============================================
SSM Session Started
==============================================
Session ID: test-user-vinson-0ee0bc84a481f7852-1731672000
User: test-user-vinson
Instance: i-0ee0bc84a481f7852
Start Time: 2024-11-15 10:30:00 UTC
==============================================

[2024-11-15 10:30:15] test-user-vinson: whoami
[2024-11-15 10:30:20] test-user-vinson: pwd
[2024-11-15 10:30:25] test-user-vinson: ls -la
[2024-11-15 10:30:30] test-user-vinson: echo "Test from ssm-user"
[2024-11-15 10:30:35] test-user-vinson: date
[2024-11-15 10:30:40] test-user-vinson: exit

==============================================
SSM Session Ended
End Time: 2024-11-15 10:30:45 UTC
==============================================
```

---

## Daily Usage

### Creating New User Access

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin

# For developer access (60 minutes)
./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 60 \
  --new-user \
  --create-keys \
  --output-script setup-john-dev.sh

# Send setup-john-dev.sh to the user
# They run: bash setup-john-dev.sh
```

### Renewing Existing User Access

```bash
# Extend access for existing user (30 more minutes)
./jit-admin-session-v1.0.5 \
  -u john-dev \
  -i i-0ee0bc84a481f7852 \
  -d 30 \
  --purge-existing
```

### Revoking Access Immediately

```bash
# Remove all access and sessions for a user
./jit-admin-session-v1.0.5 --purge-session john-dev
```

### Viewing Active Sessions

```bash
# List all active SSM sessions
aws ssm describe-sessions \
  --state Active \
  --region ap-southeast-1 \
  --query 'Sessions[*].[SessionId,Target,Owner,StartDate]' \
  --output table
```

### Monitoring Logs in Real-Time

```bash
# Tail CloudWatch logs (real-time)
aws logs tail /aws/ssm/onetime-sessions-dev --follow --region ap-southeast-1

# Filter for specific user
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --filter-pattern "john-dev" \
  --region ap-southeast-1
```

---

## Troubleshooting

### Issue 1: "AccessDeniedException" when starting session WITH document name

**Diagnosis:**
```bash
# Check user's IAM policies
USER="test-user-vinson"
aws iam list-user-policies --user-name "$USER"

# Get policy details
POLICY_NAME=$(aws iam list-user-policies --user-name "$USER" --query 'PolicyNames[0]' --output text)
aws iam get-user-policy --user-name "$USER" --policy-name "$POLICY_NAME"
```

**Solution:**
- Policy may have expired
- Re-run jit-admin-session with `--purge-existing` to renew

### Issue 2: No logs appearing in CloudWatch/S3

**Diagnosis:**
```bash
# Check instance IAM role
INSTANCE_ID="i-0ee0bc84a481f7852"
ROLE_ARN=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text)

ROLE_NAME=$(echo "$ROLE_ARN" | grep -oP 'instance-profile/\K[^/]+')

# Check attached policies
aws iam list-attached-role-policies --role-name "$ROLE_NAME"
```

**Solution:**
```bash
# Attach logging policy
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/SSM-Enhanced-Logging-Policy
```

### Issue 3: Wrapper script not logging commands

**Diagnosis:**
```bash
# Check if wrapper exists on instance
aws ssm send-command \
  --instance-ids i-0ee0bc84a481f7852 \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["test -x /usr/local/bin/ssm-session-wrapper.sh && echo FOUND || echo NOT_FOUND"]' \
  --region ap-southeast-1
```

**Solution:**
```bash
# Redeploy wrapper
cd /Users/vinson/Documents/0_Other_Services/SSM/logging
./deploy-wrapper-to-instances.sh ap-southeast-1 i-0ee0bc84a481f7852
```

### Issue 4: Instance not showing as "Online" in SSM

**Diagnosis:**
```bash
# Check instance SSM status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-0ee0bc84a481f7852" \
  --region ap-southeast-1
```

**Solutions:**
1. Ensure SSM Agent is running:
   ```bash
   # Connect via SSH/EC2 Instance Connect and run:
   sudo systemctl status amazon-ssm-agent
   sudo systemctl start amazon-ssm-agent
   ```

2. Check instance IAM role has AmazonSSMManagedInstanceCore policy

3. Verify network connectivity to SSM endpoints

---

## 📊 Log Retention & Storage

### CloudWatch Logs
- **Retention:** 90 days (configurable)
- **Cost:** ~$0.50/GB ingested, $0.03/GB stored
- **Access:** Real-time streaming and search

### S3 Logs
- **Retention:** Indefinite (can set lifecycle rules)
- **Cost:** ~$0.023/GB/month (S3 Standard)
- **Access:** Long-term archival and compliance

### Instance Local Logs
- **Location:** `/var/log/ssm-sessions/`
- **Retention:** Until manually deleted or log rotation
- **Cost:** Free (uses instance disk)

---

## 🔐 Security Checklist

- ✅ Document enforcement enabled (forces `--document-name SSM-SessionManagerRunShell`)
- ✅ All sessions logged to CloudWatch
- ✅ All sessions stored in encrypted S3 bucket
- ✅ Command-level logging on instances
- ✅ Time-limited access (auto-expires)
- ✅ Sessions auto-terminated at expiry
- ✅ S3 bucket has encryption enabled
- ✅ S3 bucket blocks public access
- ✅ CloudWatch log retention set to 90 days
- ✅ IAM policies follow least-privilege principle

---

## 📚 Quick Reference Commands

```bash
# Check instance status
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-0ee0bc84a481f7852"

# Create test user (5 min access)
./jit-admin-session-v1.0.5 -u test-$(date +%s) -i i-0ee0bc84a481f7852 -d 5 --new-user --create-keys --configure-profile test

# Start session (correct way)
aws ssm start-session --target i-0ee0bc84a481f7852 --document-name SSM-SessionManagerRunShell --profile test

# View CloudWatch logs (real-time)
aws logs tail /aws/ssm/onetime-sessions-dev --follow --region ap-southeast-1

# List S3 logs (5-15 min delay)
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --region ap-southeast-1

# Terminate all sessions for user
./jit-admin-session-v1.0.5 --purge-session username

# Run self-check
./logging/self-check-ssm-logging.sh ap-southeast-1 i-0ee0bc84a481f7852
```

---

## 🎯 Summary

You now have a fully configured SSM Session Manager setup with:

1. ✅ **Enforced document usage** - Users must use `SSM-SessionManagerRunShell`
2. ✅ **Triple logging** - CloudWatch + S3 + Instance local
3. ✅ **Command recording** - Every command logged with timestamp and user
4. ✅ **Time-limited access** - Auto-expiring permissions
5. ✅ **Auto-termination** - Sessions killed at expiry
6. ✅ **Self-check script** - Automated testing and validation

**Next Steps:**
1. Run the self-check script to validate everything
2. Create your first production user
3. Monitor logs to ensure everything is working
4. Share this guide with your team

For questions or issues, refer to the [README.md](logging/README.md) in the logging directory.
