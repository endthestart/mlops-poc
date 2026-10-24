# libvirt environment

K3s across three libvirt VMs (a server, a GPU worker and a worker) on a Linux
host. It last ran in November 2025 on an Arch-based host. Its files were moved
into this layout without being tested again; [notes/](notes/) has the history.

## Host setup

Mount the network storage that holds the VM disks (path from
`terraform/variables.tf`):

```bash
# /etc/fstab
//<nas-host>/storage /mnt/storage cifs credentials=/root/.smbcredentials,uid=libvirt-qemu,gid=kvm,file_mode=0660,dir_mode=0770,_netdev,x-systemd.automount 0 0
```

Install and start libvirt:

```bash
sudo pacman -S qemu-base qemu-system-x86 libvirt virt-manager bridge-utils ovmf terraform dnsmasq iptables-nft ebtables dmidecode cdrtools
sudo usermod -aG kvm,libvirt $USER
sudo systemctl enable --now libvirtd
```

Define the VM network:

```bash
sudo virsh net-define environments/libvirt/network.xml
sudo virsh net-start mlops-net
sudo virsh net-autostart mlops-net
```

## VMs

Add your public key to `terraform/cloud-init.yaml`, then:

```bash
cd environments/libvirt/terraform
terraform init
terraform apply
```

## K3s

From the repository root, with Ansible installed (`pip install ansible`):

```bash
cd ansible
ansible-playbook playbooks/setup-k3s-master.yml
ansible-playbook playbooks/setup-k3s-workers.yml
ansible-playbook playbooks/label-nodes.yml
```

`ansible.cfg` reads `environments/libvirt/inventory.yml`. Fetch the kubeconfig:

```bash
scp ubuntu@192.168.100.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/192.168.100.10/g' ~/.kube/config
kubectl get nodes
```

`rebuild-cluster.sh` recreates everything; `reinstall-k3s.sh` reinstalls K3s
and keeps the VMs.
