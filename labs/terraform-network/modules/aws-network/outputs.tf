output "network_id" {
  description = "The VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnets, one per zone"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "App subnets, one per zone"
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "Data subnets, one per zone"
  value       = aws_subnet.data[*].id
}

output "security_group_ids" {
  description = "Security groups for the load balancer, app and database tiers"
  value       = { lb = aws_security_group.lb.id, app = aws_security_group.app.id, db = aws_security_group.db.id }
}
