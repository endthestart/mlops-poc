# Terraform Libvirt Provider v0.8.3 - Working Configuration

## ⚠️ Important: Use v0.8.3, NOT v0.9.0

After extensive troubleshooting, **libvirt provider v0.8.3 is the recommended stable version**.

### Why v0.8.3?

- **v0.9.0 has critical bugs**:
  - Network interfaces change type from "network" to "user" unexpectedly
  - Graphics configuration becomes null after apply
  - Provider produces inconsistent results after apply
  - See: "Provider produced inconsistent result after apply" errors

- **v0.8.3 is stable and working**:
  - Mature, well-tested version
  - Syntax is similar to v0.7.x
  - No known critical bugs
  - Successfully deploys VMs

### Version Configuration

**terraform/main.tf:**
```hcl
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"  # Pin to this specific version
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
```

---

## Working v0.8.3 Configuration

### storage.tf

```hcl
# Storage pool on SMB mount
resource "libvirt_pool" "mlops" {
  name = "mlops-pool"
  type = "dir"
  
  target {  # v0.8.3: target is a BLOCK, not an attribute
    path = var.smb_storage_path
  }
}

# Base Ubuntu cloud image
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-base.qcow2"
  pool   = libvirt_pool.mlops.name
  source = var.ubuntu_image  # v0.8.3: use source for URLs
  format = "qcow2"
}

# VM disks (created from base image)
resource "libvirt_volume" "master_disk" {
  name           = "${var.vm_master.name}.qcow2"
  pool           = libvirt_pool.mlops.name
  base_volume_id = libvirt_volume.ubuntu_base.id  # v0.8.3: use base_volume_id
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
```

### cloudinit.tf

```hcl
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
```

### cloud-init.yaml

**IMPORTANT: You MUST add your SSH public key to this file!**

```yaml
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    home: /home/ubuntu
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2E... # REPLACE WITH YOUR PUBLIC KEY!

# Set password for ubuntu user (optional, for console access)
chpasswd:
  list: |
    ubuntu:ubuntu
  expire: false

# Configure network via DHCP
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true

# Install basic packages
packages:
  - qemu-guest-agent
  - vim
  - curl
  - wget

# Enable services
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

# Set hostname (will be overridden per VM)
hostname: mlops-node
```

**To add your SSH key:**
```bash
# Copy your public key
cat ~/.ssh/id_rsa.pub

# Edit cloud-init.yaml and paste it in the ssh_authorized_keys section
```

### vms.tf

```hcl
# VM configuration for libvirt provider v0.8.3

# Master VM
resource "libvirt_domain" "master" {
  name   = var.vm_master.name
  memory = var.vm_master.memory
  vcpu   = var.vm_master.vcpu

  # Attach cloud-init disk for initial configuration
  cloudinit = libvirt_cloudinit_disk.commoninit.id

  # v0.8.3: network_interface as a BLOCK (singular)
  network_interface {
    network_name   = "mlops-net"
    mac            = "52:54:00:00:00:01"
    wait_for_lease = true
  }

  # v0.8.3: disk as a BLOCK (singular)
  disk {
    volume_id = libvirt_volume.master_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  # v0.8.3: graphics as a BLOCK (singular)
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

  cloudinit = libvirt_cloudinit_disk.commoninit.id

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

  cloudinit = libvirt_cloudinit_disk.commoninit.id

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
```

---

## Key Syntax Differences: v0.8.3 vs v0.9.0

| Feature | v0.8.3 Syntax | v0.9.0 Syntax |
|---------|---------------|---------------|
| **Pool path** | `target { path = "..." }` (block) | `target = { path = "..." }` (attribute) |
| **Volume source** | `source = url` | `create = { content = { url = url } }` |
| **Volume size** | `size = bytes` | `capacity = bytes` |
| **Backing volume** | `base_volume_id = id` | `backing_store = { path, format }` |
| **Network** | `network_interface {}` (block) | `interfaces = [{}]` (array in devices) |
| **Disk** | `disk {}` (block) | `disks = [{}]` (array in devices) |
| **Graphics** | `graphics {}` (block) | `graphics = {}` (object in devices) |
| **VM devices** | Separate blocks | Single `devices = {}` object |

---

## Switching Versions

### From v0.9.0 to v0.8.3

If you need to downgrade (like we did):

```bash
cd terraform

# 1. Destroy any existing v0.9.0 resources
terraform destroy

# 2. Edit main.tf to specify v0.8.3
# version = "0.8.3"

# 3. Remove cached provider and lock file
rm -rf .terraform .terraform.lock.hcl
rm terraform.tfstate terraform.tfstate.backup  # Only if destroy completed

# 4. Reinitialize
terraform init

# 5. Verify version
terraform version
# Should show: provider registry.terraform.io/dmacvicar/libvirt v0.8.3

# 6. Update config files to v0.8.3 syntax
# (See working config above)

# 7. Plan and apply
terraform plan
terraform apply
```

### Critical: State File Incompatibility

**v0.8.3 and v0.9.0 state files are NOT compatible!**

If you get errors like:
```
Error: missing expected [
```

This usually means you have a v0.9.0 state file but v0.8.3 provider (or vice versa).

**Solution:**
1. Destroy with the old version
2. Switch versions
3. Start fresh with new state

---

## Prerequisites Setup (Arch Linux)

### Required Packages

```bash
# Core virtualization
sudo pacman -S qemu-base qemu-system-x86 libvirt virt-manager

# Networking and dependencies
sudo pacman -S bridge-utils dnsmasq iptables-nft ebtables

# UEFI firmware (optional, for EFI boot)
sudo pacman -S ovmf

# Infrastructure as Code
sudo pacman -S terraform

# System tools
sudo pacman -S dmidecode
```

### Enable KVM

```bash
# Check if CPU supports virtualization
grep -E 'vmx|svm' /proc/cpuinfo

# If nothing appears, enable in BIOS:
# - Intel: Enable VT-x and VT-d
# - AMD: Enable SVM and IOMMU

# Load KVM module (Intel)
sudo modprobe kvm_intel

# Or for AMD
sudo modprobe kvm_amd

# Make it permanent
echo "kvm_intel" | sudo tee /etc/modules-load.d/kvm.conf  # Intel
# OR
echo "kvm_amd" | sudo tee /etc/modules-load.d/kvm.conf    # AMD

# Verify /dev/kvm exists
ls -l /dev/kvm
```

### User Permissions

```bash
# Add user to required groups
sudo usermod -aG kvm,libvirt $USER

# Log out and back in for groups to take effect
# Verify groups
groups  # Should show kvm and libvirt

# Verify access to /dev/kvm
ls -l /dev/kvm
# Should show: crw-rw---- 1 root kvm
```

### Start libvirtd

```bash
# Enable and start libvirtd service
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Verify it's running
sudo systemctl status libvirtd

# Test connection
virsh list --all
```

### Create libvirt Network

```bash
# Define network from XML
sudo virsh net-define network.xml

# Start network
sudo virsh net-start mlops-net

# Set to autostart
sudo virsh net-autostart mlops-net

# Verify
virsh net-list
```

---

## Common Issues & Solutions

### Issue: "Operation not supported" when loading kvm_amd/kvm_intel

**Cause:** Virtualization disabled in BIOS  
**Fix:** Reboot into BIOS/UEFI and enable:
- Intel: VT-x, VT-d
- AMD: SVM, IOMMU

### Issue: `/dev/kvm` doesn't exist

**Cause:** KVM module not loaded or udev rules missing  
**Fix:**
```bash
# Manually create device (temporary)
sudo mknod /dev/kvm c 10 232
sudo chmod 666 /dev/kvm

# Permanent fix: Create udev rule
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666"' | sudo tee /etc/udev/rules.d/99-kvm.rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Reboot
sudo reboot
```

### Issue: "missing expected [" error

**Cause:** State file from different provider version  
**Fix:**
```bash
terraform destroy  # Clean up with old version first
# OR
rm terraform.tfstate terraform.tfstate.backup
```

### Issue: "Provider produced inconsistent result after apply"

**Cause:** Using v0.9.0 (it's buggy)  
**Fix:** Downgrade to v0.8.3 (see "Switching Versions" above)

### Issue: Can't access VMs via SSH

**Cause:** No SSH keys configured in VMs  
**Fix:** 
- Use cloud-init to add SSH keys (add to config)
- Or use `virsh console <vm-name>` to access VM console directly

### Issue: VMs boot but have no IP address / DHCP not working

**Cause:** Ubuntu cloud images require cloud-init to configure networking. Without cloud-init, VMs boot but don't configure their network interfaces.  
**Symptoms:**
- VMs appear in virt-manager and are fully booted
- `virsh net-dhcp-leases mlops-net` shows no leases
- VMs have no IP addresses
- Terraform hangs on "Still creating..." waiting for DHCP lease

**Fix:** Add cloud-init configuration with network setup (see cloudinit.tf and cloud-init.yaml above)

The cloud-init configuration:
1. Creates the `ubuntu` user with sudo access
2. Adds your SSH key for passwordless login
3. Configures network interface for DHCP
4. Installs qemu-guest-agent for better VM integration
5. Sets up basic packages

**Steps to add cloud-init:**
```bash
cd terraform

# 1. Add your SSH public key to cloud-init.yaml
cat ~/.ssh/id_rsa.pub
# Copy the output and paste into cloud-init.yaml ssh_authorized_keys section

# 2. Destroy existing VMs (they don't have cloud-init)
terraform destroy

# 3. Apply with cloud-init
terraform plan
terraform apply

# 4. VMs should now get IP addresses
virsh net-dhcp-leases mlops-net

# 5. SSH into VMs
ssh ubuntu@<vm-ip>
```

### Issue: VMs not getting IP addresses

**Cause:** Network not started or DHCP not configured  
**Fix:**
```bash
# Check network status
virsh net-list --all

# Start network if stopped
virsh net-start mlops-net

# Check DHCP leases
virsh net-dhcp-leases mlops-net

# Restart VMs if needed
virsh reboot <vm-name>
```

---

## Verification Steps

After `terraform apply`:

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

# 6. Access VM console (Ctrl+] to exit)
virsh console k3s-master

# 7. Check if VMs are accessible via SSH (once configured)
ssh ubuntu@<vm-ip>
```

---

## Next Steps After VM Creation

1. **Configure SSH access** (cloud-init or manual)
2. **Install K3s** on all nodes
3. **Configure GPU passthrough** for k3s-gpu-worker
4. **Deploy workloads**
5. **Set up monitoring** (VictoriaMetrics + Grafana)

---

## Summary

- ✅ **Use v0.8.3** - stable and working
- ❌ **Avoid v0.9.0** - has critical bugs
- 🔧 **Syntax**: Blocks (not objects) for network/disk/graphics
- 📦 **State files**: Not compatible between versions
- 🐧 **Arch setup**: Enable KVM in BIOS, install packages, add user to groups
- 🔍 **Debug**: Check /dev/kvm, virsh commands, terraform state

The configuration is now working and ready for VM deployment!
