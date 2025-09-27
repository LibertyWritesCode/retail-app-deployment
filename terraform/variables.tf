variable "aws_region" {

  description = "AWS region"

  type = string

  default = "eu-west-2"

}

variable "cluster_name" {

  description = "EKS cluster name"

  type = string

  default = "innovatemart-eks"

}

variable "cluster_version" {

  description = "EKS cluster version"

  type = string

  default = "1.28"

}
# Trigger workflow
# Updated for CI/CD trigger
# Updated for CI/CD trigger
# Updated for CI/CD trigger
