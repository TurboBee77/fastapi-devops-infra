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

variable "app_extra_ingress_ports" {
  description = "Dodatkowe porty akceptowane przez sg dla serwera aplikacji"
  type        = list(number)
}

variable "ci_extra_ingress_ports" {
  description = "Dodatkowe porty akceptowane przez sg dla serwera ci"
  type        = list(number)
}

variable "ci_root_volume_size" {
  description = "Rozmiar wolumenu root dla serwera ci (w GB)"
  type        = number
  default     = 8
}

variable "app_root_volume_size" {
  description = "Rozmiar wolumenu root dla serwera aplikacji (w GB)"
  type        = number
  default     = 8
}

variable "ci_internal_ingress_ports" {
  description = "Porty TCP dla ci dostępne tylko wewnątrz domyślnego VPC"
  type        = list(number)
  default     = []
}

variable "app_internal_ingress_ports" {
  description = "Porty TCP dla app dostępne tylko wewnątrz domyślnego VPC"
  type        = list(number)
  default     = []
}

variable "monitoring_internal_ingress_ports" {
  description = "Porty TCP dla monitoring dostępne tylko wewnątrz domyślnego VPC"
  type        = list(number)
  default     = []
}

variable "monitoring_extra_ingress_ports" {
  description = "Dodatkowe porty publiczne dla serwera monitoring (np. UI Grafany)"
  type        = list(number)
  default     = []
}
