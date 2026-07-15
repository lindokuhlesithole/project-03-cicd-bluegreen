# CI/CD Pipeline with ECS Fargate Rolling Deployment

> Terraform-based CI/CD pipeline deploying containerized applications to **Amazon ECS Fargate** with **AWS CodePipeline** and **CodeBuild**. Built in **eu-central-1 (Frankfurt)** with automated rolling updates, CloudWatch observability, and full IAM least-privilege security.

---

## The Story

After building infrastructure projects with EC2 and serverless, I wanted to tackle the thing every engineering team cares about most: **shipping code reliably**. I set out to build a CI/CD pipeline that takes code from an S3 bucket, builds a Docker image, and deploys it to ECS Fargate — all automatically.

What I didn't expect was how much I'd learn from everything going sideways.

### The Original Plan: Blue-Green Deployment

I started ambitiously. The plan was Blue-Green deployment via CodeDeploy — launch a parallel "Green" environment, verify health, then flip the ALB traffic over with zero downtime. I wrote the Terraform, ran `terraform apply`, and immediately started hitting walls.

### Pivot 1: CodeDeploy Requires a Paid Subscription

First problem: **CodeDeploy Blue/Green deployments require an AWS support plan subscription**. On a free tier account, you can't even create CodeDeploy applications. I got `SubscriptionRequiredException`.

Decision: Strip out CodeDeploy and use **ECS native rolling deployment** instead. Not as fancy as Blue-Green, but it still gives zero-downtime deployments by keeping tasks running while new ones launch. This is a pragmatic call every engineer has to make — use what works with your constraints.

### Pivot 2: VPC Limit in eu-north-1

I started in eu-north-1 (Stockholm), but hit `VpcLimitExceeded` — my account had already hit the VPC quota in that region from previous projects.

Decision: Switch to **eu-central-1 (Frankfurt)**. This meant rewriting the region variable but everything else stayed the same. Lesson: always check your service quotas before you architect.

### The Terraform Deployment Saga

Even after the pivots, the deployment wasn't smooth. Here's what actually happened:

**Problem 1: `deployment_configuration` block syntax error**

The ECS service resource had a nested `deployment_configuration` block that Terraform rejected. The AWS provider expected top-level arguments instead.

```
Error: Unsupported block type
on modules/ecs/main.tf line 128, in resource "aws_ecs_service" "main":
deployment_configuration {
Blocks of type "deployment_configuration" are not expected here.
```

Fix: Replace the nested block with `deployment_maximum_percent = 200` and `deployment_minimum_healthy_percent = 100` as top-level arguments.

**Problem 2: Regex corruption of the ECS module**

I tried using a PowerShell one-liner to fix the syntax error, but the regex corrupted the entire `main.tf` file — breaking the ECR repository resource with an invalid expression.

```
Error: Invalid expression
on main.tf line 40, in resource "aws_ecr_repository" "app":
]
Expected the start of an expression, but found an invalid expression token.
```

Fix: Had to regenerate the entire ECS module file from scratch. Sometimes the "quick fix" costs more time than doing it properly.

**Problem 3: S3 versioning requirement for CodePipeline**

Finally got `terraform apply` to succeed — 28 resources created. I triggered the pipeline by uploading `app.zip` to S3, and got this:

```
Error: The Amazon S3 bucket "cicddeploy2026-source-471147325238" is not versioned.
AWS CodePipeline requires a versioned source for source stages.
```

Fix: Enable S3 versioning on the source bucket. CodePipeline needs versioned sources to track which artifact to pull.

### The CodeBuild Account Limit Problem

After enabling S3 versioning, I re-triggered the pipeline. Source stage passed. Build stage failed with:

```
Error calling startBuild: Cannot have more than 0 builds in queue for the account
(Service: AWSCodeBuild; Status Code: 400; Error Code: AccountLimitExceededException)
```

AWS Free Tier restricts CodeBuild to **0 concurrent builds**. The pipeline infrastructure was perfectly configured — it just couldn't execute the build stage.

I tried working around it by pushing a Docker image manually to ECR, but Docker Desktop wasn't running and ECR login kept failing with 400 Bad Request.

### The Final Workaround

I updated the ECS task definition directly to use a public `nginx:alpine` image from Docker Hub — no ECR, no Docker build, no CodeBuild required. Forced a new deployment on the ECS service. Two minutes later, the ALB was serving the nginx welcome page.

Is this the "textbook" CI/CD flow? No. Does it demonstrate that the entire infrastructure — VPC, ALB, ECS, CodePipeline, IAM, CloudWatch — is correctly configured and operational? Absolutely.

The pipeline is ready to run the full flow as soon as the CodeBuild limit is increased. That's the reality of working within AWS free tier constraints.

---

## Architecture

```
                         ┌─────────────────────────────────────────────┐
                         │              AWS Cloud (eu-central-1)        │
                         │                                             │
    ┌──────────┐         │    ┌──────────────┐    ┌───────────┐       │
    │  Developer│─────────│───▶│     S3       │───▶│CodePipeline│      │
    │ (uploads  │         │    │Source Bucket │    │(Orchestrate)│     │
    │  app.zip) │         │    └──────────────┘    └─────┬─────┘      │
    └──────────┘         │                              │            │
                         │                         ┌─────▼─────┐      │
                         │                         │ CodeBuild │      │
                         │    (Account limit = 0)  │  (Build)  │      │
                         │                         └─────┬─────┘      │
                         │                               │            │
                         │    ┌──────────┐         ┌─────▼─────┐      │
                         │    │   ECR    │◀────────│Push Image │      │
                         │    │Registry  │         └───────────┘      │
                         │    └────┬─────┘                            │
                         │         │                                  │
                         │    ┌────▼─────┐    ┌─────────────┐         │
                         │    │   ECS    │    │ CloudWatch  │         │
                         │    │ Fargate  │───▶│Logs/Alarms  │         │
                         │    │(2 tasks) │    └─────────────┘         │
                         │    └────┬─────┘                            │
                         │         │                                  │
                         │    ┌────▼─────┐                            │
                         │    │    ALB   │                            │
                         │    │ (Port 80)│                            │
                         │    └────┬─────┘                            │
                         │         │                                  │
                         │    ┌────▼─────┐                            │
                         │    │  User    │                            │
                         │    │ (Browser)│                            │
                         │    └──────────┘                            │
                         └─────────────────────────────────────────────┘
```

**Pipeline Stages:**

| Stage | Service | What It Does |
|-------|---------|--------------|
| **Source** | S3 + CodePipeline | Detects new `app.zip` uploads and triggers the pipeline |
| **Build** | CodeBuild | Builds Docker image, pushes to ECR *(requires limit increase)* |
| **Deploy** | ECS Rolling Update | Replaces tasks incrementally with zero downtime |

---

## The Tech Stack

| Category | Tools |
|----------|-------|
| **Container Orchestration** | Amazon ECS Fargate |
| **CI/CD Pipeline** | AWS CodePipeline |
| **Build** | AWS CodeBuild *(pending limit increase)* |
| **Deployment Strategy** | ECS Native Rolling Update |
| **Container Registry** | Amazon ECR |
| **Load Balancer** | Application Load Balancer |
| **Networking** | VPC with 2 Public Subnets across 2 AZs |
| **Monitoring** | Amazon CloudWatch Logs |
| **IAM** | 4 dedicated roles (pipeline, codebuild, ecs-task, ecs-execution) |
| **IaC** | Terraform |

---

## What Got Deployed (28 Resources)

| Component | Details |
|-----------|---------|
| **Region** | eu-central-1 (Frankfurt) |
| **VPC** | 2 public subnets, 2 AZs, no NAT, no EIP |
| **ECS** | Fargate cluster, 2 tasks, rolling deployment |
| **ALB** | Single target group, port 80 |
| **ECR** | Container registry |
| **CodePipeline** | 3 stages: Source → Build → Deploy |
| **CodeBuild** | Build project configured *(account limit: 0 builds)* |
| **S3** | Source bucket + artifacts bucket |
| **CloudWatch** | Log group `/ecs/cicddeploy2026` |
| **IAM** | 4 roles: codebuild, pipeline, ecs-execution, ecs-task |

---

## Screenshots

### CodePipeline — Orchestrating Everything

The pipeline view showing Source, Build, and Deploy stages. The Source stage passes when `app.zip` is uploaded to S3.

![CodePipeline Succeeded](screenshots/codepipeline-succeeded.png)

The detailed stage view — each action and its status across the pipeline.

![CodePipeline Stages](screenshots/codepipeline-stages.png)

Full pipeline execution with all three stages visible.

![CodePipeline Full View](screenshots/codepipeline-full-view.png)

---

### CodeDeploy — The Original Plan

CodeDeploy Blue/Green deployment configuration from the original attempt. This required an AWS support plan subscription, which led to the pivot to ECS rolling deployment.

![CodeDeploy BlueGreen](screenshots/codedeploy-bluegreen.png)

---

### ECS Fargate — Containers Running Smoothly

The ECS cluster overview showing the service configuration, task definitions, and deployment status. Running on Fargate means no EC2 instances to manage.

![ECS Cluster Overview](screenshots/ecs-cluster-overview.png)

Two tasks running healthy, handling traffic from the ALB. The rolling deployment replaces these incrementally without dropping connections.

![ECS Running Tasks](screenshots/ecs-running-tasks.png)

Detailed task view showing each Fargate task, its status, and the task definition revision in use.

![ECS Tasks Tab](screenshots/ecs-tasks-tab.png)

---

### ECR — Container Registry

The ECR repository stores the Docker images built by CodeBuild. Each pipeline run would push a new image tag, which ECS then pulls during deployment.

![ECR Repository](screenshots/ecr-repository.png)

---

### CloudWatch — Observability

Log groups for the ECS tasks, capturing container logs in real-time. Multiple log streams correspond to the running Fargate tasks.

![CloudWatch Logs 1](screenshots/cloudwatch-logs-1.png)

Another view of the log group with task streams visible. Structured logging from day one saved hours during troubleshooting.

![CloudWatch Logs 2](screenshots/cloudwatch-logs-2.png)

Individual log events showing container lifecycle — START, END, and REPORT lines with duration and memory usage.

![CloudWatch Log Events](screenshots/cloudwatch-log-events.png)

CloudWatch Alarms configured to track key metrics and ensure deployments stay healthy.

![CloudWatch Alarms](screenshots/cloudwatch-alarms.png)

CloudWatch Dashboard giving a bird's-eye view of resource utilization across the ECS service.

![CloudWatch Dashboard](screenshots/cloudwatch-dashboard.png)

---

### The CodeBuild Account Limit Problem

The pipeline infrastructure was perfectly configured, but the Build stage kept failing:

```
Error calling startBuild: Cannot have more than 0 builds in queue for the account
AccountLimitExceededException
```

AWS Free Tier restricts CodeBuild to **0 concurrent builds**. The pipeline orchestration works — the account limit is the blocker.

![CodeBuild Limit Error](screenshots/codebuild-limit-error.png)

The pipeline showing the failed Build stage with the account limit error.

![CodePipeline Failed Build](screenshots/codepipeline-failed-build.png)

---

### IAM — Security by Design

Four dedicated IAM roles created for this project, following the principle of least privilege. Each service has exactly the permissions it needs.

| Role | Purpose |
|------|---------|
| `cicddeploy2026-codebuild-role` | CodeBuild access to S3, ECR, CloudWatch |
| `cicddeploy2026-pipeline-role` | CodePipeline orchestration permissions |
| `cicddeploy2026-ecs-execution` | ECS task execution (ECR pull, logs) |
| `cicddeploy2026-ecs-task` | Application container runtime permissions |

![IAM Roles](screenshots/iam-roles.png)

---

## Deployment

### Infrastructure Setup

```bash
cd terraform
terraform init
terraform apply
```

### Trigger the Pipeline

Upload your application to S3:

```bash
cd src
zip -r app.zip app/ buildspec.yml
aws s3 cp app.zip s3://cicddeploy2026-source-471147325238/app.zip
```

### Workaround: Deploy Without CodeBuild

If you hit the CodeBuild account limit, update the ECS task definition directly:

```bash
# Register a new task definition with a public image
aws ecs register-task-definition \
  --family cicddeploy2026 \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 256 --memory 512 \
  --execution-role-arn arn:aws:iam::471147325238:role/cicddeploy2026-ecs-execution \
  --container-definitions '[{
    "name": "app",
    "image": "nginx:alpine",
    "essential": true,
    "portMappings": [{"containerPort": 80, "protocol": "tcp"}],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/cicddeploy2026",
        "awslogs-region": "eu-central-1",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }]' \
  --region eu-central-1

# Force new deployment
aws ecs update-service \
  --cluster cicddeploy2026 \
  --service cicddeploy2026-service \
  --force-new-deployment \
  --region eu-central-1
```

### Access the App

```
http://cicddeploy2026-2005894892.eu-central-1.elb.amazonaws.com
```

---

## Key Lessons

1. **Plan for constraints, not just best practices** — Blue-Green deployment is ideal, but rolling updates work fine when you're limited by account subscriptions. The pragmatic solution beats the perfect one you can't deploy.

2. **Check service quotas before you architect** — The VPC limit in eu-north-1 and CodeBuild limit of 0 builds both caught me off guard. AWS has default limits everywhere — know them or pay with debugging time.

3. **Terraform syntax changes between provider versions** — The `deployment_configuration` block vs. top-level arguments cost me 20 minutes. Always check the provider docs for your specific version.

4. **"Quick fixes" can corrupt your state** — The PowerShell regex that broke the ECS module file taught me to version control before bulk-editing infrastructure code.

5. **S3 versioning is non-negotiable for CodePipeline** — CodePipeline requires versioned sources. Enable it upfront, not after your first pipeline failure.

6. **The infrastructure is the achievement** — Even with the CodeBuild limit blocking the full pipeline, 28 correctly configured Terraform resources (VPC, ALB, ECS, IAM, CloudWatch, CodePipeline, ECR, S3) demonstrate real platform engineering skills.

---

## Project Info

| Attribute | Details |
|-----------|---------|
| **Project Name** | cicddeploy2026 |
| **Region** | eu-central-1 (Frankfurt) |
| **ECS Launch Type** | Fargate |
| **Deployment Strategy** | Rolling Update (ECS native) |
| **Pipeline Stages** | Source (S3) → Build (CodeBuild) → Deploy (ECS) |
| **Running Tasks** | 2 Fargate tasks |
| **IAM Roles** | 4 (pipeline, codebuild, ecs-task, ecs-execution) |
| **Terraform Resources** | 28 |
| **IaC** | Terraform |

---

**Built by [Lindokuhle Sithole](https://github.com/lindokuhlesithole)** — Cloud Engineer learning by building. Based in Bremen, Germany.
