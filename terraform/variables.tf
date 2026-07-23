variable "aws_region" {
  description = "Region AWS, w którym tworzona jest infrastruktura"
  type        = string
  default     = "eu-central-1"
}

variable "key_name" {
  description = "Nazwa istniejącej pary kluczy SSH w AWS (musi istnieć w regionie aws_region przed apply)"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR, z którego dozwolony jest ruch SSH do wszystkich 3 instancji"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "Typ instancji EC2 wspólny dla wszystkich 3 VM (Free Tier: t3.micro lub t2.micro)"
  type        = string
  default     = "t3.micro"
}
