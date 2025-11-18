## Project Goals
Build a production-like MLOps infrastructure for model inference using GPU acceleration on a local baremetal host.

### Learning Objectives
- Deploy infrastructure as code using Terraform + Libvirt
- Configure GPU passthrough to VMs
- Set up Kubernetes cluster (k3s) across VMs
- Deploy GPU-accelerated inference services
- Implement monitoring and observability

## System Setup

### Network Storage
Mount network storage to /mnt/storage/ in /etc/fstab
```bash
//10.0.0.209/storage /mnt/storage cifs credentials=/root/.smbcredentials,uid=libvirt-qemu,gid=kvm,file_mode=0660,dir_mode=0770,_netdev,x-systemd.automount 0 0
sudo mkdir -p /mnt/kvm/mlops-pool
sudo mount -a
```

### Virtualization

```bash
sudo pacman -S qemu-base qemu-system-x86 libvirt virt-manager bridge-utils ovmf terraform dnsmasq iptables-nft ebtables dmidecode
```

Core packages:

- qemu-base - QEMU core
- qemu-system-x86 - x86_64 emulator (provides qemu-system-x86_64)
- libvirt - Virtualization API
- virt-manager - GUI management tool (optional but useful)
- bridge-utils - Network bridging tools
- ovmf - UEFI firmware
- terraform - Infrastructure as Code
- dnsmasq - DNS/DHCP for libvirt networks
- iptables-nft - Firewall (needed for libvirt NAT)
- ebtables - Ethernet bridge filtering
- dmidecode - System information (libvirt uses this)

```bash
sudo usermod -aG kvm,libvirt $USER
sudo systemctl start libvirtd
sudo systemctl enable libvirtd
```

```bash
$ scripts/iommu.sh
IOMMU Group 17 07:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD103 [GeForce RTX 4080 SUPER] [10de:2702] (rev a1)
```

### Networking
```bash
sudo virsh net-define network.xml
sudo virsh net-start mlops-net
sudo virsh net-autostart mlops-net
```

### Terraform
Add public key to cloud-init.yaml
cd terraform/
terraform init
terraform plan
terraform apply
