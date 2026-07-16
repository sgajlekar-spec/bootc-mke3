# Provisions bootc-mke3 on AWS by calling the upstream mke3 example directly —
# see https://registry.terraform.io/modules/terraform-mirantis-modules/provision-aws/mirantis/latest/examples/mke3
# for its full source. It configures its own AWS provider from var.aws.region,
# so no provider block is needed here.

locals {
  # The upstream example requires an "mke" input (MCR/MKE/MSR versions + admin
  # credentials) with no default, but only its debug launchpad_yaml/mke_connect
  # outputs consume it — bootc-mke3 bakes MCR/MKE into the AMI itself and is
  # installed/configured via the ansible playbooks (see ansible/vars/mke-creds.yml),
  # not launchpad. Satisfy the schema with placeholders; neither this value nor
  # those outputs are exposed by this folder.
  mke_placeholder = {
    drain       = false
    mcr_version = ""
    mke_version = ""
    msr_version = ""
    mke_connect = {
      username = ""
      password = ""
      insecure = false
    }
  }
}

module "mke3" {
  source  = "terraform-mirantis-modules/provision-aws/mirantis//examples/mke3"
  version = "0.1.7"

  name = var.name
  aws  = var.aws

  network = var.network
  subnets = var.subnets

  nodegroups = var.nodegroups
  mke        = local.mke_placeholder

  is_bootc_based  = var.is_bootc_based
  ssh_pk_location = var.ssh_pk_location
  extra_tags      = var.extra_tags
}
