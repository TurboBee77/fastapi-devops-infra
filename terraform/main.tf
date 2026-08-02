terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "ci" {
  source = "./modules/ec2-instance"

  role             = "ci"
  instance_type    = var.instance_type
  key_name         = var.key_name
  ssh_allowed_cidr = var.ssh_allowed_cidr
  extra_ingress_ports = var.ci_extra_ingress_ports
  root_volume_size = var.ci_root_volume_size # Docker + Jenkins w Docker Compose - domyślne 8 GB jest za mało
}

module "app" {
  source = "./modules/ec2-instance"

  role             = "app"
  instance_type    = var.instance_type
  key_name         = var.key_name
  ssh_allowed_cidr = var.ssh_allowed_cidr
  extra_ingress_ports = var.app_extra_ingress_ports
  root_volume_size = var.app_root_volume_size # Docker + Postgres w Docker Compose - domyślne 8 GB jest za mało
}

module "monitoring" {
  source = "./modules/ec2-instance"

  role             = "monitoring"
  instance_type    = var.instance_type
  key_name         = var.key_name
  ssh_allowed_cidr = var.ssh_allowed_cidr
}
