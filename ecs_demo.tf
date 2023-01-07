terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "ecs_vpc" {
  cidr_block       = "10.1.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "FirstSubnet" {
  vpc_id     = aws_vpc.ecs_vpc.id
  cidr_block = "10.1.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "First subnet"
  }
}

resource "aws_subnet" "SecondSubnet" {
  vpc_id     = aws_vpc.ecs_vpc.id
  cidr_block = "10.1.2.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "Second subnet"
  }
}

resource "aws_security_group" "ecs_sec_group" {
  name        = "ecs_sec_group"
  description = "ecs_sec_group"
  vpc_id      = aws_vpc.ecs_vpc.id

  tags = {
    Name = "ecs security group"
  }
}

resource "aws_security_group_rule" "sgrule1" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.ecs_sec_group.id
}

resource "aws_security_group_rule" "sgrule2" {
  type              = "ingress"
  cidr_blocks = [
                  "0.0.0.0/0"
                ]
  from_port = 22
  ipv6_cidr_blocks = ["::/0"]
  protocol = "tcp"
  to_port = 22
  security_group_id = aws_security_group.ecs_sec_group.id
}

resource "aws_security_group_rule" "sgrule3" {
  type              = "egress"
  from_port        = 0
  to_port          = 0
  protocol         = "-1"
  cidr_blocks      = ["0.0.0.0/0"]
  ipv6_cidr_blocks = ["::/0"]
  security_group_id = aws_security_group.ecs_sec_group.id
}
resource "aws_internet_gateway" "ecs_gateway" {
  vpc_id = aws_vpc.ecs_vpc.id

  tags = {
    Name = "ecs_gateway"
  }
}
resource "aws_route_table" "ecs_route_table" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ecs_gateway.id
  }


  tags = {
    Name = "ecs route table"
  }
}
resource "aws_main_route_table_association" "a" {
  vpc_id         = aws_vpc.ecs_vpc.id
  route_table_id = aws_route_table.ecs_route_table.id
}


resource "aws_ecs_cluster" "terraform_ecs_cluster" {
  name = "terraform_ecs_cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_network_interface" "first_network_interface" {
  subnet_id   = aws_subnet.FirstSubnet.id

  tags = {
    Name = "first_network_interface"
  }
}

resource "aws_network_interface" "second_network_interface" {
  subnet_id   = aws_subnet.SecondSubnet.id


  tags = {
    Name = "second_network_interface"
  }
}

resource "aws_iam_role" "ec2-ecs-role" {
  name = "ec2-ecs-role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    tag-key = "tag-value"
  }
}
resource "aws_iam_role_policy_attachment" "sto-readonly-role-policy-attach" {
  role       = aws_iam_role.ec2-ecs-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_instance_profile" "ec2-ecs-profile" {
  name = "ec2-ecs-profile_name"
  role = aws_iam_role.ec2-ecs-role.name
}

resource "aws_instance" "first_ec2" {
  ami           = "ami-0cca134ec43cf708f" # Ubuntu 20.04 LTS // us-east-1
  instance_type = "t2.micro"
  associate_public_ip_address = "true"
  subnet_id     =  aws_subnet.FirstSubnet.id
  availability_zone = "ap-south-1a"
  iam_instance_profile = aws_iam_instance_profile.ec2-ecs-profile.name
  vpc_security_group_ids = [aws_security_group.ecs_sec_group.id]

   tags = {
    Name = "first_ec2"
  }

  user_data       = <<-EOF
              #!/bin/bash
              sudo mkdir /etc/ecs/
              sudo touch /etc/ecs/ecs.config
              sudo chmod 777 /etc/ecs/ecs.config
              sudo echo ECS_CLUSTER=terraform_ecs_cluster >> /etc/ecs/ecs.config
              sudo amazon-linux-extras install ecs -y
              sudo service docker start
              sudo service ecs start
              EOF
}

resource "aws_instance" "second_ec2" {
  ami           = "ami-0cca134ec43cf708f" # Ubuntu 20.04 LTS // us-east-1
  instance_type = "t2.micro"
  associate_public_ip_address = "true"
  subnet_id     =  aws_subnet.SecondSubnet.id
  availability_zone = "ap-south-1b"
  iam_instance_profile = aws_iam_instance_profile.ec2-ecs-profile.name
  vpc_security_group_ids = [aws_security_group.ecs_sec_group.id]
   tags = {
    Name = "second_ec2"
  }

 user_data       = <<-EOF
              #!/bin/bash
              sudo mkdir /etc/ecs/
              sudo touch /etc/ecs/ecs.config
              sudo chmod 777 /etc/ecs/ecs.config
              sudo echo ECS_CLUSTER=terraform_ecs_cluster >> /etc/ecs/ecs.config
              sudo amazon-linux-extras install ecs -y
              sudo service docker start
              sudo service ecs start
              EOF
}

resource "aws_ecs_task_definition" "tf_ecs_task_def" {
  family = "tf_ecs_task_def_family"

  container_definitions = <<DEFINITION
[
  {
    "cpu": 128,
    "essential": true,
    "image": "kodekloud/ecs-project1:latest",
    "memory": 128,
    "memoryReservation": 64,
    "name": "ecs-project1"
  }
]
DEFINITION
}

resource "aws_ecs_service" "tf_ecs_service" {
  name          = "tf_ecs_service"
  cluster       = aws_ecs_cluster.terraform_ecs_cluster.id
  desired_count = 2

  # Track the latest ACTIVE revision
  task_definition = aws_ecs_task_definition.tf_ecs_task_def.arn
}
