# MLOps POC: GPU-Accelerated Model Inference

> **⚠️ IMPORTANT: Terraform Provider Version Note**
> This plan was written for libvirt provider v0.7.x, but if you have **v0.9.0** (like the user discovered), the syntax is **completely different**.
> See **[TERRAFORM-V09-FIXES.md](TERRAFORM-V09-FIXES.md)** for working v0.9.0 configuration examples and migration guide.
> The Terraform examples in Steps 1.3 below may not work with v0.9.0 - use the corrected syntax from the fixes document.

> **✅ LESSONS LEARNED (2025-11-20)**
>
> **Critical Issues Discovered:**
> 1. **Unique Hostnames Required**: All VMs MUST have unique hostnames. k3s uses hostnames for node identification. If all VMs have the same hostname (e.g., `mlops-node`), workers cannot join the cluster (error: "duplicate hostname or contents of '/etc/rancher/node/password' may not match").
>
> 2. **Solution**: Use separate cloud-init disks for each VM with templated hostnames:
>    - Master: `k3s-master`
>    - GPU Worker: `k3s-gpu-worker`
>    - Worker: `k3s-worker`
>
> 3. **SSH Host Key Management**: When recreating VMs frequently, disable strict host key checking for the VM subnet in `~/.ssh/config`:
>    ```
>    Host 192.168.100.*
>        StrictHostKeyChecking no
>        UserKnownHostsFile /dev/null
>    ```
>
> 4. **Idempotency Strategy**: For learning POCs, embrace `terraform destroy && terraform apply` as a reset button rather than fighting for perfect Ansible idempotency. Use helper scripts (`rebuild-cluster.sh`, `reinstall-k3s.sh`).
>
> 5. **Token Management**: k3s tokens include CA hashes. If you rebuild the master, workers need fresh tokens. The simplified worker playbook auto-detects token mismatches and reinstalls cleanly.
>
> **Working Configuration:**
> - See `terraform/cloudinit.tf` for per-VM cloud-init disk creation
> - See `terraform/cloud-init.yaml` for hostname templating with `${hostname}`
> - See `scripts/rebuild-cluster.sh` for full cluster rebuild workflow
> - See `scripts/reinstall-k3s.sh` for k3s-only reinstall

## 🎯 Project Goals
Build a production-like MLOps infrastructure for model inference using GPU acceleration on a local baremetal host.

### Learning Objectives
- Deploy infrastructure as code using Terraform + Libvirt
- Configure GPU passthrough to VMs
- Set up Kubernetes cluster (k3s) across VMs
- Deploy GPU-accelerated inference services
- Implement monitoring and observability
- (Optional) Add distributed inference with Ray

### Architecture Overview
```
Baremetal Host (NVIDIA 4080 Super)
├── k3s-master (VM1: Control Plane)
│   ├── K3s Server
│   └── Cluster State Management
├── k3s-gpu-worker (VM2: GPU Worker)
│   ├── K3s Agent
│   ├── GPU Passthrough (4080 Super)
│   └── Inference Workloads
└── k3s-worker (VM3: Services Worker)
    ├── K3s Agent
    ├── VictoriaMetrics + Grafana
    └── Supporting Services
```

---

## 📁 Recommended Project Structure

```
mlops-poc/
├── terraform/                      # Infrastructure as Code
│   ├── main.tf                    # Main Terraform config
│   ├── variables.tf               # Variable definitions
│   ├── network.tf                 # Network configuration (bridge/VLAN)
│   ├── vms.tf                     # VM definitions
│   ├── storage.tf                 # Storage pools and volumes
│   └── outputs.tf                 # Output values
│
├── ansible/                       # Configuration Management (optional)
│   ├── inventory/
│   │   └── hosts.yml             # VM inventory
│   ├── playbooks/
│   │   ├── setup-k3s.yml         # K3s installation
│   │   ├── setup-gpu.yml         # GPU drivers & device plugin
│   │   └── setup-monitoring.yml  # Prometheus/Grafana
│   └── roles/                    # Ansible roles
│
├── k8s/                          # Kubernetes Manifests
│   ├── namespaces/
│   │   ├── inference.yaml
│   │   └── monitoring.yaml
│   ├── storage/
│   │   ├── smb-secret.yaml       # SMB credentials (gitignored)
│   │   ├── smb-storageclass.yaml # SMB StorageClass
│   │   ├── test-pvc.yaml         # Test PVC
│   │   └── test-pod.yaml         # Test pod
│   ├── gpu/
│   │   ├── nvidia-device-plugin.yaml
│   │   └── gpu-test-pod.yaml
│   ├── inference/
│   │   ├── deployment.yaml       # Model serving deployment
│   │   ├── service.yaml
│   │   ├── pvc.yaml              # Persistent volume claims
│   │   └── configmap.yaml        # Model configurations
│   ├── monitoring/
│   │   ├── victoriametrics/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── rbac.yaml
│   │   │   ├── configmap.yaml
│   │   │   └── pvc.yaml          # VictoriaMetrics data on SMB
│   │   └── grafana/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── dashboards/
│   └── ray/                      # Optional: Ray cluster
│       ├── ray-cluster.yaml
│       └── ray-service.yaml
│
├── inference-service/            # Inference API Code
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── app/
│   │   ├── main.py              # FastAPI application
│   │   ├── model.py             # Model loading & inference
│   │   └── config.py            # Configuration
│   ├── models/                  # Model storage (gitignored)
│   └── tests/
│       └── test_inference.py
│
├── scripts/                      # Utility Scripts
│   ├── setup-host.sh            # Host prerequisites
│   ├── gpu-passthrough.sh       # GPU passthrough setup
│   ├── deploy-k3s.sh            # K3s deployment script
│   ├── test-gpu.sh              # GPU functionality tests
│   └── cleanup.sh               # Teardown script
│
├── docs/                         # Documentation
│   ├── 00-prerequisites.md
│   ├── 01-infrastructure.md
│   ├── 02-gpu-setup.md
│   ├── 03-k8s-deployment.md
│   ├── 04-inference-deployment.md
│   ├── 05-monitoring.md
│   └── troubleshooting.md
│
├── .gitignore
├── README.md                     # Quick start guide
└── PLAN.md                       # This file
```

---

## 🚀 Phase-by-Phase Implementation Plan

---

### **Phase 1: Host Prerequisites & Infrastructure Setup**
**Goal:** Prepare baremetal host and create VMs with Terraform

#### Step 1.1: Host System Preparation
**What you'll learn:** Linux kernel modules, IOMMU, GPU isolation

**Prerequisites:**
- Ubuntu 22.04+ or similar Linux distro
- NVIDIA 4080 Super installed
- CPU with virtualization support (Intel VT-x or AMD-V)
- IOMMU support enabled in BIOS

**Tasks:**
1. Enable IOMMU in BIOS/UEFI
2. Update GRUB for IOMMU and GPU isolation
   ```bash
   # Edit /etc/default/grub
   GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt vfio-pci.ids=10de:XXXX"
   # (Replace XXXX with your GPU's device ID)
   ```
3. Install required packages:
   ```bash
   sudo apt update
   sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils \
                       virt-manager ovmf terraform cifs-utils
   ```
4. Verify IOMMU groups:
   ```bash
   for d in /sys/kernel/iommu_groups/*/devices/*; do
     n=${d#*/iommu_groups/*}; n=${n%%/*}
     printf 'IOMMU Group %s ' "$n"
     lspci -nns "${d##*/}"
   done
   ```

**Checkpoint:**
- [ ] IOMMU enabled and GPU in isolated IOMMU group
- [x] Libvirt and KVM installed
- [x] User added to `libvirt` group
- [x] SMB/CIFS utilities installed

---

#### Step 1.1b: Mount SMB Storage for VM Disks
**What you'll learn:** Network storage integration, persistent mounts

**Prerequisites:**
- SMB share accessible on your 10Gb network
- Share credentials (username/password or guest access)
- Share path (e.g., `//nas.local/vmstore`)

**Tasks:**
1. Create mount point and credentials file:
   ```bash
   # Create directory for SMB mount
   sudo mkdir -p /mnt/storage

   # Create credentials file (more secure than command line)
   sudo nano /root/.smbcredentials
   ```

   Add to `/root/.smbcredentials`:
   ```
   username=your_smb_user
   password=your_smb_password
   domain=WORKGROUP
   ```

   Secure the credentials:
   ```bash
   sudo chmod 600 /root/.smbcredentials
   ```

2. Test mount manually:
   ```bash
   sudo mount -t cifs //YOUR_NAS_IP/vmstore /mnt/storage \
     -o credentials=/root/.smbcredentials,uid=libvirt-qemu,gid=kvm,file_mode=0660,dir_mode=0770

   # Verify mount
   df -h | grep smb-vmstore
   ls -la /mnt/storage
   ```

3. Make mount persistent in `/etc/fstab`:
   ```bash
   sudo nano /etc/fstab
   ```

   Add this line:
   ```
   //YOUR_NAS_IP/vmstore  /mnt/smb-vmstore  cifs  credentials=/root/.smbcredentials,uid=libvirt-qemu,gid=kvm,file_mode=0660,dir_mode=0770,_netdev,x-systemd.automount  0  0
   ```

   **Important flags explained:**
   - `uid=libvirt-qemu,gid=kvm` - Ensure libvirt can access files
   - `_netdev` - Wait for network before mounting
   - `x-systemd.automount` - Auto-mount on access

4. Test fstab entry:
   ```bash
   sudo umount /mnt/smb-vmstore
   sudo mount -a
   df -h | grep smb-vmstore
   ```

5. Create libvirt storage pool on SMB:
   ```bash
   # Create pool directory
   sudo mkdir -p /mnt/smb-vmstore/kvm/mlops-pool
   sudo chown libvirt-qemu:kvm /mnt/smb-vmstore/kvm/mlops-pool
   ```

**Checkpoint:**
- [x] SMB share mounted at `/mnt/smb-vmstore`
- [x] Mount persists after reboot
- [x] Libvirt user can read/write to mount
- [x] Pool directory created

---

#### Step 1.2: Network Setup
**What you'll learn:** Linux bridges, virtual networking, VLANs

**Choose Your Approach:**

**Option A: Simple Bridge (Recommended for POC)**
```bash
# Create a bridge network for VMs
sudo virsh net-define network.xml
sudo virsh net-start mlops-net
sudo virsh net-autostart mlops-net
```

**network.xml:**
```xml
<network>
  <name>mlops-net</name>
  <forward mode='nat'/>
  <bridge name='virbr-mlops' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.10' end='192.168.100.100'/>
      <host mac='52:54:00:00:00:01' name='k3s-master' ip='192.168.100.10'/>
      <host mac='52:54:00:00:00:02' name='k3s-gpu-worker' ip='192.168.100.11'/>
      <host mac='52:54:00:00:00:03' name='k3s-worker' ip='192.168.100.12'/>
    </dhcp>
  </ip>
</network>
```

**Option B: VLAN Setup (Advanced)**
- Document this for later if you want production-like networking

**Checkpoint:**
- [x] Network created and active
- [x] Static IPs configured via DHCP reservations

---

#### Step 1.3: Terraform Infrastructure
**What you'll learn:** IaC principles, Libvirt provider, resource management

**Create terraform/main.tf:**
```hcl
terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
```

**Create terraform/variables.tf:**
```hcl
variable "smb_storage_path" {
  description = "Path to SMB-mounted storage for VM disks"
  default     = "/mnt/smb-vmstore/mlops-pool"
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
  default = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
}
```

**Create terraform/storage.tf:**
```hcl
# Storage pool on SMB mount
resource "libvirt_pool" "mlops" {
  name = "mlops-pool"
  type = "dir"
  path = var.smb_storage_path
}

resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-base.qcow2"
  pool   = libvirt_pool.mlops.name
  source = var.ubuntu_image
  format = "qcow2"
}

# VM disks (created from base image)
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
```

**Note:** This uses the SMB-mounted path from `var.smb_storage_path`. All VM disks will be stored on your NAS over 10Gb network.

**Create terraform/cloudinit.tf:**
```hcl
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

# Cloud-init disk resources (one per VM for unique hostnames)
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
```

**Create terraform/vms.tf:**
```hcl
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

# GPU Worker VM (GPU passthrough added in Phase 7)
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
```

**Note:** Each VM now has its own cloud-init disk with a unique hostname. This is **critical** for k3s to work properly.

**Create terraform/cloud-init.yaml:**
```yaml
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    home: /home/ubuntu
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa YOUR_SSH_PUBLIC_KEY_HERE

package_update: true
package_upgrade: true

packages:
  - curl
  - wget
  - git
  - vim
  - htop

runcmd:
  - echo "VM initialized" > /tmp/cloud-init-done

# Set hostname (templated per VM - CRITICAL for k3s)
hostname: ${hostname}
```

**Deploy Infrastructure:**
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

**Verify unique hostnames:**
```bash
ssh ubuntu@192.168.100.10 'hostname'  # Should show: k3s-master
ssh ubuntu@192.168.100.11 'hostname'  # Should show: k3s-gpu-worker
ssh ubuntu@192.168.100.12 'hostname'  # Should show: k3s-worker
```

**Checkpoint:**
- [x] 3 VMs created and running
- [x] Can SSH into all VMs
- [x] VMs have network connectivity
- [x] **Each VM has a unique hostname** (critical for k3s)

---

### **Phase 2: Ansible Setup**
**Goal:** Set up Ansible for automated configuration management

**What you'll learn:** Configuration management, playbooks, inventory, idempotent operations

#### Step 2.1: Install Ansible on Host
```bash
# On your host machine
sudo apt update
sudo apt install -y ansible

# Verify installation
ansible --version
```

**Checkpoint:**
- [x] Ansible installed
- [x] Version 2.9+ confirmed

---

#### Step 2.2: Create Ansible Inventory
**Create ansible/inventory/hosts.yml:**
```yaml
all:
  children:
    k3s_cluster:
      children:
        master:
          hosts:
            k3s-master:
              ansible_host: 192.168.100.10
        workers:
          hosts:
            k3s-gpu-worker:
              ansible_host: 192.168.100.11
            k3s-worker:
              ansible_host: 192.168.100.12
      vars:
        ansible_user: ubuntu
        ansible_ssh_private_key_file: ~/.ssh/id_rsa
        ansible_python_interpreter: /usr/bin/python3
```
TODO: This should happen after the ansible.cfg step
TODO: The ansible_ssh_private_key_file doesn't need to be in there unless we are passing a unique key
**Test connectivity:**
```bash
cd ansible/
ansible all -i inventory/hosts.yml -m ping
```

**Checkpoint:**
- [x] Inventory file created
- [x] All nodes respond to ping

---

#### Step 2.3: Create Ansible Configuration
**Create ansible/ansible.cfg:**
```ini
[defaults]
inventory = inventory/hosts.yml
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
```

**Checkpoint:**
- [x] Configuration file created

---

### **Phase 3: Kubernetes (k3s) Cluster Setup with Ansible**
**Goal:** Deploy k3s cluster across 3 VMs using Ansible automation

#### Step 3.1: Create k3s Master Playbook
**Create ansible/playbooks/setup-k3s-master.yml:**
```yaml
---
- name: Install k3s on master node
  hosts: master
  become: yes
  tasks:
    - name: Download k3s installation script
      get_url:
        url: https://get.k3s.io
        dest: /tmp/k3s-install.sh
        mode: '0755'

    - name: Install k3s server
      shell: /tmp/k3s-install.sh
      environment:
        INSTALL_K3S_EXEC: "--write-kubeconfig-mode 644"
      args:
        creates: /usr/local/bin/k3s

    - name: Wait for k3s to be ready
      wait_for:
        path: /var/lib/rancher/k3s/server/node-token
        state: present
        timeout: 60

    - name: Get k3s node token
      slurp:
        src: /var/lib/rancher/k3s/server/node-token
      register: k3s_token

    - name: Save token to local file
      local_action:
        module: copy
        content: "{{ k3s_token.content | b64decode }}"
        dest: "/tmp/k3s-token"
      become: no

    - name: Verify k3s is running
      command: k3s kubectl get nodes
      register: nodes_output
      changed_when: false

    - name: Display cluster status
      debug:
        var: nodes_output.stdout_lines
```

**Run the playbook:**
```bash
cd ansible/
ansible-playbook playbooks/setup-k3s-master.yml
```

**Checkpoint:**
- [x] k3s master installed
- [x] Node token saved to /tmp/k3s-token
- [x] Master node shows as Ready

---

#### Step 3.2: Create k3s Worker Playbook
**Create ansible/playbooks/setup-k3s-workers.yml:**
```yaml
---
- name: Install k3s on worker nodes
  hosts: workers
  become: yes
  vars:
    k3s_master_ip: 192.168.100.10
    k3s_token: "{{ lookup('file', '/tmp/k3s-token') }}"
  tasks:
    - name: Download k3s installation script
      get_url:
        url: https://get.k3s.io
        dest: /tmp/k3s-install.sh
        mode: '0755'

    - name: Install k3s agent
      shell: /tmp/k3s-install.sh
      environment:
        K3S_URL: "https://{{ k3s_master_ip }}:6443"
        K3S_TOKEN: "{{ k3s_token }}"
      args:
        creates: /usr/local/bin/k3s

    - name: Wait for k3s agent to start
      systemd:
        name: k3s-agent
        state: started
        enabled: yes

    - name: Verify k3s agent is running
      systemd:
        name: k3s-agent
        state: started
      register: k3s_status

    - name: Display agent status
      debug:
        msg: "k3s-agent is {{ k3s_status.status.ActiveState }}"
```

**Run the playbook:**
```bash
ansible-playbook playbooks/setup-k3s-workers.yml
```

**Checkpoint:**
- [x] Workers joined cluster
- [x] All nodes show Ready status

---

#### Step 3.3: Label Nodes with Ansible
**Create ansible/playbooks/label-nodes.yml:**
```yaml
---
- name: Label Kubernetes nodes
  hosts: master
  become: yes
  tasks:
    - name: Label master node
      command: kubectl label nodes k3s-master node-role.kubernetes.io/control-plane=true --overwrite
      changed_when: false

    - name: Label GPU worker node
      command: kubectl label nodes k3s-gpu-worker node-role.kubernetes.io/gpu-worker=true --overwrite
      changed_when: false

    - name: Add accelerator label to GPU worker
      command: kubectl label nodes k3s-gpu-worker accelerator=nvidia --overwrite
      changed_when: false

    - name: Label standard worker node
      command: kubectl label nodes k3s-worker node-role.kubernetes.io/worker=true --overwrite
      changed_when: false

    - name: Get labeled nodes
      command: kubectl get nodes --show-labels
      register: nodes_labels
      changed_when: false

    - name: Display node labels
      debug:
        var: nodes_labels.stdout_lines
```

**Run the playbook:**
```bash
ansible-playbook playbooks/label-nodes.yml
```

**Checkpoint:**
- [x] All nodes labeled correctly
- [x] Labels verified with kubectl

---

#### Step 3.4: Helper Scripts for Cluster Management

**Create scripts/rebuild-cluster.sh** (full reset):
```bash
#!/bin/bash
# Full cluster rebuild script for mlops-poc

set -e

echo "=== MLOps POC Cluster Rebuild ==="
echo

# Destroy VMs
echo "Step 1: Destroying VMs with Terraform..."
cd terraform/
terraform destroy -auto-approve
echo

# Create VMs
echo "Step 2: Creating VMs with Terraform..."
terraform apply -auto-approve
echo

# Wait for VMs to be fully ready
echo "Step 3: Waiting for VMs to be ready..."
sleep 30
echo

# Setup k3s master
echo "Step 4: Installing k3s on master node..."
cd ../ansible/
ansible-playbook playbooks/setup-k3s-master.yml
echo

# Setup k3s workers
echo "Step 5: Installing k3s on worker nodes..."
ansible-playbook playbooks/setup-k3s-workers.yml
echo

# Label nodes
echo "Step 6: Labeling nodes..."
ansible-playbook playbooks/label-nodes.yml
echo

# Verify cluster
echo "Step 7: Verifying cluster..."
ssh ubuntu@192.168.100.10 'kubectl get nodes'
echo

echo "=== Cluster rebuild complete! ==="
```

**Create scripts/reinstall-k3s.sh** (quick k3s reinstall without destroying VMs):
```bash
#!/bin/bash
# Quick k3s re-deployment (VMs stay up, k3s gets reinstalled)

set -e

echo "=== Quick k3s Reinstall ==="
echo

# Uninstall k3s from all nodes
echo "Step 1: Uninstalling k3s from all nodes..."
ssh ubuntu@192.168.100.10 '/usr/local/bin/k3s-uninstall.sh' 2>/dev/null || echo "Master already clean"
ssh ubuntu@192.168.100.11 '/usr/local/bin/k3s-agent-uninstall.sh' 2>/dev/null || echo "Worker 1 already clean"
ssh ubuntu@192.168.100.12 '/usr/local/bin/k3s-agent-uninstall.sh' 2>/dev/null || echo "Worker 2 already clean"
echo

# Wait for cleanup
echo "Step 2: Waiting for cleanup..."
sleep 5
echo

# Reinstall k3s
echo "Step 3: Installing k3s on master node..."
cd ansible/
ansible-playbook playbooks/setup-k3s-master.yml
echo

echo "Step 4: Installing k3s on worker nodes..."
ansible-playbook playbooks/setup-k3s-workers.yml
echo

echo "Step 5: Labeling nodes..."
ansible-playbook playbooks/label-nodes.yml
echo

# Verify
echo "Step 6: Verifying cluster..."
ssh ubuntu@192.168.100.10 'kubectl get nodes'
echo

echo "=== k3s reinstall complete! ==="
```

**Make scripts executable:**
```bash
chmod +x scripts/rebuild-cluster.sh
chmod +x scripts/reinstall-k3s.sh
```

**Usage:**
```bash
# Full rebuild (destroys and recreates VMs)
./scripts/rebuild-cluster.sh

# Quick k3s reinstall (keeps VMs, reinstalls k3s)
./scripts/reinstall-k3s.sh
```

**Checkpoint:**
- [x] Helper scripts created
- [x] Scripts are executable
- [x] Cluster can be rebuilt with one command

---

### **Phase 3.5: PostgreSQL as External Datastore (Optional - Recommended for Scale)**
**Goal:** Configure k3s to use PostgreSQL instead of embedded SQLite for cluster state

**Why add this?**
- **High Availability**: PostgreSQL supports HA configurations and clustering
- **Performance at Scale**: Better performance for large clusters with many resources
- **Backup/Recovery**: Enterprise-grade backup and point-in-time recovery
- **Multi-master Support**: Enables multiple k3s server nodes (HA control plane)
- **Production Ready**: Recommended for production workloads and GPU computing at scale

**Reference:** [k3s Datastore Documentation](https://docs.k3s.io/datastore)

#### Step 3.5.1: Deploy PostgreSQL Server

**Option A: Deploy PostgreSQL on Host (Recommended for POC)**
```bash
# Install PostgreSQL on baremetal host
sudo apt update
sudo apt install -y postgresql postgresql-contrib

# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create k3s database and user
sudo -u postgres psql <<EOF
CREATE DATABASE k3s;
CREATE USER k3s_user WITH ENCRYPTED PASSWORD 'your_secure_password_here';
GRANT ALL PRIVILEGES ON DATABASE k3s TO k3s_user;
\q
EOF

# Configure PostgreSQL to allow connections from VM network
sudo nano /etc/postgresql/*/main/postgresql.conf
# Set: listen_addresses = '*'

sudo nano /etc/postgresql/*/main/pg_hba.conf
# Add: host k3s k3s_user 192.168.100.0/24 scram-sha-256

# Restart PostgreSQL
sudo systemctl restart postgresql

# Test connection from master VM
psql -h <HOST_IP> -U k3s_user -d k3s
```

**Option B: Deploy PostgreSQL as Docker Container on Host**
```bash
# Run PostgreSQL container
docker run -d \
  --name k3s-postgres \
  --restart unless-stopped \
  -e POSTGRES_DB=k3s \
  -e POSTGRES_USER=k3s_user \
  -e POSTGRES_PASSWORD=your_secure_password_here \
  -p 5432:5432 \
  -v /var/lib/k3s-postgres:/var/lib/postgresql/data \
  postgres:16-alpine

# Verify
docker logs k3s-postgres
```

**Option C: Deploy PostgreSQL in Kubernetes (Advanced - HA Setup)**
```bash
# Deploy PostgreSQL operator (e.g., CloudNativePG, Zalando)
# This is more complex but provides HA and automatic failover
# Recommended for production multi-master k3s deployments
```

#### Step 3.5.2: Configure k3s to Use PostgreSQL

**Update ansible/playbooks/setup-k3s-master.yml:**
```yaml
---
- name: Install k3s on master node with PostgreSQL datastore
  hosts: master
  become: yes
  vars:
    postgres_host: "192.168.100.1"  # Your baremetal host IP or postgres server IP
    postgres_user: "k3s_user"
    postgres_password: "your_secure_password_here"  # Use ansible-vault in production!
    postgres_db: "k3s"
  tasks:
    - name: Download k3s installation script
      get_url:
        url: https://get.k3s.io
        dest: /tmp/k3s-install.sh
        mode: '0755'

    - name: Install k3s server with PostgreSQL datastore
      shell: /tmp/k3s-install.sh
      environment:
        INSTALL_K3S_EXEC: "--write-kubeconfig-mode 644 --datastore-endpoint='postgres://{{ postgres_user }}:{{ postgres_password }}@{{ postgres_host }}:5432/{{ postgres_db }}'"
      args:
        creates: /usr/local/bin/k3s

    - name: Wait for k3s to be ready
      wait_for:
        path: /var/lib/rancher/k3s/server/node-token
        state: present
        timeout: 60

    - name: Get k3s node token
      slurp:
        src: /var/lib/rancher/k3s/server/node-token
      register: k3s_token

    - name: Save token to local file
      local_action:
        module: copy
        content: "{{ k3s_token.content | b64decode }}"
        dest: "/tmp/k3s-token"
      become: no

    - name: Verify k3s is running
      command: k3s kubectl get nodes
      register: nodes_output
      changed_when: false

    - name: Display cluster status
      debug:
        var: nodes_output.stdout_lines
```

**Security Best Practice: Use Ansible Vault for Credentials**
```bash
# Store PostgreSQL password in encrypted vault
ansible-vault create ansible/vars/secrets.yml

# Add to secrets.yml:
postgres_password: "your_secure_password_here"

# Reference in playbook:
# vars_files:
#   - vars/secrets.yml

# Run playbook with vault password:
ansible-playbook playbooks/setup-k3s-master.yml --ask-vault-pass
```

#### Step 3.5.3: Verify PostgreSQL Datastore

```bash
# Check k3s is using PostgreSQL
ssh ubuntu@192.168.100.10 'sudo systemctl status k3s | grep datastore'

# Connect to PostgreSQL and verify k3s tables
psql -h <POSTGRES_HOST> -U k3s_user -d k3s -c "\dt"

# You should see k3s tables like:
# - kine (stores Kubernetes resources)
```

#### Step 3.5.4: Enable HA Control Plane (Optional - Advanced)

Once PostgreSQL is configured, you can add additional k3s server nodes for HA:

```yaml
# Add to Terraform: additional master nodes
# Update Ansible inventory with multiple masters
# All masters share the same PostgreSQL datastore

# Example: 3 master nodes + PostgreSQL = HA control plane
# Each master connects to same PostgreSQL database
```

**Checkpoint:**
- [ ] PostgreSQL installed and accessible from VMs
- [ ] k3s master configured with PostgreSQL datastore
- [ ] k3s tables visible in PostgreSQL database
- [ ] (Optional) Multiple k3s masters for HA

**Performance Note:**
For GPU computing at scale, PostgreSQL provides better performance when managing:
- Large numbers of pods and deployments
- Frequent resource updates (model deployments, experiments)
- Custom Resource Definitions (CRDs) for ML workflows
- Ray cluster coordination and job scheduling

---

### **Phase 4: SMB Storage for Kubernetes (Optional but Recommended)**
**Goal:** Configure SMB/CIFS storage for persistent volumes in Kubernetes

**Why add this?**
- Store model files on network storage (not in containers)
- Persistent storage for VictoriaMetrics data
- Share storage across pods if needed
- Keep your local VM disks lean

#### Step 4.1: Install SMB CSI Driver with Ansible
**Create ansible/playbooks/setup-smb-csi.yml:**
```yaml
---
- name: Install SMB CSI Driver
  hosts: master
  become: yes
  tasks:
    - name: Download SMB CSI install script
      get_url:
        url: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/deploy/install-driver.sh
        dest: /tmp/install-smb-csi.sh
        mode: '0755'

    - name: Install SMB CSI driver
      shell: /tmp/install-smb-csi.sh master snapshot
      args:
        creates: /tmp/smb-csi-installed

    - name: Mark installation complete
      file:
        path: /tmp/smb-csi-installed
        state: touch

    - name: Wait for CSI driver pods
      command: kubectl wait --for=condition=ready pod -l app=csi-smb-controller -n kube-system --timeout=120s
      changed_when: false

    - name: Verify CSI driver installation
      command: kubectl get pods -n kube-system -l app=csi-smb-controller
      register: csi_pods
      changed_when: false

    - name: Display CSI pods
      debug:
        var: csi_pods.stdout_lines
```

**Run the playbook:**
```bash
ansible-playbook playbooks/setup-smb-csi.yml
```

**Checkpoint:**
- [x] SMB CSI driver installed
- [x] CSI driver pods running

---

#### Step 4.2: Create SMB Secret and StorageClass

**Create k8s/storage/smb-secret.yaml:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: smb-credentials
  namespace: kube-system
type: Opaque
stringData:
  username: your_smb_user
  password: your_smb_password
```

**Important:** Add `k8s/storage/smb-secret.yaml` to `.gitignore`!

**Create k8s/storage/smb-storageclass.yaml:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: smb
provisioner: smb.csi.k8s.io
parameters:
  source: "//YOUR_NAS_IP/k8s-data"  # Your SMB share path
  csi.storage.k8s.io/node-stage-secret-name: "smb-credentials"
  csi.storage.k8s.io/node-stage-secret-namespace: "kube-system"
  createSubDir: "true"
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=1000
  - gid=1000
```

**Deploy:**
```bash
kubectl apply -f k8s/storage/smb-secret.yaml
kubectl apply -f k8s/storage/smb-storageclass.yaml

# Verify
kubectl get storageclass
```

**Checkpoint:**
- [x] SMB credentials stored in secret
- [x] SMB StorageClass created
- [x] `kubectl get sc` shows `smb` storage class

---

#### Step 4.3: Test SMB Storage

**Create k8s/storage/test-pvc.yaml:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-smb-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: smb
  resources:
    requests:
      storage: 1Gi
```

**Create k8s/storage/test-pod.yaml:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-smb-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "echo 'SMB storage works!' > /data/test.txt && cat /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: smb-volume
      mountPath: /data
  volumes:
  - name: smb-volume
    persistentVolumeClaim:
      claimName: test-smb-pvc
```

**Test:**
```bash
kubectl apply -f k8s/storage/test-pvc.yaml
kubectl apply -f k8s/storage/test-pod.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/test-smb-pod --timeout=60s

# Check logs
kubectl logs test-smb-pod
# Should output: "SMB storage works!"

# Verify file exists on NAS
# Check your NAS at /k8s-data/default-test-smb-pvc-*/test.txt

# Cleanup test resources
kubectl delete pod test-smb-pod
kubectl delete pvc test-smb-pvc
```

**Checkpoint:**
- [x] PVC created and bound
- [x] Pod can write to SMB storage
- [x] File visible on NAS
- [x] Test resources cleaned up

---

### **Phase 5: Model Inference Service**
**Create k8s/gpu/nvidia-device-plugin.yaml:**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      nodeSelector:
        accelerator: nvidia
      priorityClassName: system-node-critical
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.14.0
        name: nvidia-device-plugin-ctr
        env:
        - name: FAIL_ON_INIT_ERROR
          value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
```

**Deploy:**
```bash
kubectl apply -f k8s/gpu/nvidia-device-plugin.yaml

# Verify
kubectl get pods -n kube-system | grep nvidia
kubectl describe node k3s-gpu-worker | grep nvidia.com/gpu
```

**Expected Output:**
```
nvidia.com/gpu:     1
```

**Checkpoint:**
- [ ] Device plugin running
- [ ] GPU visible as allocatable resource

---

### **Phase 6: Monitoring & Observability**
**Goal:** Deploy a simple GPU-accelerated inference API

#### Step 5.1: Create Inference Service Code
**Create inference-service/requirements.txt:**
```txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
torch==2.1.0
torchvision==0.16.0
pillow==10.1.0
python-multipart==0.0.6
pydantic==2.5.0
```

**Create inference-service/app/main.py:**
```python
from fastapi import FastAPI, File, UploadFile
from PIL import Image
import torch
import torchvision.transforms as transforms
import torchvision.models as models
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="GPU Inference Service")

# Load model on startup
model = None
device = None

@app.on_event("startup")
async def load_model():
    global model, device

    # Check GPU availability
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logger.info(f"Using device: {device}")

    if torch.cuda.is_available():
        logger.info(f"GPU: {torch.cuda.get_device_name(0)}")
        logger.info(f"CUDA Version: {torch.version.cuda}")

    # Load pretrained ResNet50
    model = models.resnet50(pretrained=True)
    model.to(device)
    model.eval()
    logger.info("Model loaded successfully")

@app.get("/")
async def root():
    return {
        "service": "GPU Inference API",
        "model": "ResNet50",
        "device": str(device),
        "gpu_available": torch.cuda.is_available()
    }

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "gpu_available": torch.cuda.is_available(),
        "device": str(device)
    }

@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    try:
        # Read and preprocess image
        image_data = await file.read()
        image = Image.open(io.BytesIO(image_data)).convert('RGB')

        preprocess = transforms.Compose([
            transforms.Resize(256),
            transforms.CenterCrop(224),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
        ])

        input_tensor = preprocess(image)
        input_batch = input_tensor.unsqueeze(0).to(device)

        # Inference
        with torch.no_grad():
            output = model(input_batch)

        # Get top prediction
        probabilities = torch.nn.functional.softmax(output[0], dim=0)
        top_prob, top_class = torch.topk(probabilities, 1)

        return {
            "prediction": {
                "class_id": int(top_class[0]),
                "confidence": float(top_prob[0])
            },
            "device_used": str(device)
        }

    except Exception as e:
        logger.error(f"Prediction error: {str(e)}")
        return {"error": str(e)}, 500

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

**Create inference-service/Dockerfile:**
```dockerfile
FROM nvidia/cuda:12.0.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Build and Push (from host or CI/CD):**
```bash
cd inference-service/

# Build
docker build -t mlops-inference:v1 .

# Save and load on k3s nodes (or use registry)
docker save mlops-inference:v1 | gzip > mlops-inference-v1.tar.gz

# Copy to all nodes and load
for node in 192.168.100.10 192.168.100.11 192.168.100.12; do
  scp mlops-inference-v1.tar.gz ubuntu@$node:/tmp/
  ssh ubuntu@$node "sudo k3s ctr images import /tmp/mlops-inference-v1.tar.gz"
done
```

**Checkpoint:**
- [ ] Inference service code created
- [ ] Docker image built
- [ ] Image available on k3s nodes

---

#### Step 5.2: Deploy Inference Service to Kubernetes
**Create k8s/namespaces/inference.yaml:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: inference
```

**Create k8s/inference/deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-service
  namespace: inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: inference-service
  template:
    metadata:
      labels:
        app: inference-service
    spec:
      nodeSelector:
        accelerator: nvidia
      containers:
      - name: inference
        image: mlops-inference:v1
        imagePullPolicy: Never  # Using local image
        ports:
        - containerPort: 8000
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "4Gi"
            cpu: "2"
          requests:
            nvidia.com/gpu: 1
            memory: "2Gi"
            cpu: "1"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 20
          periodSeconds: 5
```

**Create k8s/inference/service.yaml:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: inference-service
  namespace: inference
spec:
  type: NodePort
  selector:
    app: inference-service
  ports:
  - protocol: TCP
    port: 8000
    targetPort: 8000
    nodePort: 30080
```

**Deploy:**
```bash
kubectl apply -f k8s/namespaces/inference.yaml
kubectl apply -f k8s/inference/deployment.yaml
kubectl apply -f k8s/inference/service.yaml

# Verify
kubectl get pods -n inference
kubectl logs -n inference -l app=inference-service
```

**Test from host:**
```bash
# Get service
curl http://192.168.100.11:30080/

# Test with sample image
curl -X POST -F "file=@test-image.jpg" http://192.168.100.11:30080/predict
```

**Checkpoint:**
- [ ] Inference service deployed
- [ ] Pod running on GPU worker
- [ ] API accessible and returning predictions
- [ ] GPU being used (check logs)

---

### **Phase 6: Monitoring & Observability**
**Goal:** Deploy VictoriaMetrics and Grafana for cluster monitoring

**Why VictoriaMetrics?**
- Lower memory footprint (~7x less than Prometheus)
- Better compression and faster queries
- Prometheus-compatible (same PromQL, same exporters)
- Built-in de-duplication and downsampling

#### Step 6.1: Create Monitoring Namespace
**Create k8s/namespaces/monitoring.yaml:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
```

#### Step 6.2: Deploy VictoriaMetrics (Single-node)
**Create k8s/monitoring/victoriametrics/rbac.yaml:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: victoriametrics
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: victoriametrics
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - nodes/metrics
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources:
  - configmaps
  verbs: ["get"]
- nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: victoriametrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: victoriametrics
subjects:
- kind: ServiceAccount
  name: victoriametrics
  namespace: monitoring
```

**Create k8s/monitoring/victoriametrics/configmap.yaml:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: victoriametrics-config
  namespace: monitoring
data:
  scrape.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: mlops-poc

    scrape_configs:
      # Scrape VictoriaMetrics itself
      - job_name: 'victoriametrics'
        static_configs:
          - targets: ['localhost:8428']

      # Kubernetes pods with prometheus.io/scrape annotation
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: kubernetes_namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: kubernetes_pod_name

      # Kubernetes nodes
      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)

      # Kubernetes node cAdvisor
      - job_name: 'kubernetes-cadvisor'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        metrics_path: /metrics/cadvisor
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)

      # NVIDIA DCGM GPU metrics
      - job_name: 'dcgm-exporter'
        static_configs:
          - targets: ['dcgm-exporter:9400']
        relabel_configs:
          - source_labels: [__address__]
            target_label: instance
            replacement: 'gpu-worker'
```

**Create k8s/monitoring/victoriametrics/deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: victoriametrics
  namespace: monitoring
  labels:
    app: victoriametrics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: victoriametrics
  template:
    metadata:
      labels:
        app: victoriametrics
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: "true"
      serviceAccountName: victoriametrics
      containers:
      - name: victoriametrics
        image: victoriametrics/victoria-metrics:v1.93.0
        args:
          - -storageDataPath=/storage
          - -retentionPeriod=14d
          - -httpListenAddr=:8428
          - -promscrape.config=/config/scrape.yml
          - -memory.allowedPercent=60
        ports:
        - name: http
          containerPort: 8428
        volumeMounts:
        - name: storage
          mountPath: /storage
        - name: config
          mountPath: /config
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /health
            port: 8428
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8428
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: storage
        emptyDir: {}
      - name: config
        configMap:
          name: victoriametrics-config
```

**Optional: Use SMB for VictoriaMetrics data persistence**

If you completed Phase 4b (SMB storage), you can persist VictoriaMetrics data to your NAS:

**Create k8s/monitoring/victoriametrics/pvc.yaml:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: victoriametrics-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: smb
  resources:
    requests:
      storage: 10Gi
```

**Update the deployment to use PVC instead of emptyDir:**
Replace the `volumes` section in the deployment with:
```yaml
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: victoriametrics-data
      - name: config
        configMap:
          name: victoriametrics-config
```

**Deploy with PVC:**
```bash
kubectl apply -f k8s/monitoring/victoriametrics/pvc.yaml
# Wait for PVC to bind
kubectl get pvc -n monitoring
# Then deploy VictoriaMetrics
kubectl apply -f k8s/monitoring/victoriametrics/deployment.yaml
```

**Create k8s/monitoring/victoriametrics/service.yaml:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: victoriametrics
  namespace: monitoring
  labels:
    app: victoriametrics
spec:
  type: NodePort
  selector:
    app: victoriametrics
  ports:
  - name: http
    port: 8428
    targetPort: 8428
    nodePort: 30428
    protocol: TCP
```

**Deploy VictoriaMetrics:**
```bash
kubectl apply -f k8s/namespaces/monitoring.yaml
kubectl apply -f k8s/monitoring/victoriametrics/rbac.yaml
kubectl apply -f k8s/monitoring/victoriametrics/configmap.yaml
kubectl apply -f k8s/monitoring/victoriametrics/deployment.yaml
kubectl apply -f k8s/monitoring/victoriametrics/service.yaml

# Verify
kubectl get pods -n monitoring
kubectl logs -n monitoring -l app=victoriametrics
```

**Access VictoriaMetrics UI:** http://192.168.100.12:30428

**Test queries:**
```bash
# From host, test VictoriaMetrics API
curl http://192.168.100.12:30428/api/v1/query?query=up

# Should return JSON with metrics
```

**Checkpoint:**
- [ ] VictoriaMetrics deployed
- [ ] VictoriaMetrics UI accessible
- [ ] Scraping Kubernetes metrics
- [ ] `/api/v1/query` endpoint responding

---

#### Step 6.3: Deploy NVIDIA DCGM Exporter (GPU Metrics)
**Create k8s/monitoring/dcgm-exporter.yaml:**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dcgm-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: dcgm-exporter
  template:
    metadata:
      labels:
        app: dcgm-exporter
    spec:
      nodeSelector:
        accelerator: nvidia
      containers:
      - name: dcgm-exporter
        image: nvcr.io/nvidia/k8s/dcgm-exporter:3.1.8-3.1.5-ubuntu20.04
        ports:
        - containerPort: 9400
          name: metrics
        securityContext:
          privileged: true
        env:
        - name: DCGM_EXPORTER_LISTEN
          value: ":9400"
        resources:
          limits:
            nvidia.com/gpu: 1
---
apiVersion: v1
kind: Service
metadata:
  name: dcgm-exporter
  namespace: monitoring
spec:
  selector:
    app: dcgm-exporter
  ports:
  - port: 9400
    targetPort: 9400
    name: metrics
```

**Deploy:**
```bash
kubectl apply -f k8s/monitoring/dcgm-exporter.yaml

# Test GPU metrics
kubectl port-forward -n monitoring svc/dcgm-exporter 9400:9400 &
curl localhost:9400/metrics | grep DCGM
```

**Checkpoint:**
- [ ] DCGM exporter running on GPU worker
- [ ] GPU metrics available

---

#### Step 6.4: Deploy Grafana
**Create k8s/monitoring/grafana/deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: "true"
      containers:
      - name: grafana
        image: grafana/grafana:10.1.0
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: admin  # Change this!
        - name: GF_INSTALL_PLUGINS
          value: "grafana-piechart-panel"
        volumeMounts:
        - name: storage
          mountPath: /var/lib/grafana
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
      volumes:
      - name: storage
        emptyDir: {}
```

**Create k8s/monitoring/grafana/service.yaml:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  type: NodePort
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30030
```

**Deploy:**
```bash
kubectl apply -f k8s/monitoring/grafana/deployment.yaml
kubectl apply -f k8s/monitoring/grafana/service.yaml
```

**Access Grafana:** http://192.168.100.12:30030
- Username: `admin`
- Password: `admin`

**Configure Data Source:**
1. Add Prometheus data source (VictoriaMetrics is Prometheus-compatible)
2. URL: `http://victoriametrics:8428`
3. Save & Test

**Import Dashboards:**
- Kubernetes cluster monitoring: Dashboard ID `15759`
- NVIDIA DCGM Exporter: Dashboard ID `12239`

**Checkpoint:**
- [ ] Grafana accessible
- [ ] VictoriaMetrics data source configured
- [ ] Dashboards showing metrics
- [ ] GPU metrics visible in dashboard

---

### **Phase 7: GPU Passthrough Configuration**
**Goal:** Pass NVIDIA 4080 Super to gpu-worker VM

**What you'll learn:** PCI passthrough, IOMMU, VFIO drivers, GPU virtualization

#### Step 7.1: Identify GPU PCI Address
```bash
# Find GPU PCI address
lspci -nnk | grep -i nvidia

# Example output:
# 01:00.0 VGA compatible controller [0300]: NVIDIA Corporation ... [10de:2704]
# 01:00.1 Audio device [0403]: NVIDIA Corporation ... [10de:22bc]

# Note both IDs (GPU and audio): 10de:2704,10de:22bc
```

#### Step 7.2: Bind GPU to VFIO Driver
```bash
# Load VFIO modules
sudo modprobe vfio-pci

# Update /etc/modprobe.d/vfio.conf
echo "options vfio-pci ids=10de:2704,10de:22bc" | sudo tee /etc/modprobe.d/vfio.conf

# Blacklist nouveau driver
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf

# Update initramfs and reboot
sudo update-initramfs -u
sudo reboot
```

#### Step 7.3: Add GPU to Terraform VM Definition
**Update terraform/vms.tf for gpu_worker:**

Add this to the `libvirt_domain.gpu_worker` resource:
```hcl
  xml {
    xslt = <<-EOT
<?xml version="1.0" ?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output omit-xml-declaration="yes" indent="yes"/>
  <xsl:template match="node()|@*">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/domain/devices">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>
      <hostdev mode='subsystem' type='pci' managed='yes'>
        <source>
          <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
        </source>
      </hostdev>
      <hostdev mode='subsystem' type='pci' managed='yes'>
        <source>
          <address domain='0x0000' bus='0x01' slot='0x00' function='0x1'/>
        </source>
      </hostdev>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
EOT
  }
```

**Note:** Adjust PCI addresses to match your `lspci` output.

**Re-apply Terraform:**
```bash
terraform apply
```

**Checkpoint:**
- [ ] GPU bound to vfio-pci driver on host
- [ ] VM recreated with GPU passthrough
- [ ] `lspci` in gpu-worker VM shows NVIDIA GPU

---

#### Step 7.4: Install NVIDIA Drivers in GPU Worker VM with Ansible
**Create ansible/playbooks/setup-nvidia-drivers.yml:**
```yaml
---
- name: Install NVIDIA drivers on GPU worker
  hosts: k3s-gpu-worker
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install ubuntu-drivers-common
      apt:
        name: ubuntu-drivers-common
        state: present

    - name: Install NVIDIA drivers
      command: ubuntu-drivers install
      args:
        creates: /usr/bin/nvidia-smi

    - name: Check if reboot is required
      stat:
        path: /var/run/reboot-required
      register: reboot_required

    - name: Reboot if necessary
      reboot:
        reboot_timeout: 300
      when: reboot_required.stat.exists

    - name: Wait for system to come back
      wait_for_connection:
        delay: 30
        timeout: 300
      when: reboot_required.stat.exists

    - name: Verify NVIDIA driver installation
      command: nvidia-smi
      register: nvidia_output
      changed_when: false

    - name: Display nvidia-smi output
      debug:
        var: nvidia_output.stdout_lines
```

**Run the playbook:**
```bash
ansible-playbook playbooks/setup-nvidia-drivers.yml
```

**Checkpoint:**
- [ ] NVIDIA drivers installed
- [ ] `nvidia-smi` shows GPU
- [ ] GPU worker rebooted if needed

---

### **Phase 8: GPU Integration with Kubernetes**
**Goal:** Enable GPU scheduling in Kubernetes

**What you'll learn:** NVIDIA container toolkit, device plugins, GPU resource management

#### Step 8.1: Install NVIDIA Container Toolkit with Ansible
**Create ansible/playbooks/setup-nvidia-container-toolkit.yml:**
```yaml
---
- name: Install NVIDIA Container Toolkit on GPU worker
  hosts: k3s-gpu-worker
  become: yes
  tasks:
    - name: Get distribution
      shell: . /etc/os-release && echo $ID$VERSION_ID
      register: distribution
      changed_when: false

    - name: Add NVIDIA GPG key
      apt_key:
        url: https://nvidia.github.io/libnvidia-container/gpgkey
        state: present

    - name: Add NVIDIA repository
      apt_repository:
        repo: "deb https://nvidia.github.io/libnvidia-container/{{ distribution.stdout }}/$(ARCH) /"
        filename: nvidia-container-toolkit
        state: present

    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install NVIDIA Container Toolkit
      apt:
        name: nvidia-container-toolkit
        state: present

    - name: Configure containerd for GPU
      command: nvidia-ctk runtime configure --runtime=containerd --config=/var/lib/rancher/k3s/agent/etc/containerd/config.toml
      args:
        creates: /tmp/nvidia-containerd-configured

    - name: Mark containerd as configured
      file:
        path: /tmp/nvidia-containerd-configured
        state: touch

    - name: Restart k3s-agent
      systemd:
        name: k3s-agent
        state: restarted

    - name: Wait for k3s-agent to be ready
      wait_for:
        timeout: 30

    - name: Verify containerd configuration
      command: grep nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml
      register: containerd_config
      changed_when: false

    - name: Display containerd config
      debug:
        var: containerd_config.stdout_lines
```

**Run the playbook:**
```bash
ansible-playbook playbooks/setup-nvidia-container-toolkit.yml
```

**Checkpoint:**
- [ ] NVIDIA container toolkit installed
- [ ] Containerd configured for GPU
- [ ] k3s-agent restarted

---

#### Step 8.2: Deploy NVIDIA Device Plugin
**Create k8s/gpu/nvidia-device-plugin.yaml:**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      nodeSelector:
        accelerator: nvidia
      priorityClassName: system-node-critical
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.14.0
        name: nvidia-device-plugin-ctr
        env:
        - name: FAIL_ON_INIT_ERROR
          value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
```

**Deploy:**
```bash
kubectl apply -f k8s/gpu/nvidia-device-plugin.yaml

# Verify
kubectl get pods -n kube-system | grep nvidia
kubectl describe node k3s-gpu-worker | grep nvidia.com/gpu
```

**Expected Output:**
```
nvidia.com/gpu:     1
```

**Checkpoint:**
- [ ] Device plugin running
- [ ] GPU visible as allocatable resource

---

#### Step 8.3: Test GPU Access
**Create k8s/gpu/gpu-test-pod.yaml:**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: Never
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    accelerator: nvidia
```

**Test:**
```bash
kubectl apply -f k8s/gpu/gpu-test-pod.yaml
kubectl logs gpu-test

# Should show nvidia-smi output
kubectl delete pod gpu-test
```

**Checkpoint:**
- [ ] Pod scheduled on GPU worker
- [ ] GPU accessible from container
- [ ] `nvidia-smi` output in logs

---

### **Phase 9: Optional Enhancements**

#### Option A: GPU Time-Slicing (Multiple Pods per GPU)
**Update device plugin configuration to allow sharing:**

```yaml
# Update nvidia-device-plugin ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: kube-system
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 4  # Allow 4 pods to share GPU
```

#### Option B: Ray Cluster for Distributed Inference
**Deploy KubeRay operator and create Ray cluster**

See: https://docs.ray.io/en/latest/cluster/kubernetes/getting-started.html

#### Option C: Model Versioning & Registry
- Add MinIO for S3-compatible model storage
- Implement model versioning in inference service
- Create model deployment pipeline

#### Option D: CI/CD Pipeline
- GitHub Actions or GitLab CI
- Automated testing
- Container image building and pushing
- Automated deployment to k8s

---

## 📋 Testing & Validation

### End-to-End Test Checklist
- [ ] All 3 VMs running and accessible
- [ ] SMB storage mounted on host
- [ ] VM disks stored on SMB share
- [ ] GPU visible in gpu-worker VM
- [ ] K3s cluster healthy (3 nodes)
- [ ] SMB CSI driver installed (if using Phase 4b)
- [ ] GPU visible as K8s resource
- [ ] Inference service running on GPU
- [ ] Successful inference request
- [ ] VictoriaMetrics collecting metrics
- [ ] Grafana showing dashboards
- [ ] GPU metrics in Grafana

### Performance Test
```bash
# Benchmark inference throughput
# Create scripts/benchmark.sh
#!/bin/bash
for i in {1..100}; do
  curl -X POST -F "file=@test-image.jpg" \
    http://192.168.100.11:30080/predict
done
```

---

## 🔧 Troubleshooting

### SMB Storage Issues

#### SMB Mount Not Working
```bash
# Check if mount exists
df -h | grep smb-vmstore

# Check mount in fstab
grep smb-vmstore /etc/fstab

# Try manual mount with verbose output
sudo mount -v -t cifs //NAS_IP/share /mnt/storage -o credentials=/root/.smbcredentials

# Check SMB connectivity
smbclient -L //NAS_IP -U username

# Check permissions
ls -la /mnt/storage
# Should show libvirt-qemu:kvm ownership
```

#### Libvirt Can't Access SMB Storage
```bash
# Check AppArmor (if using Ubuntu)
sudo aa-status | grep libvirt

# May need to adjust AppArmor profile
sudo nano /etc/apparmor.d/abstractions/libvirt-qemu
# Add: /mnt/storage/** rwk,

sudo systemctl reload apparmor

# Or temporarily disable for testing
sudo systemctl stop apparmor
```

#### K8s SMB CSI Issues
```bash
# Check CSI driver pods
kubectl get pods -n kube-system | grep csi-smb

# Check CSI driver logs
kubectl logs -n kube-system <csi-smb-controller-pod>

# Check PVC status
kubectl describe pvc <pvc-name> -n <namespace>

# Test SMB connectivity from worker node
ssh ubuntu@192.168.100.11
sudo apt install -y cifs-utils smbclient
smbclient -L //NAS_IP -U username
```

#### Performance Issues with SMB
```bash
# Check network speed
iperf3 -c NAS_IP  # Run iperf3 server on NAS first

# Monitor SMB mount performance
iostat -x 5 /mnt/storage

# Check for SMB version (SMB3 is faster)
sudo mount | grep smb-vmstore
# Should show vers=3.0 or higher

# Force SMB3 in mount options
sudo mount -t cifs //NAS_IP/share /mnt/storage \
  -o credentials=/root/.smbcredentials,vers=3.0,cache=strict
```

---

### GPU Not Visible in VM
- Check IOMMU groups: `for d in /sys/kernel/iommu_groups/*/devices/*; do...`
- Verify vfio-pci binding: `lspci -nnk | grep -A3 NVIDIA`
- Check VM XML: `virsh dumpxml k3s-gpu-worker | grep hostdev`

### GPU Not Visible in Kubernetes
- Check device plugin logs: `kubectl logs -n kube-system <device-plugin-pod>`
- Verify containerd config: `cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml`
- Check node allocatable: `kubectl describe node k3s-gpu-worker`

### Inference Pods Not Scheduling
- Check pod events: `kubectl describe pod <pod> -n inference`
- Verify GPU resource request: `nvidia.com/gpu: 1`
- Check node selector: `accelerator: nvidia`

### No GPU Metrics in VictoriaMetrics
- Check DCGM exporter logs: `kubectl logs -n monitoring <dcgm-pod>`
- Verify VictoriaMetrics scrape config: `kubectl get cm -n monitoring victoriametrics-config -o yaml`
- Test metrics endpoint: `curl <dcgm-pod-ip>:9400/metrics`
- Check VictoriaMetrics targets: http://192.168.100.12:30428/targets

### VictoriaMetrics Not Scraping
- Check VictoriaMetrics logs: `kubectl logs -n monitoring -l app=victoriametrics`
- Verify ServiceAccount permissions: `kubectl get clusterrolebinding victoriametrics`
- Test scrape config syntax in VictoriaMetrics UI

---

## 📚 Learning Resources

### Technologies Used
- **Terraform + Libvirt**: Infrastructure as Code
- **QEMU/KVM**: Virtualization
- **Kubernetes (k3s)**: Container orchestration
- **NVIDIA GPU**: Hardware acceleration
- **Docker**: Containerization
- **FastAPI**: Python web framework
- **PyTorch**: ML framework
- **VictoriaMetrics**: Time-series database and monitoring
- **Grafana**: Visualization

### Reference Projects
- **Fawkes Terraform**: https://github.com/Cray-HPE/fawkes-terraform
  - Excellent modular Terraform structure for libvirt/KVM
  - Built for scale-out Kubernetes clusters
  - Good patterns for network and storage management
  - Uses Terragrunt (you don't need this for 3-node POC)
  - **Tip**: Look at `modules/hypervisor/modules/` for inspiration, but simplify for your fixed 3-node setup

### Useful Documentation
- **Libvirt Terraform Provider v0.9.0**: https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs
- **Cloud-init**: https://cloudinit.readthedocs.io/
- **K3s Documentation**: https://docs.k3s.io/
- **NVIDIA Container Toolkit**: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/
- **VictoriaMetrics**: https://docs.victoriametrics.com/

### Next Steps After POC
1. Implement proper CI/CD pipeline
2. Add model registry (MLflow, DVC)
3. Implement A/B testing for models
4. Add request logging and tracing
5. Implement auto-scaling based on load
6. Add security (RBAC, network policies, secrets management)
7. Implement backup and disaster recovery
8. Production-grade storage (Ceph, Longhorn)
9. Advanced networking (Istio, Calico)
10. Cost optimization and resource management

---

## 🎓 Key Concepts You'll Learn

1. **Infrastructure as Code**: Terraform for reproducible infrastructure
2. **GPU Virtualization**: PCI passthrough, IOMMU, VFIO
3. **Container Orchestration**: Kubernetes fundamentals, scheduling
4. **GPU Scheduling**: Resource limits, device plugins
5. **Model Serving**: REST API, containerized inference
6. **Observability**: Metrics, monitoring, dashboards
7. **Distributed Systems**: Multi-node clusters, networking
8. **DevOps Practices**: Automation, repeatability, documentation

---

## 📝 Notes

- This is a **learning POC**, not production-ready
- Start simple, add complexity incrementally
- Document issues and solutions
- Experiment and break things!
- Each phase builds on previous phases
- Take snapshots/backups before major changes

---

## ✅ Success Criteria

You'll know you're done when:
1. You can deploy infrastructure with `terraform apply`
2. GPU-accelerated inference works end-to-end
3. You can monitor GPU usage in Grafana
4. You understand each component and can explain it
5. You can tear down and rebuild from scratch

---

**Ready to start? Begin with Phase 1, Step 1.1!**
