# Configure AWS provider
provider "aws" {
  region = "us-east-1"
}

# Create a VPC, subnets, security groups, etc. (omitted for brevity)

resource "aws_vpc" "jenkins_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "jenkins-vpc"
  }
}

resource "aws_subnet" "jenkins_subnet" {
  vpc_id            = aws_vpc.jenkins_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "jenkins-subnet"
  }
}

resource "aws_security_group" "jenkins_security_group" {
  vpc_id = aws_vpc.jenkins_vpc.id

  # Ingress rules
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-security-group"
  }
}

# ECS Fargate Task Definition
resource "aws_ecs_task_definition" "jenkins_task" {
  family                   = "jenkins-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "jenkins-container"
    image     = "jenkins/jenkins:lts"
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
    }]
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group" = "jenkins-logs"
        "awslogs-region" = "your_aws_region"
        "awslogs-stream-prefix" = "jenkins"
      }
    }
  }])
}

# IAM role for ECS task execution
resource "aws_iam_role" "task_execution" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action    = "sts:AssumeRole"
    }]
  })
}

# IAM policy attachment for ECS task execution role
resource "aws_iam_role_policy_attachment" "task_execution_policy_attachment" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Fargate Service
resource "aws_ecs_service" "jenkins_service" {
  name            = "jenkins-service"
  task_definition = aws_ecs_task_definition.jenkins_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = ["subnet-063ea848230a3d532"]
    security_groups = ["sg-0a15e9e399c924b01"]
    assign_public_ip = true
  }
}

resource "aws_cloudwatch_metric_alarm" "jenkins_cpu_alarm" {
  alarm_name          = "jenkins-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = "jenkins-cluster"
    ServiceName = "jenkins-service"
  }

  alarm_description = "Alarm when CPU exceeds 80% on Jenkins ECS service"
  alarm_actions     = ["arn:aws:sns:us-east-1:891377400858:snsTopic"]
}

