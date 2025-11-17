#!/bin/bash

# Script to view SSM session logs from various sources

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  SSM Session Logs Viewer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Menu
echo "Select log source:"
echo "1. CloudWatch Logs (live/complete sessions)"
echo "2. S3 Text Logs (commands + output)"
echo "3. S3 Asciinema Recordings (playback)"
echo "4. S3 Command History"
echo "5. DynamoDB Session Status"
echo "6. Audit Logs (from EC2 instance)"
echo ""
read -p "Enter choice (1-6): " CHOICE

case $CHOICE in
  1)
    echo -e "${YELLOW}CloudWatch Logs${NC}"
    echo ""
    echo "Recent log streams:"
    aws logs describe-log-streams \
      --log-group-name /aws/ssm/onetime-sessions-dev \
      --order-by LastEventTime \
      --descending \
      --max-items 10 \
      --region ap-southeast-1 \
      --query 'logStreams[*].[logStreamName,lastEventTime]' \
      --output table

    echo ""
    read -p "Enter log stream name (or press Enter to tail all): " LOG_STREAM

    if [ -z "$LOG_STREAM" ]; then
      echo -e "${GREEN}Tailing all logs...${NC}"
      aws logs tail /aws/ssm/onetime-sessions-dev --follow --region ap-southeast-1
    else
      echo -e "${GREEN}Viewing $LOG_STREAM${NC}"
      aws logs tail /aws/ssm/onetime-sessions-dev --log-stream-names "$LOG_STREAM" --follow --region ap-southeast-1
    fi
    ;;

  2)
    echo -e "${YELLOW}S3 Text Logs (Commands + Output)${NC}"
    echo ""
    echo "Listing recent text logs..."
    aws s3 ls s3://ssm-onetime-logs-vortech-dev/text-logs/ --recursive --human-readable --summarize --region ap-southeast-1 | tail -20

    echo ""
    read -p "Enter S3 path to view (e.g., text-logs/i-xxx/session-xxx.log): " S3_PATH

    if [ ! -z "$S3_PATH" ]; then
      echo -e "${GREEN}Downloading and viewing...${NC}"
      aws s3 cp "s3://ssm-onetime-logs-vortech-dev/$S3_PATH" - --region ap-southeast-1 | less
    fi
    ;;

  3)
    echo -e "${YELLOW}S3 Asciinema Recordings${NC}"
    echo ""
    echo "Listing recent recordings..."
    aws s3 ls s3://ssm-onetime-logs-vortech-dev/recordings/ --recursive --human-readable --summarize --region ap-southeast-1 | tail -20

    echo ""
    read -p "Enter S3 path to download (e.g., recordings/i-xxx/session-xxx.cast): " S3_PATH

    if [ ! -z "$S3_PATH" ]; then
      LOCAL_FILE="/tmp/$(basename $S3_PATH)"
      echo -e "${GREEN}Downloading...${NC}"
      aws s3 cp "s3://ssm-onetime-logs-vortech-dev/$S3_PATH" "$LOCAL_FILE" --region ap-southeast-1

      echo ""
      echo "To play the recording, run:"
      echo "  asciinema play $LOCAL_FILE"
      echo ""
      read -p "Play now? (y/n): " PLAY_NOW

      if [ "$PLAY_NOW" == "y" ]; then
        asciinema play "$LOCAL_FILE"
      fi
    fi
    ;;

  4)
    echo -e "${YELLOW}S3 Command History${NC}"
    echo ""
    echo "Listing recent command logs..."
    aws s3 ls s3://ssm-onetime-logs-vortech-dev/commands/ --recursive --human-readable --summarize --region ap-southeast-1 | tail -20

    echo ""
    read -p "Enter S3 path to view (e.g., commands/i-xxx/session-xxx-commands.txt): " S3_PATH

    if [ ! -z "$S3_PATH" ]; then
      echo -e "${GREEN}Viewing commands...${NC}"
      aws s3 cp "s3://ssm-onetime-logs-vortech-dev/$S3_PATH" - --region ap-southeast-1 | less
    fi
    ;;

  5)
    echo -e "${YELLOW}DynamoDB Session Status${NC}"
    echo ""
    echo "Recent sessions:"
    aws dynamodb scan \
      --table-name ssm-onetime-sessions-dev \
      --region ap-southeast-1 \
      --max-items 10 \
      --query 'Items[*].[token.S,user_id.S,status.S,created_at.N,ssm_session_id.S]' \
      --output table

    echo ""
    read -p "Enter token to view details: " TOKEN

    if [ ! -z "$TOKEN" ]; then
      aws dynamodb get-item \
        --table-name ssm-onetime-sessions-dev \
        --key "{\"token\":{\"S\":\"$TOKEN\"}}" \
        --region ap-southeast-1 \
        --output json | jq .
    fi
    ;;

  6)
    echo -e "${YELLOW}Audit Logs (requires SSM access to instance)${NC}"
    echo ""

    # List instances
    echo "Fetching available instances..."
    INSTANCES=$(aws ec2 describe-instances \
      --filters "Name=instance-state-name,Values=running" \
      --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
      --output text \
      --region ap-southeast-1)

    echo "Available instances:"
    echo "$INSTANCES" | nl

    echo ""
    read -p "Enter instance number: " INSTANCE_NUM
    INSTANCE_ID=$(echo "$INSTANCES" | sed -n "${INSTANCE_NUM}p" | awk '{print $1}')

    if [ ! -z "$INSTANCE_ID" ]; then
      echo -e "${GREEN}Fetching audit logs from $INSTANCE_ID${NC}"

      aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["sudo ausearch -k ssm_commands -i | tail -100"]' \
        --region ap-southeast-1 \
        --output text \
        --query 'Command.CommandId' > /tmp/cmd_id.txt

      COMMAND_ID=$(cat /tmp/cmd_id.txt)
      echo "Command ID: $COMMAND_ID"
      echo "Waiting for results..."
      sleep 5

      aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region ap-southeast-1 \
        --query 'StandardOutputContent' \
        --output text
    fi
    ;;

  *)
    echo -e "${RED}Invalid choice${NC}"
    exit 1
    ;;
esac
