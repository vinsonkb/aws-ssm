while IFS=$'\t' read -r INSTANCE_ID INSTANCE_NAME; do
  echo "Deploying wrapper to: $INSTANCE_NAME ($INSTANCE_ID)"
  
  cd /Users/vinson/Documents/0_Other_Services/SSM/logging
  ./deploy-wrapper-to-instances.sh "$INSTANCE_ID"
  
  echo "✅ Done"
  echo ""
done < instances.txt