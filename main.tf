resource "aws_iam_role" "ec2_role" {
  name = "ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ssm-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "instance_sg" {
  for_each = {
    for idx, config in var.instance_configuration :
    tostring(idx) => config
  }

  name   = "${each.value.name}-sg"
  vpc_id = var.networks.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create network interfaces first
resource "aws_network_interface" "vnic" {
  for_each = {
    for vnic in local.flattened_vnics :
    vnic.key => vnic
  }

  subnet_id = each.value.config.subnet_type == "public" ? local.get_subnet_id.public[tostring(each.value.instance_idx)] : local.get_subnet_id.private[tostring(each.value.instance_idx)]

  security_groups = [
    aws_security_group.instance_sg[tostring(each.value.instance_idx)].id
  ]

  source_dest_check = true

  lifecycle {
    ignore_changes = [attachment]
  }

  tags = {
    Name = "${each.value.config.name}-vnic${each.value.vnic_idx}"
  }
}

# Create instance in the appropriate subnet directly
resource "aws_instance" "instances" {
  for_each = {
    for idx, config in var.instance_configuration :
    tostring(idx) => config
  }

  ami           = each.value.image
  instance_type = each.value.shape

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  subnet_id = each.value.subnet_type == "public" ? local.get_subnet_id.public[0] : local.get_subnet_id.private[0]

  associate_public_ip_address = false

  root_block_device {
    volume_size = each.value.storage_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data_base64 = base64encode(templatefile("${path.module}/cloud-init/cloud-init-${each.value.name}.yaml", {
    instance_name   = each.value.name
    ssh_public_keys = each.value.ssh_public_key
  }))

  tags = {
    Name       = each.value.name
    created-by = var.author
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }

    vpc_security_group_ids = [
    aws_security_group.instance_sg[each.key].id
  ]

  # 🚨 CRITICAL FIX: IAM eventual consistency
  depends_on = [
    aws_iam_role_policy_attachment.ssm
  ]
}


# For primary interface with custom configuration (if needed)
# Don't use custom ENI for primary, let AWS create it

# Attach primary network interface
# resource "aws_network_interface_attachment" "primary_vnic" {
#   for_each = {
#     for vnic in local.flattened_vnics :
#     vnic.key => vnic
#     if vnic.vnic_idx == 0
#   }

#   instance_id          = aws_instance.instances[each.value.instance_idx].id
#   network_interface_id = aws_network_interface.vnic[each.key].id
#   device_index         = 0
# }

resource "aws_network_interface_attachment" "secondary_vnics" {
  for_each = {
    for vnic in local.flattened_vnics :
    vnic.key => vnic
    if vnic.vnic_idx > 0
  }

  instance_id = aws_instance.instances[tostring(each.value.instance_idx)].id
  network_interface_id = aws_network_interface.vnic[each.key].id
  device_index = each.value.vnic_idx
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
    if ip.vnic_idx == 0
  }

  allocation_id = aws_eip.reserved_public_ips[each.key].id

  # ✅ attach to PRIMARY ENI
  network_interface_id = aws_instance.instances[tostring(each.value.instance_idx)].primary_network_interface_id
}

# EBS Block Volumes - Create after instances
resource "aws_ebs_volume" "block_volumes" {
  for_each = {
    for vol in local.flattened_volumes :
    vol.key => vol
  }

  availability_zone = aws_instance.instances[tostring(each.value.instance_idx)].availability_zone
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
  instance_id = aws_instance.instances[tostring(each.value.instance_idx)].id

  skip_destroy = true
}