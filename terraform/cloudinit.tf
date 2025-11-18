# Cloud-init configuration for VMs
data "template_file" "user_data" {
  template = file("${path.module}/cloud-init.yaml")
}

# Cloud-init disk resource
resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit.iso"
  user_data = data.template_file.user_data.rendered
  pool      = libvirt_pool.mlops.name
}
