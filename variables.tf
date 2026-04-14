# Network outputs from other module
variable "networks" {
  description = "Outputs from network module"
  type = object({
    vpc_id               = string
    public_subnet_ids    = list(string)
    private_subnet_ids   = list(string)
  })
}

# Instance configuration array
variable "instance_configuration" {
  description = "List of EC2 instance configurations"
  type = list(object({
    name           = string
    ssh_public_key = list(string)
    shape_config = object({
      memory = number
      ocpus  = number
      type   = string
    })
    assign_ipv6ip             = string
    state                     = string
    assign_private_dns_record = string
    assign_public_ip          = string
    image                     = string
    storage_size              = optional(number)
    block_volumes = optional(list(object({
      size      = number
      type      = optional(string, "gp3")
      encrypted = optional(bool, true)
    })), [])
    subnet_index       = number
    application_name   = string
    reserved_public_ip = bool
    platform           = string
    license_type       = string
    prevent_destroy    = bool
  }))
}


# Optional: Allowed CIDR blocks for SSH
variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Optional: Instance profile (IAM role) for EC2
variable "iam_instance_profile" {
  description = "IAM instance profile name for EC2 instances"
  type        = string
  default     = null
}

variable "author" {
    description = "The author of the resources"
    type = string
    default = "terraform"
}