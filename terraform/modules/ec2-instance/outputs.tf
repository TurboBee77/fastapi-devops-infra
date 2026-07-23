output "public_ip" {
  description = "Publiczny, stały adres IP instancji (Elastic IP)"
  value       = aws_eip.this.public_ip
}

output "instance_id" {
  description = "ID instancji EC2"
  value       = aws_instance.ec2.id
}

output "security_group_id" {
  description = "ID security group przypisanego do instancji"
  value       = aws_security_group.this.id
}
