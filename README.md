## Project Goals
Build a production-like MLOps infrastructure for model inference using GPU acceleration on a local baremetal host.

### Learning Objectives
- Deploy infrastructure as code using Terraform + Libvirt
- Configure GPU passthrough to VMs
- Set up Kubernetes cluster (k3s) across VMs
- Deploy GPU-accelerated inference services
- Implement monitoring and observability

## System Setup
### Virtualization
sudo pacman -S qemu-desktop bridge-utils libvirt virt-manager ovmf terraform
sudo usermod -a -G libvirt,kvm andermic
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

$ scripts/iommu.sh
IOMMU Group 17 07:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD103 [GeForce RTX 4080 SUPER] [10de:2702] (rev a1)

### Networking
sudo virsh net-define network.xml
sudo virsh net-start mlops-net
sudo virsh net-autostart mlops-net

