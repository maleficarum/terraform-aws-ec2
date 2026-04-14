locals {
  # 0 = 1 private, 1 = 1 public, 2 = 1 public + 1 private, 3 = 2 public + 1 private
  vnic_configs = {
    for idx, config in var.instance_configuration :
    idx => config.subnet_index == 0 ? [
      { type = "private", public = false, device_index = 0 }
    ] : config.subnet_index == 1 ? [
      { type = "public", public = true, device_index = 0 }
    ] : config.subnet_index == 2 ? [
      { type = "public", public = true, device_index = 0 },
      { type = "private", public = false, device_index = 1 }
    ] : config.subnet_index == 3 ? [
      { type = "public", public = true, device_index = 0 },
      { type = "public", public = true, device_index = 1 },
      { type = "private", public = false, device_index = 2 }
    ] : []
  }
}