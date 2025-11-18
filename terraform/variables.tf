variable "smb_storage_path" {
  description = "Path to SMB-mounted storage for VM disks"
  default     = "/mnt/storage/kvm/mlops-pool"
}

variable "vm_master" {
  type = object({
    name   = string
    vcpu   = number
    memory = number
    disk   = number
  })
  default = {
    name   = "k3s-master"
    vcpu   = 2
    memory = 4096
    disk   = 20
  }
}

variable "vm_gpu_worker" {
  type = object({
    name   = string
    vcpu   = number
    memory = number
    disk   = number
  })
  default = {
    name   = "k3s-gpu-worker"
    vcpu   = 8
    memory = 16384
    disk   = 50
  }
}

variable "vm_worker" {
  type = object({
    name   = string
    vcpu   = number
    memory = number
    disk   = number
  })
  default = {
    name   = "k3s-worker"
    vcpu   = 4
    memory = 8192
    disk   = 50
  }
}

variable "ubuntu_image" {
  default = "https://cloud-images.ubuntu.com/releases/plucky/release/ubuntu-25.04-server-cloudimg-amd64.img"
}
