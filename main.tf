#-------------
# Test Task DevOps Geniusse
#-------------


provider "aws" {
  region = "eu-central-1"
}

data "aws_avialability_zones" "available" {}
data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

#Create new secrity group
resourse "aws_security_group" "web_server" {
  name = "Security Group"

  dynamic "ingress" {
    for_each = ["80", "443"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_prot     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "Security Group"
    Owner = "You"
  }
}
#Create webserver
resource "aws_launch_configuration" "web_server" {
  name_prefix     = "WebServer-Test-Task-WB-"
  image_id        = data.aws.ami.lates_amazon_linux.image_id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web_server]
  user_data       = file("user_data.sh")

  #Create lifecycle forn there isn't downtime server
  lifecycle {
    create_before_destroy = true
  }
}

#Create autoscaling group
resource "aws_autoscaling_group" "web_server" {
  name_name_prefix          = "WebServer-Test-Task-ASG-"
  launch_configuration      = aws_launch_configuration.web_server.name                
  max_size                  = 2
  min_size                  = 2
  min_elb_capacity          = 2
  health_check_type         = "ELB"  
  vpc_zone_identifier       = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  load_balancers            = [aws_elb.web_server]

    dynamic "tag"{
        for_each = {
            Name = "WebServer"
            Owner = "You"
        }
        conetnt{
            key                 = tag.key
            value               = tag.value
            propagate_at_launch = true
        }   
    } 

    lifecycle {
        create_before_destroy = true
    }  
}

resource "aws_elb" "web_server"{
    name_prefix         =   "WebServer-Test-Task-ELB"
    availability_zones  = [data.aws.availability_zones.available.names[0], data.aws.availability_zones.available.names[1]]
    security_groups     = [aws_security_group.web.id]
    listener {
        lb_port           = 80
        lblb_protocol     = "http"
        instance_port     = 80
        instance_protocol = "http"
    }
    health_check {
      healthy_threshold     = 2
      unhealthy_threshold   = 2
      timeout               = 3
      target                = "HTTP:80/"
      interval              = 10
    }
    tags = {
        Name = "WebServer-Test-Task-ELB"
    }
}

resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.available.names[1]
}