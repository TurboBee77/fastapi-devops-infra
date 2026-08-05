output "ci_public_ip" {
  description = "Publiczny IP instancji ci (Jenkins)"
  value       = module.ci.public_ip
}

output "app_public_ip" {
  description = "Publiczny IP instancji app (backend + PostgreSQL)"
  value       = module.app.public_ip
}

output "monitoring_public_ip" {
  description = "Publiczny IP instancji monitoring (Prometheus + Grafana)"
  value       = module.monitoring.public_ip
}

output "ci_private_ip" {
  description = "Prywatny IP instancji ci (Jenkins)"
  value       = module.ci.private_ip
}

output "app_private_ip" {
  description = "Prywatny IP instancji app (backend + PostgreSQL)"
  value       = module.app.private_ip
}

output "monitoring_private_ip" {
  description = "Prywatny IP instancji monitoring (Prometheus + Grafana)"
  value       = module.monitoring.private_ip
}