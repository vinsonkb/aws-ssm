# Adding New Servers to Existing SSM Environment

**Quick guide for adding additional EC2 instances to your existing SSM Session Manager setup**

**Prerequisites:** You already have SSM logging infrastructure set up (S3 bucket, CloudWatch log group, SSM Document).

---

## 🎯 Overview

When you add a new EC2 instance to your environment, you **DO NOT** need to run the setup script again. The logging infrastructure (S3 bucket, CloudWatch log group, SSM Document) already exists and can be shared across all instances.

**What you DO need:**
1. ✅ SSM Agent installed on the new instance
2. ✅ IAM role attached with correct permissions
3. ✅ Session wrapper script deployed to the instance

---

## 📋 Step-by-Step Guide

### Step 1: Install SSM Agent (if not already installed)

#### **Amazon Linux 2023 / Amazon Linux 2** (Pre-installed)
```bash
# Connect to instance via SSH or EC2 Instance Connect
# Check if SSM Agent is running
sudo systemctl status amazon-ssm-agent

# If not running, start it
sudo systemctl start amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
```

#### **Ubuntu 22.04 / 20.04 / 18.04**
```bash
# Install via snap
sudo snap install amazon-ssm-agent --classic

# Start and enable
sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service

# Verify
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service
```

#### **Ubuntu 16.04 / Debian**
```bash
# Download and install
cd /tmp
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
sudo dpkg -i amazon-ssm-agent.deb

# Start and enable
sudo systemctl start amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
```

#### **RHEL / CentOS / Rocky Linux**
```bash
# Install
sudo yum install -y amazon-ssm-agent

# Start and enable
sudo systemctl start amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
```

#### **Verify Installation**
```bash
# From your local machine
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-YOUR-NEW-INSTANCE-ID" \
  --region ap-southeast-1 \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,PlatformVersion]' \
  --output table
```

**Expected output:**
```
-------------------------------------------------------------
|              DescribeInstanceInformation                  |
+---------------------+----------+----------------+---------+
|  i-0abc123def456789 |  Online  |  Amazon Linux  |  2023   |
+---------------------+----------+----------------+---------+
```

---

### Step 2: Attach IAM Role to New Instance

#### **Option A: Use Existing SSM Role** (Recommended)

If your new instance should have the same SSM permissions as your existing instances:

```bash
# 1. Find the existing IAM role from a working instance
EXISTING_INSTANCE="i-0ee0bc84a481f7852"  # Your working instance
REGION="ap-southeast-1"

EXISTING_ROLE=$(aws ec2 describe-instances \
  --instance-ids "$EXISTING_INSTANCE" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text | awk -F'/' '{print $NF}')

echo "Existing role: $EXISTING_ROLE"
# Output: SSM-Enhanced-Instance-Dev-Role

# 2. Attach the same role to your new instance
NEW_INSTANCE="i-YOUR-NEW-INSTANCE-ID"

aws ec2 associate-iam-instance-profile \
  --instance-id "$NEW_INSTANCE" \
  --iam-instance-profile Name="$EXISTING_ROLE" \
  --region "$REGION"

# 3. Verify
aws ec2 describe-instances \
  --instance-ids "$NEW_INSTANCE" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text
```

#### **Option B: Create Instance with IAM Role** (When Launching)

If you're launching a brand new instance:

```bash
aws ec2 run-instances \
  --image-id ami-0c802847a7dd848c0 \  # Amazon Linux 2023 in ap-southeast-1
  --instance-type t3.micro \
  --iam-instance-profile Name=SSM-Enhanced-Instance-Dev-Role \
  --subnet-id subnet-xxxxxxxx \
  --security-group-ids sg-xxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=MyNewSSMInstance},{Key=Environment,Value=Development}]' \
  --region ap-southeast-1
```

---

### Step 3: Deploy Session Wrapper Script

The session wrapper logs all commands executed during SSM sessions.

```bash
# From your local machine
cd /Users/vinson/Documents/0_Other_Services/SSM/logging

# Deploy to your new instance
./deploy-wrapper-to-instances.sh i-YOUR-NEW-INSTANCE-ID
```

**What this script does:**
1. Copies `ssm-session-wrapper.sh` to `/usr/local/bin/` on the instance
2. Sets executable permissions (`chmod +x`)
3. Creates log directory `/var/log/ssm-sessions/`

**Manual deployment** (if script doesn't work):
```bash
# Copy wrapper script to instance
aws ssm send-command \
  --instance-ids i-YOUR-NEW-INSTANCE-ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="[
    'sudo mkdir -p /var/log/ssm-sessions',
    'sudo chmod 755 /var/log/ssm-sessions',
    'sudo curl -o /usr/local/bin/ssm-session-wrapper.sh https://raw.githubusercontent.com/YOUR-REPO/ssm-session-wrapper.sh',
    'sudo chmod +x /usr/local/bin/ssm-session-wrapper.sh'
  ]" \
  --region ap-southeast-1
```

Or use the actual file from your project:
```bash
WRAPPER_CONTENT=$(cat /Users/vinson/Documents/0_Other_Services/SSM/logging/ssm-session-wrapper.sh | base64)

aws ssm send-command \
  --instance-ids i-YOUR-NEW-INSTANCE-ID \
  --document-name "AWS-RunShellScript" \
  --parameters commands="[
    'sudo mkdir -p /var/log/ssm-sessions',
    'echo \"$WRAPPER_CONTENT\" | base64 -d | sudo tee /usr/local/bin/ssm-session-wrapper.sh > /dev/null',
    'sudo chmod +x /usr/local/bin/ssm-session-wrapper.sh'
  ]" \
  --region ap-southeast-1
```

---

### Step 4: Verify Setup

#### **Test 1: SSM Session Connectivity**
```bash
# Start a test session
aws ssm start-session \
  --target i-YOUR-NEW-INSTANCE-ID \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1

# Inside the session, run a test command
whoami
date
exit
```

#### **Test 2: Check CloudWatch Logs (Real-Time)**
```bash
# In another terminal, tail CloudWatch logs
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --region ap-southeast-1 \
  | grep i-YOUR-NEW-INSTANCE-ID
```

**Expected:** You should see session start/commands appearing within 1-5 seconds.

#### **Test 3: Check S3 Logs (After Session Ends)**
```bash
# Wait 1-2 minutes after ending session, then check S3
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --recursive \
  --human-readable \
  --region ap-southeast-1 \
  | grep i-YOUR-NEW-INSTANCE-ID
```

#### **Test 4: Check Instance Local Logs**
```bash
# Connect to instance and check local logs
aws ssm start-session \
  --target i-YOUR-NEW-INSTANCE-ID \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1

# Inside the session:
sudo ls -lh /var/log/ssm-sessions/
sudo tail -20 /var/log/ssm-sessions/*.log
```

---

## 🔧 Troubleshooting

### Issue 1: Instance Not Showing in SSM

**Symptom:**
```bash
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-xxx"
# Returns empty
```

**Solutions:**
1. **Check SSM Agent is running:**
   ```bash
   # Via EC2 Instance Connect or SSH
   sudo systemctl status amazon-ssm-agent
   sudo systemctl restart amazon-ssm-agent
   ```

2. **Check IAM role permissions:**
   ```bash
   # Ensure role has AmazonSSMManagedInstanceCore policy
   aws iam list-attached-role-policies \
     --role-name SSM-Enhanced-Instance-Dev-Role
   ```

3. **Check instance has IAM role:**
   ```bash
   aws ec2 describe-instances \
     --instance-ids i-YOUR-NEW-INSTANCE-ID \
     --query 'Reservations[0].Instances[0].IamInstanceProfile'
   ```

4. **Wait 5 minutes** - SSM Agent needs time to register with SSM service.

---

### Issue 2: CloudWatch Logs Not Appearing

**Symptom:** Session works but no logs in CloudWatch.

**Solutions:**
1. **Check IAM policy includes CloudWatch permissions:**
   ```bash
   # The instance role MUST have the logs:DescribeLogGroups permission with Resource: "*"
   # See: Guide/CLOUDWATCH-LOGGING-FIX.md
   ```

2. **Restart SSM Agent** (to refresh credentials):
   ```bash
   aws ssm send-command \
     --instance-ids i-YOUR-NEW-INSTANCE-ID \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["sudo systemctl restart amazon-ssm-agent"]' \
     --region ap-southeast-1
   ```

3. **Verify SSM Document is correct:**
   ```bash
   aws ssm get-document \
     --name SSM-SessionManagerRunShell \
     --region ap-southeast-1 \
     --query 'Content' \
     --output text | jq '.inputs.cloudWatchLogGroupName'
   # Should return: "/aws/ssm/onetime-sessions-dev"
   ```

---

### Issue 3: Session Wrapper Not Logging Commands

**Symptom:** Session works, CloudWatch/S3 logs show session start/end, but no command-level logging.

**Solutions:**
1. **Check wrapper script exists:**
   ```bash
   aws ssm send-command \
     --instance-ids i-YOUR-NEW-INSTANCE-ID \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["ls -lh /usr/local/bin/ssm-session-wrapper.sh"]' \
     --region ap-southeast-1
   ```

2. **Check wrapper script permissions:**
   ```bash
   aws ssm send-command \
     --instance-ids i-YOUR-NEW-INSTANCE-ID \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["sudo chmod +x /usr/local/bin/ssm-session-wrapper.sh"]' \
     --region ap-southeast-1
   ```

3. **Re-deploy the wrapper script** (Step 3 above).

---

## 📊 Checklist

Use this checklist when adding each new server:

- [ ] SSM Agent installed and running
- [ ] Instance appears Online in `aws ssm describe-instance-information`
- [ ] IAM role attached to instance
- [ ] IAM role has logging permissions (S3 + CloudWatch)
- [ ] Session wrapper script deployed to `/usr/local/bin/ssm-session-wrapper.sh`
- [ ] Test session successful
- [ ] CloudWatch logs appearing (real-time)
- [ ] S3 logs appearing (after session ends, 1-2 min)
- [ ] Instance local logs appearing in `/var/log/ssm-sessions/`

---

## 🎯 Quick Commands Summary

```bash
# Set variables
NEW_INSTANCE="i-YOUR-NEW-INSTANCE-ID"
REGION="ap-southeast-1"
IAM_ROLE="SSM-Enhanced-Instance-Dev-Role"

# 1. Verify SSM Agent is registered
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$NEW_INSTANCE" \
  --region $REGION

# 2. Attach IAM role
aws ec2 associate-iam-instance-profile \
  --instance-id $NEW_INSTANCE \
  --iam-instance-profile Name=$IAM_ROLE \
  --region $REGION

# 3. Deploy wrapper script
cd /Users/vinson/Documents/0_Other_Services/SSM/logging
./deploy-wrapper-to-instances.sh $NEW_INSTANCE

# 4. Test session
aws ssm start-session \
  --target $NEW_INSTANCE \
  --document-name SSM-SessionManagerRunShell \
  --region $REGION

# 5. Monitor logs
aws logs tail /aws/ssm/onetime-sessions-dev --follow --region $REGION
```

---

## 📚 Related Guides

- [SETUP_GUIDE.md](../SETUP_GUIDE.md) - Full infrastructure setup (first-time only)
- [CLOUDWATCH-LOGGING-FIX.md](CLOUDWATCH-LOGGING-FIX.md) - CloudWatch IAM permission fix
- [HOW_TO_SEE_LOGS.md](HOW_TO_SEE_LOGS.md) - Viewing and filtering logs
- [JIT-ADMIN-COMPLETE-GUIDE.md](JIT-ADMIN-COMPLETE-GUIDE.md) - Granting user access

---

**Last Updated:** November 16, 2025
**Environment:** ap-southeast-1, Account 937206802878
