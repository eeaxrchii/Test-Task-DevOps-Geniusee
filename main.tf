#-------------
# Test Task DevOps Geniusse
#-------------
terraform {
    required_version = "1.0.11"
}

provider "aws"{
    region = var.region
}

data "aws_eks_cluster" "cluster"{
    name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster"{
    name = module.eks.cluster_id
}

data "aws_availability_zones" "available"{}

#Create new secrity group
resource "aws_security_group" "worker_group_mgmt_one" {
    name_prefix = "worker_group_mgmt_one"
    vpc_id = module.vpc.vpc_id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"

        cidr_blocks = [
            "10.0.0.0/8"
        ]
    }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name                 = "test-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }

}

#Create Kuber
module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name    = var.cluster_name
  cluster_version = "1.21"


  vpc_id          = module.vpc.vpc_id
  subnets         = [module.vpc.private_subnets[0], module.vpc.public_subnets[1]]
  fargate_subnets = [module.vpc.private_subnets[2]]

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true



  

  # Worker groups (using Launch Configurations)
  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t2.micro"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    }
  ]

  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
  # Worker groups (using Launch Templates)
  worker_groups_launch_template = [
    {
      name                    = "spot-1"
      override_instance_types = ["m5.large", "m5a.large", "m5d.large", "m5ad.large"]
      spot_instance_pools     = 4
      asg_max_size            = 5
      asg_desired_capacity    = 5
      kubelet_extra_args      = "--node-labels=node.kubernetes.io/lifecycle=spot"
      public_ip               = true
    },
  ]

  # Managed Node Groups
  node_groups_defaults = {
    ami_type  = "AL2_x86_64"
    disk_size = 50
  }

  node_groups = {
    example = {
      desired_capacity = 1
      max_capacity     = 10
      min_capacity     = 1

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
      k8s_labels = {
        Environment = "test"
        GithubRepo  = "terraform-aws-eks"
        GithubOrg   = "terraform-aws-modules"
      }
      additional_tags = {
        ExtraTag = "example"
      }
      taints = [
        {
          key    = "dedicated"
          value  = "gpuGroup"
          effect = "NO_SCHEDULE"
        }
      ]
      update_config = {
        max_unavailable_percentage = 50 # or set `max_unavailable`
      }
    }
  }

  # AWS Auth (kubernetes_config_map)
  map_roles = var.map_roles
  map_users = var.map_users
  map_accounts = var.map_accounts
}

provider "kubernetes"{
    host = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_deployment" "example" {
  metadata {
    name = "terraform-example"
    labels = {
      test = "MyExampleApp"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        test = "MyExampleApp"
      }
    }

    template {
      metadata {
        labels = {
          test = "MyExampleApp"
        }
      }

      spec {
        container {
          image = "httpd"
          name  = "example"

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

          liveness_probe {
            http_get {
              port = 80

              http_header {
                name  = "X-Custom-Header"
                value = "Awesome"
              }
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "example"{
    metadata {
        name = "terraform-example"
    }

    spec{
        selector = {
            test = "MyExampleApp"
        }
        port {
            port = 80
            target_port = 80
        }

        type = "LoadBalancer"
    }
}

data "aws_elb" "example" {
  name = local.lb_name
}


#Create Elastic Search Domain
resource "aws_elasticsearch_domain" "elastic_logs_domain" {
  domain_name = "elastic-logs-domain"
  elasticsearch_version = 6.5
  cluster_config {
    instance_type = "m4.large.elasticsearch"
    instance_count = 1
    dedicated_master_enabled = false
  }
  ebs_options {
    ebs_enabled = true
    volume_type = "gp2"
    volume_size = "512"
  }
}

#Create Fluend 
resource "kubernetes_daemonset" "fluentd" {
  metadata {
    name      = "fluentd"
    namespace = "kube-system"

    labels = {
      k8s-app = "fluentd-logging"

      version = "v1"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "fluentd-logging"

        version = "v1"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "fluentd-logging"

          version = "v1"
        }
      }

      spec {
        volume {
          name = "varlog"

          host_path {
            path = "/var/log"
          }
        }

        container {
          name  = "fluentd"
          image = "fluent/fluentd-kubernetes-daemonset:v1-debian-elasticsearch"

          env {
            name  = "FLUENT_ELASTICSEARCH_HOST"
            value = "elasticsearch-logging"
          }

          env {
            name  = "FLUENT_ELASTICSEARCH_PORT"
            value = "9200"
          }

          env {
            name  = "FLUENT_ELASTICSEARCH_SCHEME"
            value = "http"
          }

          env {
            name  = "FLUENT_ELASTICSEARCH_USER"
            value = "elastic"
          }

          env {
            name  = "FLUENT_ELASTICSEARCH_PASSWORD"
            value = "changeme"
          }

          resources {
            limits = {
              memory = "200Mi"
            }

            requests = {
              cpu = "100m"

              memory = "200Mi"
            }
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
          }

        }

        termination_grace_period_seconds = 30

        toleration {
          key    = "node-role.kubernetes.io/master"
          effect = "NoSchedule"
        }
      }
    }
  }
}