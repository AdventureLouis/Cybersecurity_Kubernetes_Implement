# CloudWatch Log Groups for monitoring
resource "aws_cloudwatch_log_group" "sagemaker_logs" {
  name              = "/aws/sagemaker/NotebookInstances/${aws_sagemaker_notebook_instance.threat_detection.name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "eks_api_service_logs" {
  name              = "/aws/eks/${var.cluster_name}/api-service"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "eks_inference_service_logs" {
  name              = "/aws/eks/${var.cluster_name}/inference-service"
  retention_in_days = 14
}

# CloudWatch Log Group for ALB access logs
resource "aws_cloudwatch_log_group" "alb_logs" {
  name              = "/aws/alb/threat-detection"
  retention_in_days = 14
}
