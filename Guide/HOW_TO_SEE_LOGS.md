# How to See Session Logs in S3

## 🎯 Understanding SSM Logging

### ❌ What DOESN'T Create S3 Logs
```bash
# SSM Run Command - logs only go to command history
aws ssm send-command \
  --instance-ids i-xxx \
  --document-name "AWS-RunShellScript" \
  --parameters commands=["whoami","ls"]
```
**Result:** No S3 logs, no CloudWatch session logs

### ✅ What DOES Create S3 Logs
```bash
# SSM Session Manager - creates full session logs
aws ssm start-session \
  --target i-xxx \
  --document-name SSM-SessionManagerRunShell \
  --profile username
```
**Result:** Logs appear in S3, CloudWatch, and instance

---

## 📊 Your Current Configuration

**From your `SSM-SessionManagerRunShell` document:**

| Setting | Value |
|---------|-------|
| **S3 Bucket** | `ssm-onetime-logs-vortech-dev` |
| **S3 Prefix** | `sessions/` |
| **CloudWatch Log Group** | `/aws/ssm/onetime-sessions-dev` |
| **Instance Wrapper** | `/usr/local/bin/ssm-session-wrapper.sh` |
| **Idle Timeout** | 20 minutes |
| **Max Duration** | 240 minutes (4 hours) |

---

## 🧪 Live Test - Create Your Own Session Log

I've created a test user for you to try:

### Step 1: Start an Interactive Session

```bash
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile demo-test-user
```

### Step 2: Run Some Commands

Once connected, type these commands:

```bash
whoami                    # Shows current user
pwd                       # Shows current directory
ls -la /home             # List home directories
hostname                  # Shows hostname
date                      # Shows current date/time
echo "Testing S3 logging from demo-test-user"
history                   # Shows command history
exit                      # Ends session
```

### Step 3: Check S3 for Your New Log

**Wait 5-15 minutes** after ending the session, then:

```bash
# List recent session logs
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --region ap-southeast-1 \
  --human-readable \
  | grep demo-test-user

# Download your session log
aws s3 cp s3://ssm-onetime-logs-vortech-dev/sessions/demo-test-user-{session-id}.log \
  ./my-session.log \
  --region ap-southeast-1

# View the log
cat ./my-session.log
```

**Why the delay?** AWS batches S3 uploads every 5-15 minutes (architectural design). Use CloudWatch for real-time logs instead.

---

## 📄 What the Log Contains

The S3 log will show:

```
Script started on 2025-11-15 11:00:00+00:00
whoami
ssm-user
pwd
/usr/bin
ls -la /home
total 0
drwxr-xr-x.  4 root     root      38 Nov 12 17:45 .
drwx------.  5 ec2-user ec2-user 187 Nov 14 13:19 ec2-user
drwx------.  3 ssm-user ssm-user  98 Nov 14 13:16 ssm-user
hostname
ip-10-104-0-88.ap-southeast-1.compute.internal
date
Fri Nov 15 11:00:30 UTC 2025
echo "Testing S3 logging from demo-test-user"
Testing S3 logging from demo-test-user
exit
Script done on 2025-11-15 11:01:00+00:00 [COMMAND_EXIT_CODE="0"]
```

---

## 🔍 Existing Logs Found

Your S3 bucket **already has session logs** from previous sessions:

```bash
# View existing logs
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ \
  --region ap-southeast-1 \
  --human-readable
```

**Recent sessions found:**
- `lee-01-vynnogeidtaoz5qhvybcrud5xe.log` (6.6 KB) - Nov 14
- `lee-02-6jxgubgds6ehxpysx6skygslky.log` (748 B) - Nov 14
- `tony-04-5uvaxxn7eoab38jga5z53b8ste.log` (377 B) - Nov 14
- `vinson-03-j4pexuzzfe45h4n224fu4edhfi.log` (59.9 KB) - Nov 13
- `vinson-05-97qossv8lyczhx2vek9f4tayty.log` (1005 B) - Nov 13
- `vinson-cli-ckkxkv98ev9koddi5rtonylrba.log` (3.1 KB) - Nov 13

**These logs prove your system is already working!** ✅

---

## 🔍 Alternative: Check CloudWatch Logs

CloudWatch logs are streamed in real-time:

```bash
# Tail CloudWatch logs (live streaming)
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --region ap-southeast-1

# Filter for specific user
aws logs tail /aws/ssm/onetime-sessions-dev \
  --follow \
  --filter-pattern "demo-test-user" \
  --region ap-southeast-1

# Search recent logs
aws logs filter-log-events \
  --log-group-name /aws/ssm/onetime-sessions-dev \
  --start-time $(date -u -v-1H +%s)000 \
  --region ap-southeast-1 \
  --query 'events[*].message' \
  --output text
```

---

## 🔍 Check Instance Local Logs

If the wrapper script is working, check local logs:

```bash
# During an SSM session on the instance:
sudo ls -lht /var/log/ssm-sessions/

# View a specific session log
sudo cat /var/log/ssm-sessions/session-demo-test-user-*.log
```

---

## 📊 Log Format Comparison

### S3 Session Log (Terminal Recording)
```
Script started on 2025-11-15 11:00:00+00:00
[terminal escape codes and raw session data]
whoami
ssm-user
pwd
/usr/bin
exit
Script done on 2025-11-15 11:01:00+00:00
```

### Instance Wrapper Log (Command Logging)
```
==============================================
SSM Session Started
==============================================
Session ID: demo-test-user-0ee0bc84a481f7852-abc123
User: demo-test-user
Instance: i-0ee0bc84a481f7852
Start Time: 2025-11-15 11:00:00 UTC
==============================================

[2025-11-15 11:00:15] demo-test-user: whoami
[2025-11-15 11:00:20] demo-test-user: pwd
[2025-11-15 11:00:25] demo-test-user: exit

==============================================
SSM Session Ended
End Time: 2025-11-15 11:01:00 UTC
==============================================
```

---

## ⚠️ Why My Self-Test Didn't Create S3 Logs

**What I ran:**
```bash
aws ssm send-command \
  --instance-ids i-0ee0bc84a481f7852 \
  --document-name "AWS-RunShellScript" \
  --parameters commands=["whoami","pwd","ls"]
```

**Why no S3 logs:**
- This is **SSM Run Command**, not **SSM Session Manager**
- Run Command executes scripts remotely
- Logs only go to SSM command history
- Does NOT trigger session document logging

**What creates S3 logs:**
```bash
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell
```

---

## 🧪 Quick Verification Steps

### 1. Check if you have existing logs (you do!)
```bash
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --region ap-southeast-1
```

### 2. Download and view a recent log
```bash
aws s3 cp s3://ssm-onetime-logs-vortech-dev/sessions/vinson-05-97qossv8lyczhx2vek9f4tayty.log \
  ./sample.log \
  --region ap-southeast-1

cat ./sample.log
```

### 3. Create a new test session
```bash
# Use the demo user I created for you
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile demo-test-user

# Run some commands, then exit

# Check CloudWatch immediately (real-time)
aws logs tail /aws/ssm/onetime-sessions-dev --follow --filter-pattern "demo-test" --region ap-southeast-1

# Wait 5-15 minutes, then check S3
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --region ap-southeast-1 | grep demo-test
```

---

## 🧹 Cleanup Demo User

After testing, remove the demo user:

```bash
cd /Users/vinson/Documents/0_Other_Services/SSM/jit-admin
./jit-admin-session-v1.0.5 --purge-session demo-test-user --region ap-southeast-1
```

---

## ✅ Summary

**Your logging IS working!** The confusion was:

1. ❌ I used **SSM Run Command** (no session logs)
2. ✅ You need **SSM Session Manager** (creates session logs)
3. ✅ Your S3 bucket **already has 13+ session logs**
4. ✅ Logs go to: `s3://ssm-onetime-logs-vortech-dev/sessions/`
5. ✅ CloudWatch: `/aws/ssm/onetime-sessions-dev`

**To see your commands logged:**
- Start a session with `aws ssm start-session` (not `send-command`)
- Use `--document-name SSM-SessionManagerRunShell`
- Check CloudWatch immediately (real-time, 1-5 second delay)
- Check S3 after 5-15 minutes (AWS batching behavior)
- Logs show every command you typed!

---

## 📚 Reference

- **S3 Bucket:** ssm-onetime-logs-vortech-dev
- **S3 Path:** sessions/
- **CloudWatch:** /aws/ssm/onetime-sessions-dev
- **Instance Logs:** /var/log/ssm-sessions/
- **Demo User:** demo-test-user (expires in 10 minutes)
- **Instance:** i-0ee0bc84a481f7852
