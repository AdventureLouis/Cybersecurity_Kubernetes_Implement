output "s3_data_bucket" {
  description = "Name of the S3 bucket for all data"
  value       = aws_s3_bucket.data.id
}

output "dockerhub_api_image" {
  description = "Docker Hub image for API service"
  value       = "${var.dockerhub_username}/threat-detection-api:latest"
}

output "dockerhub_inference_image" {
  description = "Docker Hub image for Inference service"
  value       = "${var.dockerhub_username}/threat-detection-inference:latest"
}

output "sagemaker_notebook_instance_name" {
  description = "Name of the SageMaker notebook instance"
  value       = aws_sagemaker_notebook_instance.threat_detection.name
}

output "sagemaker_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_role.arn
}

output "eks_pod_role_arn" {
  description = "ARN of the EKS pod IAM role (for IRSA)"
  value       = aws_iam_role.eks_pod_role.arn
}

output "amplify_app_id" {
  description = "Amplify app ID"
  value       = aws_amplify_app.threat_detection_app.id
}

output "amplify_app_url" {
  description = "URL of the Amplify app"
  value       = "https://main.${aws_amplify_app.threat_detection_app.id}.amplifyapp.com"
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "setup_instructions" {
  description = "Setup instructions"
  value       = <<-EOT

    🚀 Cybersecurity Threat Detection System (Kubernetes) Deployed!

    📋 Next Steps:
    1. Build and push Docker images:
       task docker:build
       task docker:push

    2. Deploy K8s manifests:
       task k8s:deploy

    3. Get ALB URL:
       kubectl get ingress -n threat-detection

    4. Update Amplify frontend with ALB URL:
       task amplify:deploy

    📍 Resources:
    - S3 Bucket: ${aws_s3_bucket.data.id}
    - API Image: ${var.dockerhub_username}/threat-detection-api:latest
    - Inference Image: ${var.dockerhub_username}/threat-detection-inference:latest
    - Amplify: https://main.${aws_amplify_app.threat_detection_app.id}.amplifyapp.com

  EOT
}
