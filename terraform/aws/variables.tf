variable "aws" {
  description = "AWS configuration"
  type = object({
    region = string
  })
  default = {
    region = "us-east-1"
  }
}

variable "name" {
  description = "stack/cluster name, used in labelling across the stack."
  type        = string
}

variable "network" {
  description = "Network configuration"
  type = object({
    cidr               = string
    enable_vpn_gateway = bool
    enable_nat_gateway = bool
  })
  default = {
    cidr               = "172.31.0.0/16"
    enable_vpn_gateway = false
    enable_nat_gateway = false
  }
}

# === subnets ===
variable "subnets" {
  description = "The subnets configuration"
  type = map(object({
    cidr       = string
    nodegroups = list(string)
    private    = bool
  }))
  default = {}
}

variable "nodegroups" {
  description = "A map of machine group definitions. Each entry must specify exactly one AMI source: either 'platform' (built-in library lookup, for stock RHEL/Ubuntu/etc. images) or 'ami_id'+'ami_owner' (direct lookup). bootc-mke3 nodegroups always use the 'ami_id'+'ami_owner' path — see terraform.tfvars.example and docs/runbooks/provision-terraform-aws.md for how to obtain a current bootc AMI ID."
  type = map(object({
    // platform-based AMI selection (mutually exclusive with ami_id)
    platform = optional(string)

    // direct AMI selection (mutually exclusive with platform) — this is the path bootc-mke3 uses
    ami_id    = optional(string)
    ami_owner = optional(string)

    // SSH connection details; required when using ami_id (platform provides these automatically)
    ssh_user   = optional(string)
    ssh_port   = optional(number, 22)
    connection = optional(string, "ssh")

    type        = string
    count       = number
    volume_size = number
    role        = string
    public      = bool
    user_data   = optional(string, "")
  }))

  validation {
    condition = alltrue([
      for k, ng in var.nodegroups : (ng.platform != null) != (ng.ami_id != null)
    ])
    error_message = "Each nodegroup must specify exactly one of 'platform' or 'ami_id', not both and not neither."
  }

  validation {
    condition = alltrue([
      for k, ng in var.nodegroups : ng.ami_id == null || ng.ami_owner != null
    ])
    error_message = "'ami_owner' is required when 'ami_id' is set."
  }

  validation {
    condition = alltrue([
      for k, ng in var.nodegroups : ng.ami_id == null || ng.ssh_user != null
    ])
    error_message = "'ssh_user' is required when 'ami_id' is set (it cannot be inferred from a platform definition)."
  }
}

variable "extra_tags" {
  description = "Extra tags that will be added to all provisioned resources, where possible."
  type        = map(string)
  default     = {}
}

variable "ssh_pk_location" {
  description = "Location of the ssh private key"
  type        = string
  default     = ""
}

variable "is_bootc_based" {
  description = "If true, inject cloud-init user-data that configures cloud-user with sudo and docker group access using the stack SSH public key. Defaults to true here because this folder is dedicated to provisioning bootc-mke3 (immutable, cloud-user-based) images; set to false only if you are pointing a nodegroup at a non-bootc platform image for comparison."
  type        = bool
  default     = true
}
