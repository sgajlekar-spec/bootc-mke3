# Passthrough of the upstream example's outputs — see the "mke3" module.
# https://registry.terraform.io/modules/terraform-mirantis-modules/provision-aws/mirantis/latest/examples/mke3

output "bootc_ansible_output" {
  description = "Ansible inventory YAML compatible with bootc-mke3 playbooks. Retrieve with: terraform output -raw bootc_ansible_output > inventory.yaml"
  sensitive   = true
  value       = module.mke3.bootc_ansible_output
}

output "nodes" {
  description = "Nodegroups with node lists"
  sensitive   = true
  value       = module.mke3.nodes
}

output "ingresses" {
  description = "Ingresses with dns information"
  value       = module.mke3.ingresses
}

output "platforms" {
  description = "Resolved AMI data for any platform-based (non-bootc) nodegroups"
  sensitive   = true
  value       = module.mke3.platforms
}
