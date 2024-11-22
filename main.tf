provider "aws" {
  region = var.region
}
### STEP 1: Use Default VPC ###
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

### STEP 2: Use Default Security Group ###
data "aws_security_group" "default" {
  filter {
    name   = "group-name"
    values = ["default"]
  }

  vpc_id = data.aws_vpc.default.id
}
### STEP 1: Create ECR Repository ###
resource "aws_ecr_repository" "php_app_repo" {
  name = "php-app-repo"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.php_app_repo.repository_url
}

### STEP 2: Create ECS Cluster ###
resource "aws_ecs_cluster" "php_app_cluster" {
  name = "php-app-cluster"
}

### STEP 3: Create ECS Task Definition ###
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
}

resource "aws_ecs_task_definition" "php_task" {
  family                   = "php-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name  = "php-container"
      image = "${aws_ecr_repository.php_app_repo.repository_url}:latest"
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

### STEP 4: Create ECS Service ###
resource "aws_ecs_service" "php_service" {
  name            = "php-service"
  cluster         = aws_ecs_cluster.php_app_cluster.id
  task_definition = aws_ecs_task_definition.php_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true  # Add this line
    subnets         = data.aws_subnets.default_subnets.ids
    security_groups = [data.aws_security_group.default.id]
  }
}
### STEP 5: Create S3 Bucket ###
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "codepipeline-${random_id.bucket_suffix.hex}-${var.environment}"

  tags = {
    Name        = "CodePipeline"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "codepipeline_bucket_pab" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

### STEP 6: Define CodeBuild Project ###
resource "aws_codebuild_project" "ecr_build_project" {
  name          = "php-app-build"
  description   = "Build and push Docker image to ECR"
  service_role  = aws_iam_role.codepipeline_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.php_app_repo.repository_url
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("buildspec.yml")
  }
}

### STEP 7: CI/CD Pipeline ###
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = [
            "codepipeline.amazonaws.com",
            "codebuild.amazonaws.com"
          ]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline-full-access-policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Full S3 permissions for the CodePipeline artifact bucket
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Resource = [
          "arn:aws:s3:::codepipeline-c634a7aa-test",
          "arn:aws:s3:::codepipeline-c634a7aa-test/*"
        ]
      },
      # Full CloudWatch Logs permissions
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      # Full CodeBuild permissions
      {
        Effect = "Allow",
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds",
          "codebuild:BatchGetProjects",
          "codebuild:ListBuilds",
          "codebuild:ListBuildsForProject",
          "codebuild:ListProjects"
        ],
        Resource = "*"
      },
      # Full CodeStar Connections permissions
      {
        Effect = "Allow",
        Action = [
          "codestar-connections:UseConnection",
          "codestar-connections:GetConnection",
          "codestar-connections:ListConnections"
        ],
        Resource = "arn:aws:codestar-connections:*:*:connection/*"
      },
      # Full ECR permissions
      {
        Effect = "Allow",
        Action = [
          # "ecr:GetAuthorizationToken",
          # "ecr:BatchCheckLayerAvailability",
          # "ecr:GetDownloadUrlForLayer",
          # "ecr:BatchGetImage",
          # "ecr:InitiateLayerUpload",
          # "ecr:UploadLayerPart",
          # "ecr:CompleteLayerUpload",
          # "ecr:PutImage",
          # "ecr:CreateRepository",
          # "ecr:DeleteRepository",
          # "ecr:DescribeRepositories",
          # "ecr:ListImages",
          # "ecr:DeleteRepositoryPolicy",
          "ecr:*",
          "cloudtrail:LookupEvents"
        ],
        Resource = "*"
      },
      # Full ECS permissions
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeContainerInstances",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListClusters",
          "ecs:ListContainerInstances",
          "ecs:ListServices",
          "ecs:ListTaskDefinitions",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:StartTask",
          "ecs:StopTask",
          "ecs:UpdateService",
          "ecs:RunTask",
          "ecs:CreateCluster",
          "ecs:DeleteCluster",
          "ecs:*"
        ],
        Resource = "*"
      },
      # IAM PassRole permission
      {
        Effect = "Allow",
        Action = "iam:PassRole",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "ecs-task-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}



resource "aws_codepipeline" "php_pipeline" {
  name     = "PHPAppPipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "GitHubSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId = var.github_repo  # Example: "owner/repo"
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildAndPushToECR"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.ecr_build_project.name
      }
    }
  }
  stage {
    name = "Deploy"

    action {
      version         = "1"
      name            = "ECSDeploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["BuildOutput"]

      configuration = {
        ClusterName    = aws_ecs_cluster.php_app_cluster.name
        ServiceName    = aws_ecs_service.php_service.name
        FileName       = "imagedefinitions.json"
      }
    }
  }
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "github-connection"
  provider_type = "GitHub"
}
