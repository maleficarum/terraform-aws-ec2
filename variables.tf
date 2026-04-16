# Network outputs from other module
variable "networks" {
  description = "Outputs from network module"
  type = object({
    vpc_id             = string
    public_subnet_ids  = list(string)
    private_subnet_ids = list(string)
  })
}

# Instance configuration array
variable "instance_configuration" {
  description = "List of EC2 instance configurations"
  type = list(object({
    name               = string
    ssh_public_key     = list(string)
    shape              = string
    image              = string
    subnet_type        = string  # "public" or "private"
    reserved_public_ip = bool   # Only applies if subnet_type = "public"
    storage_size       = number
    vnic_count         = optional(number, 1)  # Number of VNICs (1-3 typically)
    block_volumes = optional(list(object({
      size      = number
      type      = optional(string, "gp3")
      encrypted = optional(bool, true)
    })), [])
  }))
}


# Optional: Allowed CIDR blocks for SSH
variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to HTTP/HTTPS into instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Optional: Instance profile (IAM role) for EC2
# variable "iam_instance_profile" {
#   description = "IAM instance profile name for EC2 instances"
#   type        = string
#   default     = null
# }

variable "author" {
  description = "The author of the resources"
  type        = string
  default     = "terraform"
}