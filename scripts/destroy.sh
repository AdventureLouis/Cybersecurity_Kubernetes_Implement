#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

AWS_REGION="${AWS_REGION:-us-east-1}"

echo "🗑️  Destroying Cybersecurity Threat Detection System (Kubernetes)"
echo "================================================================="

# ─── Step 0: Delete api.lab-loui.org DNS Record ───
echo ""
echo "🌐 Step 0: Clean up DNS"
echo "------------------------"
DOMAIN="lab-loui.org"
ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" \
  --query 'HostedZones[0].Id' --output text 2>/dev/null | sed 's|/hostedzone/||')
if [ -n "$ZONE_ID" ]; then
  RECORD=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
    --query "ResourceRecordSets[?Name=='api.$DOMAIN.']" --output json 2>/dev/null)
  ALB_VALUE=$(echo "$RECORD" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r[0]['ResourceRecords'][0]['Value']) if r else exit(1)" 2>/dev/null || echo "")
  if [ -n "$ALB_VALUE" ]; then
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch '{
      "Changes": [{
        "Action": "DELETE",
        "ResourceRecordSet": {
          "Name": "api.'"$DOMAIN"'",
          "Type": "CNAME",
          "TTL": 300,
          "ResourceRecords": [{"Value": "'"$ALB_VALUE"'"}]
        }
      }]
    }' > /dev/null 2>&1
    echo "✅ api.$DOMAIN DNS record deleted"
  else
    echo "ℹ️  No api.$DOMAIN record found"
  fi
fi

# ─── Step 1: Delete K8s Resources ───
echo ""
echo "☸️  Step 1: Delete Kubernetes Resources"
echo "----------------------------------------"
kubectl delete ingress --all -n threat-detection --ignore-not-found 2>/dev/null || true

echo "⏳ Waiting for ALB to be deprovisioned..."
sleep 30

kubectl delete svc --all -n threat-detection --ignore-not-found 2>/dev/null || true
kubectl delete deployment --all -n threat-detection --ignore-not-found 2>/dev/null || true
kubectl delete sa threat-detection-sa -n threat-detection --ignore-not-found 2>/dev/null || true
kubectl delete ns threat-detection --ignore-not-found 2>/dev/null || true
echo "✅ K8s resources deleted"

# ─── Step 2: Delete SageMaker Endpoints ───
echo ""
echo "🧠 Step 2: Delete SageMaker Endpoints"
echo "--------------------------------------"
for EP in $(aws sagemaker list-endpoints --region "$AWS_REGION" --query 'Endpoints[?starts_with(EndpointName,`threat-detection-endpoint`)].EndpointName' --output text 2>/dev/null); do
    echo "   Deleting endpoint: $EP"
    EP_CONFIG=$(aws sagemaker describe-endpoint --endpoint-name "$EP" --region "$AWS_REGION" --query 'EndpointConfigName' --output text 2>/dev/null || true)
    aws sagemaker delete-endpoint --endpoint-name "$EP" --region "$AWS_REGION" 2>/dev/null || true
    if [ -n "$EP_CONFIG" ] && [ "$EP_CONFIG" != "None" ]; then
        MODEL=$(aws sagemaker describe-endpoint-config --endpoint-config-name "$EP_CONFIG" --region "$AWS_REGION" --query 'ProductionVariants[0].ModelName' --output text 2>/dev/null || true)
        aws sagemaker delete-endpoint-config --endpoint-config-name "$EP_CONFIG" --region "$AWS_REGION" 2>/dev/null || true
        if [ -n "$MODEL" ] && [ "$MODEL" != "None" ]; then
            aws sagemaker delete-model --model-name "$MODEL" --region "$AWS_REGION" 2>/dev/null || true
        fi
    fi
done
echo "✅ SageMaker resources deleted"

# ─── Step 3: Terraform Destroy ───
echo ""
echo "📦 Step 3: Terraform Destroy"
echo "----------------------------"
cd "$TERRAFORM_DIR"
terraform destroy -auto-approve
echo "✅ Terraform resources destroyed"

echo ""
echo "================================================================="
echo "🎉 Cleanup Complete!"
echo "================================================================="
echo ""
echo "Note: The EKS cluster itself was NOT deleted."
echo "To delete the EKS cluster, run:"
echo "  cd ../03_Installation_and_setup && task aws:06-clean-up"
