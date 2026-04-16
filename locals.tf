# Local variables for processing
locals {

  # Generate VNIC configurations based on vnic_count
  vnic_configs = {
    for idx, config in var.instance_configuration :
    idx => [
      for i in range(config.vnic_count) : {
        type         = config.subnet_type  # All VNICs use same subnet type
        device_index = i
        public       = config.subnet_type == "public" && config.reserved_public_ip && i == 0  # Only primary VNIC gets public IP
      }
    ]
  }

  # Flatten VNICs for resource creation
  flattened_vnics = flatten([
    for idx, config in var.instance_configuration :
    [
      for vnic_idx, vnic in local.vnic_configs[idx] :
      {
        key          = "${idx}_${vnic_idx}"
        instance_idx = idx
        vnic_idx     = vnic_idx
        config       = config
        vnic_config  = vnic
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

  # Flatten reserved public IPs (only for primary VNIC of public instances)
  flattened_reserved_ips = flatten([
    for idx, config in var.instance_configuration :
    [
      for vnic_idx, vnic in local.vnic_configs[idx] :
      {
        key          = "${idx}_${vnic_idx}"
        instance_idx = idx
        vnic_idx     = vnic_idx
        config       = config
        vnic_config  = vnic
      }
      if config.reserved_public_ip == true && vnic.public == true
    ]
  ])

  # Helper maps for subnet selection
#public_subnet_count  = length(var.networks.public_subnet_ids)
#private_subnet_count = length(var.networks.private_subnet_ids)
  
  get_subnet_id = {
    public  = var.networks.public_subnet_ids
    private = var.networks.private_subnet_ids
  }
}