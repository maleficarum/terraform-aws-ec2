# Local variables for processing
locals {
  
  # Flatten VNICs for resource creation
  flattened_vnics = flatten([
    for idx, config in var.instance_configuration :
    [
      for vnic_idx, vnic in local.vnic_configs[idx] :
      {
        key           = "${idx}_${vnic_idx}"
        instance_idx  = idx
        vnic_idx      = vnic_idx
        config        = config
        vnic_config   = vnic
      }
    ]
  ])
  
  # Flatten block volumes for resource creation
  flattened_volumes = flatten([
    for idx, config in var.instance_configuration :
    [
      for vol_idx, volume in config.block_volumes :
      {
        key           = "${idx}_${vol_idx}"
        instance_idx  = idx
        volume_idx    = vol_idx
        volume_config = volume
        config        = config
      }
    ]
  ])
  
  # Flatten reserved public IPs
  flattened_reserved_ips = flatten([
    for idx, config in var.instance_configuration :
    [
      for vnic_idx, vnic in local.vnic_configs[idx] :
      {
        key           = "${idx}_${vnic_idx}"
        instance_idx  = idx
        vnic_idx      = vnic_idx
        config        = config
        vnic_config   = vnic
      }
      if config.reserved_public_ip == true && vnic.public == true
    ]
  ])

}

resource "aws_security_group" "instance_sg" {
  for_each = {
    for idx, config in var.instance_configuration :
    idx => config
  }
  
  name        = "${each.value.name}-sg"
  description = "Security group for ${each.value.name}"
  vpc_id      = var.networks.vpc_id

  tags = {
    created-by = var.author
  }
  
  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }
  
  # ICMP for ping (optional)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ICMP"
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
}

resource "aws_network_interface" "vnic" {
  for_each = {
    for vnic in local.flattened_vnics :
    vnic.key => vnic
  }
  
  subnet_id = each.value.vnic_config.type == "public" ? var.networks.public_subnet_ids[each.value.vnic_idx % length(var.networks.public_subnet_ids)] : var.networks.private_subnet_ids[each.value.instance_idx % length(var.networks.private_subnet_ids)]
  
  security_groups = [aws_security_group.instance_sg[each.value.instance_idx].id]
  
  # Source/destination check (set to false for NAT instances)
  source_dest_check = true
  
  lifecycle {
    ignore_changes = [
      attachment,  # Prevent conflicts with aws_instance network_interface attachment
    ]
  }

  tags = {
    created-by = var.author
  }
}

# EC2 Instances
resource "aws_instance" "instances" {
  for_each = {
    for idx, config in var.instance_configuration :
    idx => config
  }

  tags = {
    created-by = var.author
  }
  
  ami               = each.value.image
  instance_type     = each.value.shape_config.type
  iam_instance_profile = var.iam_instance_profile
  
  # Root volume configuration
  root_block_device {
    volume_size = each.value.storage_size != null ? each.value.storage_size : 20
    volume_type = "gp3"
    encrypted   = true
    
  }
  
  # Primary network interface (device_index 0)
  network_interface {
    network_interface_id = aws_network_interface.vnic["${each.key}_0"].id
    device_index         = 0
  }
  
  # Secondary network interface (device_index 1) - if exists
  dynamic "network_interface" {
    for_each = length(local.vnic_configs[each.key]) > 1 ? [local.vnic_configs[each.key][1]] : []
    content {
      network_interface_id = aws_network_interface.vnic["${each.key}_1"].id
      device_index         = network_interface.value.device_index
    }
  }
  
  # Tertiary network interface (device_index 2) - if exists
  dynamic "network_interface" {
    for_each = length(local.vnic_configs[each.key]) > 2 ? [local.vnic_configs[each.key][2]] : []
    content {
      network_interface_id = aws_network_interface.vnic["${each.key}_2"].id
      device_index         = network_interface.value.device_index
    }
  }
  
  # User data for SSH key configuration
user_data = base64encode(templatefile("${path.module}/cloud-init/cloud-init.yaml", {
    instance_name    = each.value.name
    ssh_public_keys  = each.value.ssh_public_key
}))

  # Credit specification for T-series instances
  dynamic "credit_specification" {
    for_each = startswith(each.value.shape_config.type, "t") ? [1] : []
    content {
      cpu_credits = "standard"
    }
  }
  
  lifecycle {
    ignore_changes  = [
      ami,  # Allow AMI updates during maintenance
      user_data,  # Ignore user_data changes after creation
    ]
  }
}

# Elastic IPs for reserved public IPs
resource "aws_eip" "reserved_public_ips" {
  for_each = {
    for ip in local.flattened_reserved_ips :
    ip.key => ip
  }
  
  domain = "vpc"
  
}

# Associate EIPs with network interfaces
resource "aws_eip_association" "reserved_ips" {
  for_each = {
    for ip in local.flattened_reserved_ips :
    ip.key => ip
  }
  
  network_interface_id = aws_network_interface.vnic[each.key].id
  allocation_id        = aws_eip.reserved_public_ips[each.key].id
}

# EBS Block Volumes
resource "aws_ebs_volume" "block_volumes" {
  for_each = {
    for vol in local.flattened_volumes :
    vol.key => vol
  }
  
  availability_zone = aws_instance.instances[each.value.instance_idx].availability_zone
  size              = each.value.volume_config.size
  type              = each.value.volume_config.type
  encrypted         = each.value.volume_config.encrypted
  
}

# Attach block volumes to instances
resource "aws_volume_attachment" "block_attachments" {
  for_each = {
    for vol in local.flattened_volumes :
    vol.key => vol
  }
  
  device_name = "/dev/sd${substr("fghijklmnopqrstuvwxyz", each.value.volume_idx, 1)}"
  volume_id   = aws_ebs_volume.block_volumes[each.key].id
  instance_id = aws_instance.instances[each.value.instance_idx].id
  
  # Prevent volume from being deleted when attachment is destroyed
  skip_destroy = true
  
  # Stop instance before attaching volume (required for some instance types)
  # stop_instance_before_detaching = true
}