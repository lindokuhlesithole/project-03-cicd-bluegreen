# Cloud-Native CI/CD with ECS Deployments

Terraform-based CI/CD pipeline that deploys containerized applications to **Amazon ECS** with automated rolling updates via **AWS CodePipeline** and **CodeBuild**.

## Architecture

```
S3 Source → CodePipeline → CodeBuild → ECR → ECS Rolling Update
```

| Stage | Action |
|-------|--------|
| **Source** | S3 bucket triggers pipeline on new upload |
| **Build** | CodeBuild builds Docker image, pushes to ECR |
| **Deploy** | ECS rolling update with zero-downtime deployment |

## Infrastructure

| Component | Details |
|-----------|---------|
| VPC | 2 public subnets across 2 AZs (no NAT, no EIP) |
| ECS | Fargate with rolling deployment |
| ALB | Single target group with health checks |
| CI/CD | CodePipeline + CodeBuild + ECR + ECS |

## Deployment

```bash
cd terraform
terraform init
terraform apply
```

## Trigger Pipeline

```bash
cd src
zip -r app.zip app/ buildspec.yml
aws s3 cp app.zip s3://cicddeploy2026-source-471147325238/app.zip
```

## Access the App

```
http://cicddeploy2026-alb-xxx.eu-central-1.elb.amazonaws.com
```

## Author

AWS Cloud Portfolio Project
