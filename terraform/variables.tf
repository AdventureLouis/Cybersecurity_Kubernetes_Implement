variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name (must match the cluster created in 03_Installation_and_setup)"
  type        = string
  default     = "Louis"
}

variable "dockerhub_username" {
  description = "Docker Hub username"
  type        = string
  default     = "kezy"
}
