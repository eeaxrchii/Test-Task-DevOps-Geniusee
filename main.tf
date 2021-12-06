#-------------
# Test Task DevOps Geniusse
#-------------


provider "aws"{
    region = "eu-central-1"
}

data "aws_avialability_zones" "available"{}
data "aws_ami" "latest_amazon_linux" {
    owners = ["amazon"]
    most_recent = true
    filter{
        name = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

#Create new secrity group
resourse "aws_security_group" "web_server"{
    name = "Security Group"

    dynamic "ingress"{
        for_each = ["80", "443"]
        content {
            from_port = ingress.value
            to_port = ingress.value
            protocol = "tcp"
            cidr_blocks = ["0.0.0.0/0"]
        }
    }

    egress {
        from_port = 0
        to_prot = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "Security Group"
        Owner = "You"
    }
}

