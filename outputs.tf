output "instance_details" {
  description = "Details of all created EC2 instances"
  value = {
    for idx, instance in aws_instance.instances :
    idx => {
      id                = instance.id
      private_ip        = instance.private_ip
      public_ip         = instance.public_ip
      state             = instance.instance_state
      instance_type     = instance.instance_type
      availability_zone = instance.availability_zone
      vnics = {
        for vnic_key, vnic in aws_network_interface.vnic :
        vnic_key => {
          id         = vnic.id
          private_ip = vnic.private_ip
        }
        if startswith(vnic_key, idx)
      }
    }
  }
}

output "instance_ids" {
  description = "IDs of created instances"
  value       = { for idx, instance in aws_instance.instances : idx => instance.id }
}

output "instance_private_ips" {
  description = "Private IPs of instances (primary VNIC)"
  value       = { for idx, instance in aws_instance.instances : idx => instance.private_ip }
}

output "instance_public_ips" {
  description = "Public IPs of instances (if assigned)"
  value       = { for idx, instance in aws_instance.instances : idx => instance.public_ip }
}

output "vnic_details" {
  description = "Details of all VNICs"
  value = {
    for key, vnic in aws_network_interface.vnic :
    key => {
      id         = vnic.id
      private_ip = vnic.private_ip
      subnet_id  = vnic.subnet_id
    }
  }
}

output "reserved_public_ips" {
  description = "Reserved public IPs (EIPs) created"
  value = {
    for key, eip in aws_eip.reserved_public_ips :
    key => {
      id              = eip.id
      public_ip       = eip.public_ip
      associated_with = aws_eip_association.reserved_ips[key].network_interface_id
    }
  }
}