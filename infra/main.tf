terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "vpc_id" {}
variable "subnet_id" {}
variable "ec2_key_name" {}
variable "region" {}

# Fetch latest Amazon Linux 2 AMI
data "aws_ssm_parameter" "latest_amzn2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# S3 Buckets
resource "aws_s3_bucket" "logs" {
  bucket = "sports-highlights-logs-${random_id.bucket_suffix.hex}"
  tags   = { Name = "sports-highlights-logs" }
}

resource "aws_s3_bucket" "metadata" {
  bucket = "sports-highlights-metadata-${random_id.bucket_suffix.hex}"
  tags   = { Name = "sports-highlights-metadata" }
}

resource "aws_s3_bucket" "processed" {
  bucket = "sports-highlights-processed-${random_id.bucket_suffix.hex}"
  tags   = { Name = "sports-highlights-processed" }
}

resource "aws_s3_bucket" "videos" {
  bucket = "sports-highlights-videos-${random_id.bucket_suffix.hex}"
  tags   = { Name = "sports-highlights-videos" }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Security Group
resource "aws_security_group" "pipeline_sg" {
  name        = "sports-pipeline-sg"
  description = "Security group for pipeline EC2"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sports-pipeline-sg" }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "sports_pipeline_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ec2_policy" {
  name        = "sports_pipeline_ec2_policy"
  description = "Policy for pipeline EC2"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*", "cloudwatch:*", "ssm:*", "ec2:Describe*"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "sports_pipeline_profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance
resource "aws_instance" "pipeline_instance" {
  ami                    = data.aws_ssm_parameter.latest_amzn2_ami.value
  instance_type          = "t3.micro"
  key_name               = var.ec2_key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.pipeline_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = { Name = "pipeline-ec2" }
}

# Outputs
output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.pipeline_instance.public_ip
}

output "logs_bucket"      { value = aws_s3_bucket.logs.bucket }
output "metadata_bucket"  { value = aws_s3_bucket.metadata.bucket }
output "processed_bucket" { value = aws_s3_bucket.processed.bucket }
output "videos_bucket"    { value = aws_s3_bucket.videos.bucket }
