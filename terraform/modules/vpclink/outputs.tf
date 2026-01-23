# VPC Link統合モジュール - 出力定義

output "vpc_id" {
  description = "作成されたVPCのID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "プライベートサブネットのIDリスト"
  value       = aws_subnet.private[*].id
}

output "alb_arn" {
  description = "ALBのARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALBのDNS名"
  value       = aws_lb.main.dns_name
}

output "nlb_arn" {
  description = "NLBのARN"
  value       = aws_lb.nlb.arn
}

output "nlb_dns_name" {
  description = "NLBのDNS名"
  value       = aws_lb.nlb.dns_name
}

output "vpc_link_id" {
  description = "VPC LinkのID"
  value       = aws_api_gateway_vpc_link.main.id
}

output "vpc_link_status" {
  description = "VPC Linkのステータス"
  value       = aws_api_gateway_vpc_link.main.status
}

output "ecs_cluster_name" {
  description = "ECSクラスター名"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECSクラスターのARN"
  value       = aws_ecs_cluster.main.arn
}

output "api_server_1_service_name" {
  description = "API Server 1 (Users Service) のECSサービス名"
  value       = aws_ecs_service.api_server_1.name
}

output "api_server_2_service_name" {
  description = "API Server 2 (Orders Service) のECSサービス名"
  value       = aws_ecs_service.api_server_2.name
}
