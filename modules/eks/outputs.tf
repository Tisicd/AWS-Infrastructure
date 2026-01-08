output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID automatically created by EKS"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "managed_nodegroup_names" {
  description = "Names of managed node groups"
  value       = var.node_role_arn != "" ? [aws_eks_node_group.main[0].node_group_name] : []
}

output "asg_name" {
  description = "Name of the Auto Scaling Group (if using self-managed nodes)"
  value       = var.node_role_arn == "" ? aws_autoscaling_group.eks_nodes[0].name : null
}




