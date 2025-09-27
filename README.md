# InnovateMart EKS Deployment - Project Bedrock

## Project Overview
This project deploys the InnovateMart retail store application on Amazon EKS using Infrastructure as Code principles.

## Architecture
- **VPC**: Custom VPC with public and private subnets across 2 AZs
- **EKS Cluster**: Managed Kubernetes cluster version 1.28
- **Node Group**: t3.medium instances with auto-scaling (1-4 nodes)
- **Application**: Retail store microservices with in-cluster dependencies

## Prerequisites
- AWS CLI configured
- kubectl installed
- Terraform >= 1.0
- Git

## Deployment Instructions

### 1. Clone Repository
```bash
git clone <>
cd innovatemart-eks
# Testing pipeline after credential cleanup
