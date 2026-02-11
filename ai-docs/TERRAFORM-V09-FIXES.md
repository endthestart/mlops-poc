# Terraform Libvirt Provider v0.9.0 Syntax Guide

## Important: Provider Version Differences

Your system has **libvirt provider v0.9.0** which has **completely different syntax** from the v0.7.x examples in the original PLAN.md.

The PLAN.md was written with v0.7.x syntax in mind, but v0.9.0 made breaking API changes.

---

## ✅ Working Terraform Configuration (v0.9.0)

### storage.tf
```hcl
# Storage pool on SMB mount
resource "libvirt_pool" "mlops" {
  name = "mlops-pool"
  type = "dir"
  target = {  # v0.9.0: target is an object
    path = var.smb_storage_path
  }
}

# Base Ubuntu cloud image
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-base.qcow2"
  pool   = libvirt_pool.mlops.name
  format = "qcow2"
  
  # v0.9.0: create.content.url instead of source
  create = {
    content = {
      url = var.ubuntu_image
    }
  }
}

# VM disks (created from base image using backing store)
resource "libvirt_volume" "master_disk" {
  name     = "${var.vm_master.name}.qcow2"
  pool     = libvirt_pool.mlops.name
  format   = "qcow2"
  capacity = var.vm_master.disk * 1024 * 1024 * 1024  # v0.9.0: capacity not size
  
  # v0.9.0: backing_store instead of base_volume_id
  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = "qcow2"
  }
}

resource "libvirt_volume" "gpu_worker_disk" {
  name     = "${var.vm_gpu_worker.name}.qcow2"
  pool     = libvirt_pool.mlops.name
  format   = "qcow2"
  capacity = var.vm_gpu_worker.disk * 1024 * 1024 * 1024
  
  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = "qcow2"
  }
}

resource "libvirt_volume" "worker_disk" {
  name     = "${var.vm_worker.name}.qcow2"
  pool     = libvirt_pool.mlops.name
  format   = "qcow2"
  capacity = var.vm_worker.disk * 1024 * 1024 * 1024
  
  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = "qcow2"
  }
}
```

### vms.tf
```hcl
# VM configuration for libvirt provider v0.9.0

# Master VM
resource "libvirt_domain" "master" {
  name   = var.vm_master.name
  memory = var.vm_master.memory
  vcpu   = var.vm_master.vcpu

  # v0.9.0: Single devices object instead of separate blocks
  devices = {
    # v0.9.0: interfaces (plural) not network_interface
    interfaces = [{
      type         = "network"
      network_name = "mlops-net"
      mac          = "52:54:00:00:00:01"
    }]
    
    # v0.9.0: disks (plural) and requires target
    disks = [{
      volume_id = libvirt_volume.master_disk.id
      target = {
        dev = "vda"
        bus = "virtio"
      }
    }]
    
    # v0.9.0: graphics is singular object not array
    graphics = {
      type = "spice"
      listen = {
        type = "address"
      }
    }
  }
}

# GPU Worker VM
resource "libvirt_domain" "gpu_worker" {
  name   = var.vm_gpu_worker.name
  memory = var.vm_gpu_worker.memory
  vcpu   = var.vm_gpu_worker.vcpu

  devices = {
    interfaces = [{
      type         = "network"
      network_name = "mlops-net"
      mac          = "52:54:00:00:00:02"
    }]
    
    disks = [{
      volume_id = libvirt_volume.gpu_worker_disk.id
      target = {
        dev = "vda"
        bus = "virtio"
      }
    }]
    
    graphics = {
      type = "spice"
      listen = {
        type = "address"
      }
    }
  }
}

# Worker VM
resource "libvirt_domain" "worker" {
  name   = var.vm_worker.name
  memory = var.vm_worker.memory
  vcpu   = var.vm_worker.vcpu

  devices = {
    interfaces = [{
      type         = "network"
      network_name = "mlops-net"
      mac          = "52:54:00:00:00:03"
    }]
    
    disks = [{
      volume_id = libvirt_volume.worker_disk.id
      target = {
        dev = "vda"
        bus = "virtio"
      }
    }]
    
    graphics = {
      type = "spice"
      listen = {
        type = "address"
      }
    }
  }
}
```

---

## 📊 API Changes Summary

| Feature | v0.7.x Syntax | v0.9.0 Syntax |
|---------|---------------|---------------|
| **Pool path** | `path = "..."` | `target = { path = "..." }` |
| **Volume source** | `source = url` | `create = { content = { url = url } }` |
| **Volume size** | `size = bytes` | `capacity = bytes` |
| **Backing volume** | `base_volume_id = id` | `backing_store = { path, format }` |
| **VM devices** | Separate blocks | Single `devices = {}` object |
| **Network** | `network_interface {}` | `interfaces = [{}]` (plural) |
| **Disks** | `disk {}` | `disks = [{}]` (plural) + required `target` |
| **Graphics** | `graphics {}` block | `graphics = {}` object |
| **Cloud-init** | `cloudinit = id` | Different approach (TBD) |

---

## 🚫 What's Missing in Current Config

The current simplified configuration **does not include**:

1. **Cloud-init**: The v0.9.0 provider handles cloud-init differently
2. **Console**: Removed for simplicity
3. **SSH Keys**: Need to be added via cloud-init or manually
4. **Hostname configuration**: Need to set manually
5. **Network wait**: `wait_for_lease` not available in v0.9.0

These will need to be handled differently - either:
- Use libvirt's newer cloudinit approach
- Configure after VMs boot using Ansible
- Use the Fawkes project's patterns (see below)

---

## 🎯 Using Fawkes Project Code

The [Fawkes Terraform project](https://github.com/Cray-HPE/fawkes-terraform) has excellent patterns you can reuse:

### What's Useful from Fawkes:

1. **Modular Structure**: 
   - `modules/hypervisor/` - Hypervisor management
   - `modules/hypervisor/modules/kubernetes/` - K8s-specific VMs
   - `modules/hypervisor/modules/networks/` - Network management

2. **Good Patterns**:
   - Separated network configuration
   - Proper variable management
   - Output definitions for accessing VMs
   - Inventory generation for Ansible

3. **What to Adapt** (not copy directly):
   - Their code uses Terragrunt for multi-environment
   - Built for scalable node count
   - You need simpler, fixed 3-node setup

### Recommended Approach:

**Option A: Start Simple (Current)**
- Use the working config above
- Add cloud-init/configuration manually
- Get VMs running first
- Add complexity later

**Option B: Modularize Like Fawkes**
```
terraform/
├── main.tf              # Main orchestration
├── variables.tf         # All variables
├── modules/
│   ├── storage/         # Storage pool & volumes
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── network/         # Network configuration
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── vms/            # VM definitions
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── outputs.tf          # VM IPs, etc.
```

**Recommendation**: Start with Option A (current working config), get it running, then refactor to modules if needed.

---

## 🔧 Next Steps to Complete Configuration

### 1. Add Cloud-Init (Method 1: User Data via XML)
```hcl
resource "libvirt_domain" "master" {
  # ... existing config ...
  
  xml {
    xslt = templatefile("${path.module}/cloudinit.xsl", {
      hostname = var.vm_master.name
      ssh_key  = file("~/.ssh/id_rsa.pub")
    })
  }
}
```

### 2. Add Cloud-Init (Method 2: External Tool)
Use `cloud-localds` to create cloud-init ISO manually:
```bash
cat > user-data << EOF
#cloud-config
hostname: k3s-master
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat ~/.ssh/id_rsa.pub)
EOF

cloud-localds cloud-init.iso user-data
```

Then attach to VM as CD-ROM.

### 3. Add Outputs for Easy Access
**Create terraform/outputs.tf:**
```hcl
output "master_ip" {
  description = "Master node IP address"
  value       = libvirt_domain.master.network_interface[0].addresses[0]
}

output "gpu_worker_ip" {
  description = "GPU worker IP address"  
  value       = libvirt_domain.gpu_worker.network_interface[0].addresses[0]
}

output "worker_ip" {
  description = "Worker node IP address"
  value       = libvirt_domain.worker.network_interface[0].addresses[0]
}

output "ssh_commands" {
  description = "SSH commands to access VMs"
  value = {
    master     = "ssh ubuntu@${libvirt_domain.master.network_interface[0].addresses[0]}"
    gpu_worker = "ssh ubuntu@${libvirt_domain.gpu_worker.network_interface[0].addresses[0]}"
    worker     = "ssh ubuntu@${libvirt_domain.worker.network_interface[0].addresses[0]}"
  }
}
```

### 4. Add Network Definition
**Create a proper libvirt network** (instead of assuming mlops-net exists):

**Create terraform/network.tf:**
```hcl
resource "libvirt_network" "mlops" {
  name      = "mlops-net"
  mode      = "nat"
  domain    = "mlops.local"
  addresses = ["192.168.100.0/24"]
  
  dhcp = {
    enabled = true
  }
  
  dns = {
    enabled    = true
    local_only = false
  }
}
```

---

## 🐛 Common Issues & Fixes

### Issue: "Unsupported argument"
**Cause**: Using v0.7.x syntax with v0.9.0 provider  
**Fix**: Use the syntax from this document

### Issue: "attribute X is required"
**Cause**: v0.9.0 has stricter requirements  
**Fix**: Check schema with `terraform providers schema -json`

### Issue: Cloud-init not working
**Cause**: v0.9.0 changed cloud-init handling  
**Fix**: Use alternative methods (XML xslt, manual ISO, or Ansible)

### Issue: Can't access VMs
**Cause**: No SSH keys configured, or network not set up  
**Fix**: 
1. Add SSH keys via cloud-init or manually
2. Ensure network is created first
3. Use `virsh console <vm-name>` to access

### Issue: VMs not getting IP addresses
**Cause**: Network DHCP not configured or network not started  
**Fix**:
```bash
# Check network status
virsh net-list --all

# Start network if needed
virsh net-start mlops-net

# Set to autostart
virsh net-autostart mlops-net
```

---

## 📚 References

- **Libvirt Provider v0.9.0**: [Provider Registry](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)
- **Fawkes Project**: https://github.com/Cray-HPE/fawkes-terraform
- **Cloud-Init Docs**: https://cloudinit.readthedocs.io/

---

## ✅ Verification Steps

After applying Terraform:

```bash
# 1. Check Terraform state
terraform show

# 2. List VMs
virsh list --all

# 3. Check VM details
virsh dominfo k3s-master
virsh dominfo k3s-gpu-worker  
virsh dominfo k3s-worker

# 4. Check networks
virsh net-list
virsh net-dhcp-leases mlops-net

# 5. Check storage
virsh pool-list
virsh vol-list mlops-pool

# 6. Access VM console (if no SSH yet)
virsh console k3s-master
# Press Ctrl+] to exit console

# 7. Once SSH is configured
ssh ubuntu@<vm-ip>
```

---

## 🎯 Recommended Path Forward

1. **Now**: Use the working v0.9.0 config above ✅ (already done!)
2. **Next**: Set up network definition in Terraform
3. **Then**: Add cloud-init or use Ansible for initial configuration
4. **Later**: Consider modularizing like Fawkes if needed
5. **Optional**: Look at Fawkes patterns for inspiration, but don't copy blindly

The current configuration is **good enough to get started**. Get the VMs running first, then iterate!
