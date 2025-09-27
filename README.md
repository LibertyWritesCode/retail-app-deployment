# InnovateMart EKS Deployment 
## My Journey Building This EKS Infrastructure

As a Cloud DevOps Engineer working on Project Bedrock, I designed and implemented a complete Infrastructure as Code solution to deploy InnovateMart's retail application on Amazon EKS. This README documents my approach, the challenges I encountered, and how I solved them.

## What I Built

I created an automated deployment pipeline that provisions a production-ready Kubernetes environment from scratch. My solution includes custom VPC networking, a managed EKS cluster, proper IAM security, and a complete CI/CD pipeline using GitHub Actions.

### My Architecture Decisions

When designing this infrastructure, I made several key architectural choices:

**VPC Design**: I built a custom VPC with public and private subnets across multiple Availability Zones. I placed the EKS worker nodes in private subnets for security, while keeping the load balancers in public subnets for internet access. This follows AWS security best practices.

**EKS Configuration**: I chose EKS version 1.28 for stability and configured the cluster with both public and private endpoint access. This gives me flexibility for both external access and secure internal communication.

**Node Group Strategy**: I implemented auto-scaling node groups using t3.micro instances to keep costs low while meeting the project requirements. I configured the scaling between 1-4 nodes to handle variable workloads efficiently.

**IAM Security**: I implemented least-privilege IAM roles for all components. I created separate roles for the EKS cluster, node groups, and a read-only developer user, each with only the permissions they actually need.

```
├── terraform/                 # My Infrastructure as Code
│   ├── main.tf               # Provider and backend configuration
│   ├── vpc.tf                # VPC, subnets, routing I designed
│   ├── iam.tf                # IAM roles with least privilege
│   ├── eks.tf                # EKS cluster and node configuration
│   ├── variables.tf          # Configurable parameters
│   └── outputs.tf            # Important values for other tools
├── k8s-manifests/            # Application deployment configs
│   └── retail-store/         # Retail app I containerized
├── .github/workflows/        # CI/CD pipeline I built
│   └── terraform.yml         # Automated deployment workflow
└── README.md               
```

## How I Implemented the Solution

### Setting Up the Infrastructure Foundation

I started by creating the networking foundation. In my `vpc.tf`, I defined a VPC with carefully planned CIDR blocks to avoid conflicts with other AWS services:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
```

I created both public and private subnets in each Availability Zone. The public subnets handle internet-facing load balancers, while private subnets host the worker nodes. I added specific Kubernetes tags so the AWS Load Balancer Controller can automatically discover the right subnets:

```hcl
tags = {
  "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  "kubernetes.io/role/elb" = "1"
}
```

For internet connectivity, I implemented NAT Gateways in each public subnet with dedicated Elastic IPs. This ensures high availability while allowing private subnet resources to access the internet securely.

### Building the EKS Cluster

In my `eks.tf`, I configured the cluster with specific requirements for this retail application. I chose version 1.28 for its stability and feature set:

```hcl
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }
}
```

I configured both public and private API access to give me flexibility during development while maintaining security for production workloads.

### Implementing Security with IAM

Security was a top priority, so I created granular IAM roles in my `iam.tf`. I built separate roles for different functions:

**EKS Cluster Role**: I attached only the `AmazonEKSClusterPolicy` because that's all the control plane needs.

**Node Group Role**: I attached three specific policies - `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly` - giving nodes exactly what they need to function.

**Developer User**: I created a read-only user with custom policies that allow developers to view cluster resources without making changes:

```hcl
resource "aws_iam_policy" "developer_eks_readonly" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### Creating the CI/CD Pipeline

I built my GitHub Actions workflow in `.github/workflows/terraform.yml` to automate the entire deployment process. My pipeline triggers on changes to the terraform directory, which ensures infrastructure changes are properly reviewed and deployed:

```yaml
on:
  push:
    branches: [ "main" ]
    paths: ['terraform/**']
  pull_request:
    branches: [ "main" ]
    paths: ['terraform/**']
```

My workflow follows these steps that I designed:

1. **Checkout**: Retrieves my repository code
2. **Setup Terraform**: Installs the Terraform CLI
3. **Configure AWS**: Uses GitHub Secrets I configured for authentication
4. **Initialize**: Sets up Terraform backend and downloads providers
5. **Format Check**: Validates my code formatting
6. **Plan**: Shows what changes will be made
7. **Apply**: Actually creates the infrastructure (only on main branch)

I implemented branch protection by only applying changes on the main branch, while pull requests only run plan operations for review.

### Deploying the Retail Application

I containerized the retail store application using Kubernetes manifests I wrote. My application consists of several microservices:

- **UI Service**: The React frontend that customers interact with
- **Catalog Service**: Manages product information with MySQL backend
- **Cart Service**: Handles shopping cart data using DynamoDB
- **Orders Service**: Processes orders with PostgreSQL
- **Checkout Service**: Manages payment flow with Redis caching

I configured each service with proper resource limits and health checks.
```

I used Kubernetes Services to enable communication between microservices and configured a LoadBalancer service for external access to the UI.

## Challenges I Encountered and How I Solved Them

### AWS Service Quota Limitations

During deployment, I hit several AWS service quotas that initially blocked my pipeline:

**VPC Limit**: My account had reached the default limit of 5 VPCs. I had to clean up unused VPCs from previous projects and request a quota increase through AWS Support.

**Elastic IP Limit**: I needed 2 Elastic IPs for my NAT Gateways, but my account was at the limit. I released unused EIPs and optimized my design to use fewer resources.

**Node Group Creation Failures**: I initially configured 10 t3.medium instances, which exceeded capacity in some Availability Zones. I reduced this to 2-4 nodes and added multiple instance types as fallbacks:

```hcl
instance_types = ["t3.micro", "t2.micro"]
scaling_config {
  desired_size = 2
  max_size     = 4
  min_size     = 1
}
```

### GitHub Actions Authentication Issues

My CI/CD pipeline initially failed due to authentication problems. I discovered that:

1. I needed to store AWS credentials as GitHub Secrets, not in the repository
2. The IAM user required programmatic access permissions
3. I had to ensure the AWS region in my workflow matched my Terraform configuration

I solved this by properly configuring the GitHub Secrets and updating my workflow to use the correct region (eu-west-2).

### Application Pod Failures

When I first deployed the retail application, several pods failed with CrashLoopBackOff errors. Through debugging with `kubectl describe pod`, I found:

**Health Check Issues**: Some containers had incorrect health check endpoints. I removed problematic health checks:

```bash
kubectl patch deployment assets -n retail-store-sample -p '{"spec":{"template":{"spec":{"containers":[{"name":"assets","livenessProbe":null,"readinessProbe":null}]}}}}'
```

**Resource Constraints**: With t3.micro nodes, I had limited memory and CPU. I added resource limits to all containers to ensure proper scheduling.

**Service Dependencies**: I had to ensure database services (MySQL, Redis, DynamoDB) started before application services that depend on them.

### Git Repository Management

I encountered issues with large files and exposed credentials:

**Large Files**: Terraform providers and kubectl binaries were being committed, causing GitHub to reject pushes. I added comprehensive `.gitignore` rules:

```
terraform/.terraform/
*.tfstate*
kubectl*
awscli-bundle*
```

**Credential Exposure**: Terraform state files contained sensitive information. I removed them from git tracking and added them to `.gitignore` to prevent future exposure.

## How My CI/CD Pipeline Works

My automated deployment process follows this workflow:

**Feature Development**: When I work on feature branches, my pipeline runs `terraform plan` to validate changes without applying them. This gives me and reviewers confidence that changes will work.

**Main Branch Deployment**: When I merge to main, my pipeline runs both `terraform plan` and `terraform apply`, automatically deploying the infrastructure changes.

**Security**: I never store AWS credentials in my repository. Instead, I use GitHub Secrets that are securely encrypted and only accessible to my workflows.

**Monitoring**: I can monitor deployment progress through the GitHub Actions interface, and any failures generate detailed logs I can use for troubleshooting.

## What I Learned About Production Readiness

Through this project, I gained valuable insights into production infrastructure:

**Resource Planning**: I learned to consider AWS service quotas early in design. Production environments need quota increases planned in advance.

**Cost Optimization**: I implemented auto-scaling and used appropriate instance sizes. My t3.micro nodes keep costs low while providing adequate performance for this demonstration.

**Security First**: I implemented security best practices from the start - private subnets, least privilege IAM, and no hardcoded credentials.

**Monitoring and Observability**: I configured proper tagging for resource management and cost tracking. I also set up kubectl access for ongoing monitoring and troubleshooting.

## How to Use My Infrastructure


- AWS CLI configured with appropriate permissions
- kubectl for Kubernetes management
- Git for repository operations

### GitHub Setup
1. Fork my repository
2. Add your AWS credentials to GitHub Secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
3. Push changes to trigger the deployment

### Manual Deployment
If you prefer to deploy manually:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Then configure kubectl and deploy the application:

```bash
aws eks update-kubeconfig --region eu-west-2 --name innovatemart-eks
kubectl apply -f k8s-manifests/retail-store/
```

### Developer Access

I created a read-only developer user for team access. The credentials are provided separately for security. Developers can access the cluster using:

```bash
aws eks update-kubeconfig --region eu-west-2 --name innovatemart-eks
kubectl get pods -n retail-store-sample
```

## Cost Management Strategy

I designed this infrastructure with cost optimization in mind:

**Development vs Production**: I use t3.micro instances for development, but the infrastructure scales to larger instances for production workloads.

**Auto-scaling**: My node groups automatically scale down during low usage periods.

**Resource Cleanup**: I included complete destruction commands to avoid ongoing charges:

```bash
terraform destroy -auto-approve
```


## Future Improvements

Based on my experience with this project, I would enhance it with:

**Advanced Monitoring**: Integrate CloudWatch Container Insights and Prometheus for better observability.

**Multi-Environment Support**: Create separate configurations for development, staging, and production environments.

**Database Migration**: Move from in-cluster databases to managed AWS services (RDS, ElastiCache, DynamoDB) for production use.

**Security Scanning**: Add container vulnerability scanning and policy validation to the CI/CD pipeline.

**Backup Strategy**: Implement automated backups for application data and cluster configuration.

This project demonstrates my ability to design, implement, and troubleshoot production-grade cloud infrastructure using modern DevOps practices. The challenges I encountered and solved reflect real-world scenarios that any cloud engineer faces when building scalable, secure systems.
