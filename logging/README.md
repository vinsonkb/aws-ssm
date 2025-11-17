# SSM Session Manager Logging & Security Setup

This directory contains scripts and configurations to enable comprehensive logging and enforce secure document usage for AWS SSM Session Manager.

## 🎯 Features

### 1. **Force Document Name Usage**
- Users **MUST** use `--document-name SSM-SessionManagerRunShell` to start sessions
- Attempting to start a session without the correct document name will be **denied**
- IAM policy enforces this requirement through conditions

### 2. **Comprehensive Logging**
- **CloudWatch Logs**: Real-time session log streaming
- **S3 Storage**: Long-term session log storage with encryption
- **Local Instance Logs**: Command-level logging on each instance at `/var/log/ssm-sessions/`
- **Command Recording**: Every command executed is timestamped and logged with username

## 📁 Files

### Core Scripts
- **`ssm-session-wrapper.sh`**: Session wrapper that logs all commands (deployed to EC2 instances)
- **`setup-ssm-logging.sh`**: One-time setup for S3, CloudWatch, and SSM preferences
- **`deploy-wrapper-to-instances.sh`**: Deploy wrapper script to EC2 instances via SSM Run Command

### Configuration Files
- **`ssm-session-preferences.json`**: Session Manager preferences template
- **`iam-instance-logging-policy.json`**: IAM policy for EC2 instances to upload logs

### Admin Tool
- **`../jit-admin/jit-admin-session-v1.0.5`**: Updated admin script with enforced document usage

## 🚀 Setup Instructions

### Step 1: Initial Infrastructure Setup

Run the setup script to create S3 bucket, CloudWatch log group, and configure SSM:

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/logging
./setup-ssm-logging.sh ap-southeast-1
```

This will:
- ✅ Create S3 bucket: `ssm-session-logs-{account-id}-{region}`
- ✅ Create CloudWatch Log Group: `/aws/ssm/sessions`
- ✅ Configure SSM Session Manager preferences
- ✅ Create IAM policy for EC2 instances

### Step 2: Attach IAM Policy to EC2 Instance Role

Attach the created policy to your EC2 instance IAM role:

```bash
# Get the policy ARN from setup output
POLICY_ARN="arn:aws:iam::{account-id}:policy/SSM-SessionManager-Logging-Policy"
INSTANCE_ROLE="YourEC2InstanceRole"

aws iam attach-role-policy \
  --role-name "$INSTANCE_ROLE" \
  --policy-arn "$POLICY_ARN"
```

### Step 3: Deploy Session Wrapper to EC2 Instances

Deploy the logging wrapper script to your instances:

```bash
# Deploy to specific instances
./deploy-wrapper-to-instances.sh ap-southeast-1 i-0123456789abcdef0,i-0fedcba9876543210

# Or deploy to all SSM-managed instances
./deploy-wrapper-to-instances.sh ap-southeast-1 all
```

### Step 4: Create JIT Access with Enforced Document Usage

Use the updated admin script to grant time-limited access:

```bash
cd ../jit-admin

# Create new user with setup script
./jit-admin-session-v1.0.5 \
  -u tony-03 \
  -i i-0ee0bc84a481f7852 \
  -d 30 \
  --new-user \
  --create-keys \
  --output-script setup-tony-03.sh

# The generated setup script will automatically use the correct document name
```

## 🔒 How Document Enforcement Works

### IAM Policy Enforcement

The updated IAM policy in `jit-admin-session-v1.0.5` includes a condition:

```json
{
  "Sid": "StartSessionAnyManagedInstance",
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": [
    "arn:aws:ec2:*:*:instance/*",
    "arn:aws:ssm:*:*:managed-instance/*"
  ],
  "Condition": {
    "StringEquals": {
      "ssm:SessionDocumentAccessCheck": "true"
    }
  }
}
```

This combined with requiring explicit permission for the document:

```json
{
  "Sid": "StartSessionDocument",
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": "arn:aws:ssm:{region}:{account}:document/SSM-SessionManagerRunShell"
}
```

### What Happens When Users Try to Connect

✅ **With correct document** (allowed):
```bash
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1
```

❌ **Without document name** (denied):
```bash
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --region ap-southeast-1

# Error: AccessDeniedException
```

❌ **With wrong document** (denied):
```bash
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --region ap-southeast-1

# Error: AccessDeniedException
```

## 📊 Viewing Logs

### CloudWatch Logs
```bash
# View recent sessions
aws logs tail /aws/ssm/sessions --follow --region ap-southeast-1

# Search for specific user sessions
aws logs filter-log-events \
  --log-group-name /aws/ssm/sessions \
  --filter-pattern "tony-03" \
  --region ap-southeast-1
```

### S3 Logs
```bash
# List all session logs
aws s3 ls s3://ssm-session-logs-{account-id}-{region}/session-logs/ --recursive

# Download specific session logs
aws s3 cp s3://ssm-session-logs-{account-id}-{region}/session-logs/ . --recursive
```

### Instance Local Logs
```bash
# SSH to instance (if needed) or use SSM
aws ssm start-session --target i-0123456789abcdef0 --document-name SSM-SessionManagerRunShell

# View session logs
sudo ls -lh /var/log/ssm-sessions/
sudo cat /var/log/ssm-sessions/session-tony-03-20241115-143000.log
```

## 🧪 Testing

### Test 1: Verify Document Enforcement

```bash
# Should FAIL (no document)
aws ssm start-session --target i-xxx --profile tony-03

# Should SUCCEED
aws ssm start-session --target i-xxx --document-name SSM-SessionManagerRunShell --profile tony-03
```

### Test 2: Verify Command Logging

1. Start a session with the correct document
2. Run some commands:
   ```bash
   whoami
   pwd
   ls -la
   echo "test"
   ```
3. Check logs in CloudWatch, S3, and instance

## 📋 Log Format Example

```
==============================================
SSM Session Started
==============================================
Session ID: tony-03-0ee0bc84a481f7852-1234567890abc
User: tony-03
Instance: i-0ee0bc84a481f7852
Start Time: 2024-11-15 14:30:00 UTC
==============================================

[2024-11-15 14:30:15] tony-03: whoami
[2024-11-15 14:30:20] tony-03: pwd
[2024-11-15 14:30:25] tony-03: ls -la
[2024-11-15 14:30:30] tony-03: sudo systemctl status nginx
[2024-11-15 14:35:00] tony-03: exit

==============================================
SSM Session Ended
End Time: 2024-11-15 14:35:05 UTC
==============================================
```

## 🔧 Troubleshooting

### Issue: Session wrapper not executing

**Solution**: Verify wrapper is deployed and executable:
```bash
aws ssm send-command \
  --instance-ids i-xxx \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["ls -lh /usr/local/bin/ssm-session-wrapper.sh"]'
```

### Issue: Logs not appearing in S3/CloudWatch

**Solution**: Check instance IAM role has the logging policy:
```bash
ROLE_NAME="YourInstanceRole"
aws iam list-attached-role-policies --role-name "$ROLE_NAME"
```

### Issue: Access denied when starting session

**Solution**: Verify user is using correct document name:
```bash
# Check user's IAM policies
aws iam list-user-policies --user-name tony-03

# Verify policy includes document permission
aws iam get-user-policy --user-name tony-03 --policy-name OneTimeSSM-xxxxx
```

## 🔐 Security Best Practices

1. ✅ **Always use document enforcement** - Never grant wildcard SSM document access
2. ✅ **Enable S3 encryption** - Logs contain sensitive command history
3. ✅ **Set CloudWatch retention** - Default is 90 days, adjust as needed
4. ✅ **Restrict log access** - Use separate IAM policies for log viewing
5. ✅ **Monitor failed access attempts** - Set up CloudWatch alarms for AccessDenied
6. ✅ **Regular log review** - Audit session logs for suspicious activity
7. ✅ **Time-limited access** - Use jit-admin for temporary access only

## 📚 Additional Resources

- [AWS SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Session Manager Logging](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html)
- [IAM Condition Keys for SSM](https://docs.aws.amazon.com/service-authorization/latest/reference/list_awssystemsmanager.html)
