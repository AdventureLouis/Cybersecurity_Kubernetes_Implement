#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
K8S_DIR="$PROJECT_DIR/k8s"
DOCKER_DIR="$PROJECT_DIR/docker"
AMPLIFY_DIR="$PROJECT_DIR/amplify_package"
AMPLIFY_DEPLOY_DIR="$PROJECT_DIR/amplify_deploy"

AWS_REGION="${AWS_REGION:-us-east-1}"

echo "🚀 Deploying Cybersecurity Threat Detection System (Kubernetes)"
echo "================================================================"

# ─── Step 1: Terraform Init & Apply ───
echo ""
echo "📦 Step 1: Terraform Infrastructure"
echo "------------------------------------"
cd "$TERRAFORM_DIR"
terraform init
terraform apply -auto-approve

# Get outputs
S3_BUCKET=$(terraform output -raw s3_data_bucket)
DOCKERHUB_API_IMAGE=$(terraform output -raw dockerhub_api_image)
DOCKERHUB_INFERENCE_IMAGE=$(terraform output -raw dockerhub_inference_image)
DOCKERHUB_USERNAME=$(echo "$DOCKERHUB_API_IMAGE" | cut -d'/' -f1)
EKS_POD_ROLE_ARN=$(terraform output -raw eks_pod_role_arn)
AMPLIFY_APP_ID=$(terraform output -raw amplify_app_id)
CLUSTER_NAME=$(terraform output -raw cluster_name)

echo "✅ Terraform applied successfully"
echo "   S3 Bucket: $S3_BUCKET"
echo "   API Image: $DOCKERHUB_API_IMAGE"
echo "   Inference Image: $DOCKERHUB_INFERENCE_IMAGE"

# ─── Step 2: Build & Push Docker Images ───
echo ""
echo "🐳 Step 2: Build & Push Docker Images to Docker Hub"
echo "----------------------------------------------------"

# Login to Docker Hub
docker login

# Build and push API service
echo "Building API service..."
docker build --platform linux/amd64 -t "$DOCKERHUB_API_IMAGE" "$DOCKER_DIR/api-service/"
docker push "$DOCKERHUB_API_IMAGE"
echo "✅ API service image pushed"

# Build and push Inference service
echo "Building Inference service..."
docker build --platform linux/amd64 -t "$DOCKERHUB_INFERENCE_IMAGE" "$DOCKER_DIR/inference-service/"
docker push "$DOCKERHUB_INFERENCE_IMAGE"
echo "✅ Inference service image pushed"

# ─── Step 3: Update kubeconfig ───
echo ""
echo "☸️  Step 3: Configure kubectl"
echo "-----------------------------"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
echo "✅ kubeconfig updated"

# ─── Step 4: Deploy K8s Resources ───
echo ""
echo "☸️  Step 4: Deploy Kubernetes Resources"
echo "----------------------------------------"
cd "$K8S_DIR"

# Create namespace
kubectl apply -f namespace.yaml

# Deploy service account with IRSA
export EKS_POD_ROLE_ARN
envsubst < service-account.yaml | kubectl apply -f -

# Deploy API service
export DOCKERHUB_USERNAME
envsubst < api-service/deployment.yaml | kubectl apply -f -
kubectl apply -f api-service/service.yaml

# Deploy Inference service — auto-detect latest endpoint
if [ -z "${SAGEMAKER_ENDPOINT_NAME:-}" ]; then
    SAGEMAKER_ENDPOINT_NAME=$(aws sagemaker list-endpoints --region "$AWS_REGION" \
        --query "Endpoints[?starts_with(EndpointName,'threat-detection-endpoint') && EndpointStatus=='InService'] | sort_by(@, &CreationTime) | [-1].EndpointName" --output text 2>/dev/null || echo "")
    if [ -z "$SAGEMAKER_ENDPOINT_NAME" ] || [ "$SAGEMAKER_ENDPOINT_NAME" = "None" ]; then
        echo "⚠️  No InService SageMaker endpoint found. Using default name."
        SAGEMAKER_ENDPOINT_NAME="threat-detection-endpoint"
    else
        echo "🔍 Auto-detected SageMaker endpoint: $SAGEMAKER_ENDPOINT_NAME"
    fi
fi
export SAGEMAKER_ENDPOINT_NAME
envsubst < inference-service/deployment.yaml | kubectl apply -f -
kubectl apply -f inference-service/service.yaml

# Deploy Ingress (with or without HTTPS)
export ACM_CERTIFICATE_ARN=$(aws acm list-certificates --region "$AWS_REGION" \
    --query "CertificateSummaryList[?DomainName=='lab-loui.org' && Status=='ISSUED'].CertificateArn" --output text 2>/dev/null || echo "")
if [ -z "$ACM_CERTIFICATE_ARN" ]; then
    echo "⚠️  No ISSUED ACM certificate found. Deploying with HTTP only."
    echo "   Run 'task acm:setup' to enable HTTPS."
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: threat-detection-ingress
  namespace: threat-detection
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/load-balancer-attributes: routing.http.drop_invalid_header_fields.enabled=true
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    alb.ingress.kubernetes.io/unhealthy-threshold-count: "3"
    alb.ingress.kubernetes.io/tags: "Environment=production,App=threat-detection"
  labels:
    app: threat-detection
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /predict
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 8000
          - path: /health
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 8000
EOF
else
    echo "🔒 Deploying with HTTPS (ACM: $ACM_CERTIFICATE_ARN)"
    envsubst < ingress/ingress.yaml | kubectl apply -f -
fi

echo "✅ K8s resources deployed"

# ─── Step 5: Wait for ALB & Setup DNS ───
echo ""
echo "⏳ Step 5: Waiting for ALB to provision..."
echo "-------------------------------------------"
ALB_URL=""
for i in $(seq 1 30); do
    ALB_URL=$(kubectl get ingress -n threat-detection threat-detection-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [ -n "$ALB_URL" ]; then
        echo "✅ ALB provisioned: $ALB_URL"
        break
    fi
    echo "   Waiting... ($i/30)"
    sleep 10
done

if [ -z "$ALB_URL" ]; then
    echo "⚠️  ALB not ready yet. Check with: kubectl get ingress -n threat-detection"
    echo "   Continuing with deployment..."
    ALB_URL="PENDING"
fi

# Update api.lab-loui.org CNAME
if [ "$ALB_URL" != "PENDING" ]; then
    DOMAIN="lab-loui.org"
    ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" \
        --query 'HostedZones[0].Id' --output text | sed 's|/hostedzone/||')
    if [ -n "$ZONE_ID" ]; then
        aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch '{
          "Changes": [{
            "Action": "UPSERT",
            "ResourceRecordSet": {
              "Name": "api.'"$DOMAIN"'",
              "Type": "CNAME",
              "TTL": 300,
              "ResourceRecords": [{"Value": "'"$ALB_URL"'"}]
            }
          }]
        }' > /dev/null
        echo "✅ api.$DOMAIN → $ALB_URL"
    fi
fi

# ─── Step 6: Update & Deploy Amplify Frontend ───
echo ""
echo "🌐 Step 6: Deploy Amplify Frontend"
echo "-----------------------------------"

# Determine the API endpoint URL
ACM_CERTIFICATE_ARN=$(aws acm list-certificates --region "$AWS_REGION" \
    --query "CertificateSummaryList[?DomainName=='lab-loui.org' && Status=='ISSUED'].CertificateArn" --output text 2>/dev/null || echo "")
if [ -n "$ACM_CERTIFICATE_ARN" ] && [ "$ALB_URL" != "PENDING" ]; then
    API_BASE="https://api.lab-loui.org"
else
    API_BASE="http://$ALB_URL"
fi

# Create amplify_deploy directory
mkdir -p "$AMPLIFY_DEPLOY_DIR"

# Update index.html with the ALB endpoint
sed "s|%%ALB_ENDPOINT%%|$API_BASE|g" "$AMPLIFY_DIR/index.html" > "$AMPLIFY_DEPLOY_DIR/index.html"
cp "$AMPLIFY_DIR/result.html" "$AMPLIFY_DEPLOY_DIR/result.html"

# Create zip for Amplify deployment
cd "$AMPLIFY_DEPLOY_DIR"
zip -r "$PROJECT_DIR/threat-detection-app.zip" .

# Deploy to Amplify using manual deployment API
echo "📦 Creating Amplify deployment..."
DEPLOY_RESULT=$(aws amplify create-deployment \
    --app-id "$AMPLIFY_APP_ID" \
    --branch-name main \
    --region "$AWS_REGION" \
    --output json)

JOB_ID=$(echo "$DEPLOY_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['jobId'])")
UPLOAD_URL=$(echo "$DEPLOY_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['zipUploadUrl'])")

# Upload zip to the pre-signed URL
curl -T "$PROJECT_DIR/threat-detection-app.zip" "$UPLOAD_URL" --silent --show-error

# Start the deployment
aws amplify start-deployment \
    --app-id "$AMPLIFY_APP_ID" \
    --branch-name main \
    --job-id "$JOB_ID" \
    --region "$AWS_REGION"

echo "✅ Frontend deployed (Job ID: $JOB_ID)"

# ─── Summary ───
echo ""
echo "================================================================"
echo "🎉 Deployment Complete!"
echo "================================================================"
echo ""
echo "📍 Resources:"
echo "   ALB URL:      $API_BASE"
echo "   API Endpoint: $API_BASE/predict"
echo "   Amplify URL:  https://main.$AMPLIFY_APP_ID.amplifyapp.com"
echo "   S3 Bucket:    $S3_BUCKET"
echo ""
echo "📋 Useful Commands:"
echo "   kubectl get pods -n threat-detection"
echo "   kubectl get ingress -n threat-detection"
echo "   kubectl logs -n threat-detection -l app=api-service"
echo ""
