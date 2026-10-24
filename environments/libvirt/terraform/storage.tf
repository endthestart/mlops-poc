resource "libvirt_pool" "mlops" {
  name = "mlops-pool"
  type = "dir"
  
  target {
    path = var.smb_storage_path
  }
}

resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-base.qcow2"
  pool   = libvirt_pool.mlops.name
  source = var.ubuntu_image
  format = "qcow2"
}

resource "libvirt_volume" "master_disk" {
  name           = "${var.vm_master.name}.qcow2"
  pool           = libvirt_pool.mlops.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.vm_master.disk * 1024 * 1024 * 1024
}

resource "libvirt_volume" "gpu_worker_disk" {
  name           = "${var.vm_gpu_worker.name}.qcow2"
  pool           = libvirt_pool.mlops.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.vm_gpu_worker.disk * 1024 * 1024 * 1024
}

resource "libvirt_volume" "worker_disk" {
  name           = "${var.vm_worker.name}.qcow2"
  pool           = libvirt_pool.mlops.name
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = var.vm_worker.disk * 1024 * 1024 * 1024
}
