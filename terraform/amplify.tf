# Local files for Amplify deployment
resource "local_file" "amplify_index" {
  content  = file("${path.module}/../amplify_package/index.html")
  filename = "${path.module}/../amplify_deploy/index.html"
}

resource "local_file" "amplify_result" {
  content  = file("${path.module}/../amplify_package/result.html")
  filename = "${path.module}/../amplify_deploy/result.html"
}

# Create zip file for Amplify deployment
data "archive_file" "amplify_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../amplify_deploy"
  output_path = "${path.module}/../threat-detection-app.zip"

  depends_on = [
    local_file.amplify_index,
    local_file.amplify_result
  ]
}

# AWS Amplify App
resource "aws_amplify_app" "threat_detection_app" {
  name                 = "threat-detection-k8s-${random_string.suffix.result}"
  description          = "AI-Powered Threat Detection System (Kubernetes)"
  platform             = "WEB"
  iam_service_role_arn = aws_iam_role.amplify_role.arn

  custom_rule {
    source = "/<*>"
    status = "404"
    target = "/index.html"
  }

  tags = {
    Name        = "ThreatDetectionApp"
    Environment = "Production"
  }
}

# Amplify branch for deployment
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.threat_detection_app.id
  branch_name = "main"
  framework   = "Web"
  stage       = "PRODUCTION"
}
