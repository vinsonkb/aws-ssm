# Quick Commands Reference

## ADMIN Commands

### Create New User with Setup Script
```bash
# New developer (30 min access)
./jit-admin-session-v1.0.5 -u tony-04 -i i-0ee0bc84a481f7852 -d 30 \
  --new-user --create-keys --output-script setup-tony-04.sh

# Short test access (3 min)
./jit-admin-session-v1.0.5 -u tony-06 -i i-0ee0bc84a481f7852 -d 3 \
  --new-user --create-keys --output-script setup-tony-06.sh

# Extended access (60 min)
./jit-admin-session-v1.0.5 -u tony-04 -i i-0ee0bc84a481f7852 -d 60 \
  --new-user --create-keys --output-script setup-tony-04.sh
```

### Renew Existing User Access
```bash
# Renew for 30 min (wait 10 seconds for IAM propagation after)
./jit-admin-session-v1.0.5 -u tony-04 -i i-0ee0bc84a481f7852 -d 30 --purge-existing

# Renew for 60 min
./jit-admin-session-v1.0.5 -u tony-04 -i i-0ee0bc84a481f7852 -d 60 --purge-existing
```

### Purge Session and Cleanup
```bash
# Remove all access, policies, and keys
./jit-admin-session-v1.0.5 --purge-session tony-04
```

## USER Commands

### First Time Setup
```bash
# Run the setup script provided by admin
bash setup-tony-04.sh
```

### Reconnect (Script Reusable!)
```bash
# Use the same script to reconnect anytime within access window
bash setup-tony-04.sh
```

### Manual Connection
```bash
aws ssm start-session \
  --target i-0ee0bc84a481f7852 \
  --document-name SSM-SessionManagerRunShell \
  --region ap-southeast-1 \
  --profile tony-04
```

## Check Logs

### CloudWatch (Real-time)
```bash
aws logs tail /aws/ssm/onetime-sessions-dev --follow --filter-pattern "tony-04" --region ap-southeast-1
```

### S3 (5-15 min delay)
```bash
aws s3 ls s3://ssm-onetime-logs-vortech-dev/sessions/ --region ap-southeast-1 | grep tony-04
```

## Notes
- **Script Version:** v1.0.5 (current)
- **Instance:** i-0ee0bc84a481f7852
- **Region:** ap-southeast-1
- **Setup scripts are reusable** - keep them for reconnecting!
- **IAM propagation:** Wait 10 seconds after `--purge-existing` before reconnecting