# SMB Storage Integration - Quick Reference

## Overview
This POC uses SMB/CIFS network storage in two ways:
1. **Host level**: VM disk images stored on SMB share
2. **Kubernetes level**: Persistent volumes for model data, metrics, etc.

## Benefits
- ✅ Saves local disk space (VMs can be 20-50GB each)
- ✅ Leverage your 10Gb network
- ✅ Centralized backup (backup NAS instead of local disks)
- ✅ Easy to expand storage
- ✅ Share data between pods (ReadWriteMany)

## Prerequisites
- SMB share accessible on your network
- Share credentials (username/password)
- Share path (e.g., `//nas.local/vmstore`)
- 10Gb network connection

---

## Part 1: Host-Level SMB (VM Disks)

### Quick Setup
```bash
# 1. Install CIFS utilities
sudo apt install -y cifs-utils

# 2. Create credentials file
sudo nano /root/.smbcredentials
```

Add to file:
```
username=your_smb_user
password=your_smb_password
domain=WORKGROUP
```

```bash
# 3. Secure credentials
sudo chmod 600 /root/.smbcredentials

# 4. Create mount point
sudo mkdir -p /mnt/smb-vmstore

# 5. Test mount
sudo mount -t cifs //YOUR_NAS_IP/vmstore /mnt/smb-vmstore \
  -o credentials=/root/.smbcredentials,uid=libvirt-qemu,gid=kvm,file_mode=0660,dir_mode=0770

# 6. Verify
df -h | grep smb-vmstore
ls -la /mnt/smb-vmstore

# 7. Make persistent
sudo nano /etc/fstab
```

Add to `/etc/fstab`:
```
//YOUR_NAS_IP/vmstore  /mnt/smb-vmstore  cifs  credentials=/root/.smbcredentials,uid=libvirt-qemu,gid=kvm,file_mode=0660,dir_mode=0770,_netdev,x-systemd.automount  0  0
```

```bash
# 8. Test fstab
sudo umount /mnt/smb-vmstore
sudo mount -a

# 9. Create libvirt pool directory
sudo mkdir -p /mnt/smb-vmstore/mlops-pool
sudo chown libvirt-qemu:kvm /mnt/smb-vmstore/mlops-pool
```

### Terraform Configuration
In `terraform/variables.tf`:
```hcl
variable "smb_storage_path" {
  description = "Path to SMB-mounted storage for VM disks"
  default     = "/mnt/smb-vmstore/mlops-pool"
}
```

In `terraform/storage.tf`, the pool path will automatically use SMB:
```hcl
resource "libvirt_pool" "mlops" {
  name = "mlops-pool"
  type = "dir"
  path = var.smb_storage_path  # Points to /mnt/smb-vmstore/mlops-pool
}
```

**Result**: All VM disks will be stored on your NAS!

---

## Part 2: Kubernetes-Level SMB (Persistent Volumes)

### Quick Setup
```bash
# 1. Install SMB CSI driver (on master node)
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/deploy/install-driver.sh

# 2. Create credentials secret
kubectl create secret generic smb-credentials \
  --from-literal=username=your_smb_user \
  --from-literal=password=your_smb_password \
  -n kube-system

# 3. Create StorageClass
kubectl apply -f k8s/storage/smb-storageclass.yaml

# 4. Test with PVC
kubectl apply -f k8s/storage/test-pvc.yaml
kubectl apply -f k8s/storage/test-pod.yaml

# 5. Verify
kubectl get pvc
kubectl logs test-smb-pod
```

### StorageClass Configuration
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: smb
provisioner: smb.csi.k8s.io
parameters:
  source: "//YOUR_NAS_IP/k8s-data"
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

### Usage Example (VictoriaMetrics)
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: victoriametrics-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: smb  # Uses SMB storage
  resources:
    requests:
      storage: 10Gi
```

**Result**: Kubernetes pods can store data on your NAS!

---

## Storage Layout on NAS

After setup, your NAS will have:
```
/vmstore/                          (SMB share for VM disks)
├── mlops-pool/                    (Libvirt storage pool)
│   ├── ubuntu-22.04-base.qcow2   (~2GB)
│   ├── k3s-master.qcow2          (~20GB)
│   ├── k3s-gpu-worker.qcow2      (~50GB)
│   └── k3s-worker.qcow2          (~50GB)

/k8s-data/                         (SMB share for K8s PVs)
├── monitoring-victoriametrics-data-<id>/  (VictoriaMetrics time-series data)
├── inference-models-<id>/                  (Model files)
└── ...
```

---

## Performance Considerations

### Expected Performance (10Gb Network)
- **Sequential reads**: ~800-1000 MB/s (SMB3)
- **Sequential writes**: ~600-800 MB/s (SMB3)
- **Random I/O**: ~50-100k IOPS (depends on NAS)

### Optimization Tips

1. **Use SMB3** (faster than SMB2):
   ```bash
   # Add to mount options
   vers=3.0,cache=strict
   ```

2. **Enable multichannel** (if supported):
   ```bash
   # Add to mount options
   multichannel
   ```

3. **Tune cache settings**:
   ```bash
   # For better read performance
   cache=strict
   
   # For better write performance (less safe)
   cache=loose
   ```

4. **Check actual SMB version in use**:
   ```bash
   mount | grep smb-vmstore
   ```

5. **Monitor network utilization**:
   ```bash
   iftop -i eth0  # Replace eth0 with your 10Gb interface
   ```

### What to Store Where

**Good for SMB storage:**
- ✅ VM disk images (sequential I/O)
- ✅ Model files (large, sequential reads)
- ✅ Time-series data (VictoriaMetrics)
- ✅ Container images (read-heavy)
- ✅ Logs and archives

**Not ideal for SMB:**
- ❌ Database files with random I/O (etcd, PostgreSQL)
- ❌ High-frequency small writes
- ❌ Temporary files

**Recommendation**: Keep etcd (k3s state) on local VM disk, everything else on SMB.

---

## Troubleshooting

### Mount fails with "Permission denied"
```bash
# Check credentials
sudo cat /root/.smbcredentials

# Test credentials manually
smbclient -L //NAS_IP -U username

# Check NAS share permissions
```

### Libvirt can't access SMB files
```bash
# Check ownership
ls -la /mnt/smb-vmstore/mlops-pool

# Should be: libvirt-qemu:kvm

# Fix ownership
sudo chown -R libvirt-qemu:kvm /mnt/smb-vmstore/mlops-pool

# Check AppArmor (Ubuntu)
sudo aa-status | grep libvirt
# May need to add /mnt/smb-vmstore/** to libvirt AppArmor profile
```

### K8s PVC stuck in Pending
```bash
# Check CSI driver
kubectl get pods -n kube-system | grep csi-smb

# Check PVC events
kubectl describe pvc <pvc-name>

# Check logs
kubectl logs -n kube-system <csi-smb-controller-pod>

# Verify secret exists
kubectl get secret smb-credentials -n kube-system
```

### Slow performance
```bash
# Check SMB version (should be 3.0+)
mount | grep smb-vmstore

# Test network speed
iperf3 -c NAS_IP

# Check if using 10Gb interface
ethtool <interface-name> | grep Speed
# Should show: Speed: 10000Mb/s

# Monitor I/O
iostat -x 5 /mnt/smb-vmstore
```

---

## Security Notes

1. **Credentials file**: `/root/.smbcredentials` should be mode 600
2. **K8s secret**: Don't commit `smb-secret.yaml` to git
3. **Add to .gitignore**:
   ```
   k8s/storage/smb-secret.yaml
   ```
4. **Network**: Consider using isolated VLAN for storage traffic (future enhancement)

---

## Cost Savings

With 3 VMs using ~120GB total on NAS instead of local storage:
- Local SSD saved: ~120GB
- Can use smaller/cheaper local disk
- Centralized backups: Backup NAS once instead of each VM
- Easy to snapshot entire environment

---

## Next Steps

1. Complete Phase 1, Step 1.1b (mount SMB for VMs)
2. Update `terraform/variables.tf` with your SMB path
3. Run `terraform apply` (VMs will use SMB storage)
4. Optionally: Complete Phase 4b (K8s SMB storage)
5. Use SMB PVCs for VictoriaMetrics, model storage, etc.

**Ready to proceed with Terraform setup!**
