# Cybersecurity Threat Detection System - Kubernetes Architecture

## Architecture Overview

```
User → Amplify Frontend → ALB (HTTPS) → EKS Cluster → API Service → Inference Service → SageMaker Endpoint
                                                                                              ↓
                                                                                         S3 Bucket (data)
                                                                                         CloudWatch (logs)
```

## Layers

### Layer 1: Terraform Layer
Provisions AWS infrastructure:
- EKS Cluster (via existing 03_Installation_and_setup)
- S3 Bucket (single bucket for raw + processed data)
- SageMaker (notebook + endpoint)
- Amplify (frontend hosting)
- CloudWatch (logging)
- ALB Ingress Controller (via Helm)
- IAM Roles and Policies

### Layer 2: ACM / HTTPS (standalone, via AWS CLI)
Managed separately from Terraform so it persists across destroy cycles:
- ACM Certificate for HTTPS (`lab-loui.org` + `*.lab-loui.org`)
- Route 53 DNS validation records

### Layer 3: Kubernetes Cluster Layer
Deployed via kubectl:
- `threat-detection` namespace
- API Service (Deployment + Service) - replaces Lambda + API Gateway
- Inference Service (Deployment + Service) - calls SageMaker endpoint
- Ingress (ALB with HTTPS if ACM cert is ISSUED, HTTP-only otherwise)

## Directory Structure

```
├── terraform/              # Layer 1: Terraform infrastructure
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── s3.tf
│   ├── sagemaker.tf
│   ├── amplify.tf
│   ├── cloudwatch.tf
│   ├── iam.tf
│   └── alb-controller.tf
├── k8s/                    # Layer 3: Kubernetes manifests
│   ├── namespace.yaml
│   ├── api-service/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── inference-service/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── ingress/
│   │   └── ingress.yaml
│   └── Taskfile.yaml
├── docker/                 # Docker images
│   ├── api-service/
│   │   ├── Dockerfile
│   │   ├── app.py
│   │   └── requirements.txt
│   └── inference-service/
│       ├── Dockerfile
│       ├── app.py
│       └── requirements.txt
├── amplify_package/        # Frontend
│   ├── index.html
│   └── result.html
├── scripts/                # Automation scripts
│   ├── deploy.sh
│   └── destroy.sh
└── Taskfile.yaml           # Root taskfile
```

## Configuration

Before deploying, update these values to match your own environment:

| Value | Where to change | Description |
|---|---|---|
| `Louis` | `Taskfile.yaml`, `03_Installation_and_setup/Taskfile.yaml` | EKS cluster name |
| `kezy` | `terraform/variables.tf` | Docker Hub username |
| `lab-loui.org` | `Taskfile.yaml`, `k8s/Taskfile.yaml`, `scripts/deploy.sh`, `scripts/destroy.sh` | Your Route 53 registered domain |

## Quick Start

```bash
# Enter devbox shell
devbox shell

# Power up EKS cluster
cd 03_Installation_and_setup
t aws:03-create-cluster
t aws:03a-create-oidc
cd ..

# Step by step deployment (ensure to run each command before the next):
task terraform:init
task terraform:apply
task acm:setup #(already done)                         # One-time — persists across destroy cycles
task docker:build                      # Only needed once, or when docker/ code changes
task docker:push                       # Only needed once, or when docker/ code changes
task k8s:deploy
task data:upload
task data:preprocess
python scripts/automated_training.py
task amplify:deploy                     # Always run last

# Destroy infrastructure (ACM certificate is preserved)
task destroy

# Destroy ACM certificate (only when you no longer need HTTPS)
task acm:destroy

# Delete EKS cluster
cd 03_Installation_and_setup
t aws:06-clean-up
```

## ACM / HTTPS Management

ACM is managed independently from Terraform via CLI tasks. This avoids re-creating the certificate on every deploy cycle.

| Command | Description |
|---|---|
| `task acm:setup` | Creates ACM cert, adds DNS validation record to Route 53, waits until ISSUED |
| `task acm:status` | Shows current certificate status |
| `task acm:destroy` | Deletes the certificate and DNS validation records |

- `task k8s:deploy` auto-detects an ISSUED certificate and configures HTTPS on the ALB
- `task amplify:deploy` auto-detects an ISSUED certificate and sets the frontend API URL to HTTPS
- If no certificate is found, both tasks fall back to HTTP-only mode



## Useful Commands

```bash
# Check logs when requests hit the cluster
kubectl logs -n threat-detection -l app=api-service --tail=10

# Check what endpoint the inference pods are using
kubectl get deployment inference-service -n threat-detection -o jsonpath='{.spec.template.spec.containers[0].env}'

# Manually update inference endpoint without redeploying
kubectl set env deployment/inference-service -n threat-detection SAGEMAKER_ENDPOINT_NAME=<endpoint-name>
```

##Demo
<br>
The demo below illustrates the implementation outome on AWS console,Kubernetes UI and and front-end in amplify

https://github.com/user-attachments/assets/008b5055-92bd-4b68-bc45-6015725fc69e



