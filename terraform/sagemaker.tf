# SageMaker Notebook Instance (retained from original architecture)
resource "aws_sagemaker_notebook_instance" "threat_detection" {
  name          = "Threat-detection-${random_string.suffix.result}"
  role_arn      = aws_iam_role.sagemaker_role.arn
  instance_type = "ml.t3.medium"

  tags = {
    Name = "ThreatDetectionNotebook"
  }
}
