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
