# Cloud-init configuration for VMs
data "template_file" "user_data_master" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    hostname = "k3s-master"
  }
}

data "template_file" "user_data_gpu_worker" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    hostname = "k3s-gpu-worker"
  }
}

data "template_file" "user_data_worker" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    hostname = "k3s-worker"
  }
}

# Cloud-init disk resources
resource "libvirt_cloudinit_disk" "master" {
  name      = "master-init.iso"
  user_data = data.template_file.user_data_master.rendered
  pool      = libvirt_pool.mlops.name
}

resource "libvirt_cloudinit_disk" "gpu_worker" {
  name      = "gpu-worker-init.iso"
  user_data = data.template_file.user_data_gpu_worker.rendered
  pool      = libvirt_pool.mlops.name
}

resource "libvirt_cloudinit_disk" "worker" {
  name      = "worker-init.iso"
  user_data = data.template_file.user_data_worker.rendered
  pool      = libvirt_pool.mlops.name
}
