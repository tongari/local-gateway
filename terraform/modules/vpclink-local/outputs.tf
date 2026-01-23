# LocalStack用 VPC Link統合モジュール - 出力定義

output "vpc_id" {
  description = "作成されたVPCのID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "プライベートサブネットのIDリスト"
  value       = aws_subnet.private[*].id
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
  description = "VPC LinkのID（LocalStackではステータス取得は未サポート）"
  value       = aws_api_gateway_vpc_link.main.id
}

output "target_group_arn" {
  description = "ターゲットグループのARN"
  value       = aws_lb_target_group.backend.arn
}
