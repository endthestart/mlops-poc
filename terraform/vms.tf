# VM configuration for libvirt provider v0.8.3

# Master VM
resource "libvirt_domain" "master" {
  name   = var.vm_master.name
  memory = var.vm_master.memory
  vcpu   = var.vm_master.vcpu

  cloudinit = libvirt_cloudinit_disk.master.id

  network_interface {
    network_name   = "mlops-net"
    mac            = "52:54:00:00:00:01"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.master_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# GPU Worker VM
resource "libvirt_domain" "gpu_worker" {
  name   = var.vm_gpu_worker.name
  memory = var.vm_gpu_worker.memory
  vcpu   = var.vm_gpu_worker.vcpu

  cloudinit = libvirt_cloudinit_disk.gpu_worker.id

  network_interface {
    network_name   = "mlops-net"
    mac            = "52:54:00:00:00:02"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.gpu_worker_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

# Worker VM
resource "libvirt_domain" "worker" {
  name   = var.vm_worker.name
  memory = var.vm_worker.memory
  vcpu   = var.vm_worker.vcpu

  cloudinit = libvirt_cloudinit_disk.worker.id

  network_interface {
    network_name   = "mlops-net"
    mac            = "52:54:00:00:00:03"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.worker_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
