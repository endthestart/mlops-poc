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
sudo pacman -S qemu-base qemu-system-x86 libvirt virt-manager bridge-utils ovmf terraform dnsmasq iptables-nft ebtables dmidecode cdrtools
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
- cdrtools - Tools that include mkisofs

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

### Ansible
In a virtualenv
```bash
pip install ansible
```

```bash
ansible-playbook playbooks/setup-k3s-master.yml
ansible-playbook playbooks/setup-k3s-workers.yml
ansible-playbook playbooks/label-nodes.yml
ansible-playbook playbooks/setup-smb-csi.yml
```

### Troubleshooting
scripts/reinstall-k3s.sh
scripts/rebuild-cluster.sh


# K8s Commands
sudo pacman -S kubectl
mkdir -p ~/.kube
scp ubuntu@192.168.100.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/192.168.100.10/g' ~/.kube/config
kubectl get nodes
kubectl apply -f k8s/storage/smb-secret.yaml
kubectl apply -f k8s/storage/smb-storageclass.yaml
kubectl get sc

kubectl apply -f k8s/storage/test-pvc.yaml
kubectl apply -f k8s/storage/test-pod.yaml

kubectl wait --for=condition=ready pod/test-smb-pod --timeout=60s
kubectl logs test-smb-pod
kubectl describe pod test-smb-pod
kubectl get pod test-smb-pod -o wide
kubectl get pvc -w

### Remove
kubectl delete pod test-smb-pod
kubectl delete pvc test-smb-pvc
kubectl delete storageclass smb

### Show
kubectl get storageclass
kubectl describe pvc test-smb-pvc
kubectl get csidrivers
kubectl get pods -n kube-system
