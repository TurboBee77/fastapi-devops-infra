variable "role" {
  description = "Rola instancji (ci / app / monitoring) - używana jako Name tag i do identyfikacji zasobów."
  type        = string
}

variable "instance_type" {
  description = "Typ instancji EC2 (Free Tier: t3.micro lub t2.micro, zależnie od dostępności w regionie)."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Nazwa istniejącej pary kluczy SSH w AWS (musi być wcześniej zaimportowana/utworzona w regionie docelowym)."
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR, z którego dozwolony jest ruch SSH (port 22) do instancji."
  type        = string
  default     = "0.0.0.0/0"
}

variable "extra_ingress_ports" {
  description = "Dodatkowe porty TCP otwierane per rola (np. 8080 dla Jenkinsa) - poza SSH, które jest zawsze otwarte."
  type        = list(number)
  default     = []
}

variable "root_volume_size" {
  description = "Rozmiar root volume (EBS) w GB. Domyślne AMI Ubuntu startuje z 8 GB - zwiększ dla instancji hostujących dane (np. Postgres w Docker)."
  type        = number
  default     = 8
}
