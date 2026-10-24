# MLOps POC - Session Summary (2025-11-20)

## ✅ What We Accomplished

### Infrastructure Setup (Phase 1)
- ✅ Terraform configuration created for 3 VMs
- ✅ Separate cloud-init disks per VM with **unique hostnames**
- ✅ VMs using SMB storage for disk images
- ✅ Network configured with static IPs via DHCP reservations

### Ansible Setup (Phase 2)
- ✅ Ansible inventory configured
- ✅ SSH config updated to handle frequent VM rebuilds
- ✅ Playbooks created for k3s deployment

### k3s Cluster Deployment (Phase 3)
- ✅ k3s master installed and running
- ✅ 2 worker nodes joined cluster successfully
- ✅ All nodes labeled correctly
- ✅ Helper scripts created for cluster management

### Current Cluster State
```
NAME             STATUS   ROLES                  AGE   VERSION
k3s-gpu-worker   Ready    gpu-worker             8s    v1.33.5+k3s1
k3s-master       Ready    control-plane,master   25s   v1.33.5+k3s1
k3s-worker       Ready    worker                 8s    v1.33.5+k3s1
```

## 🔧 Key Issues Resolved

### Issue #1: Duplicate Hostnames
**Problem:** All VMs had hostname `mlops-node`, causing k3s workers to fail joining:
```
Node password rejected, duplicate hostname or contents of '/etc/rancher/node/password' may not match
```

**Solution:** 
- Created separate cloud-init disks for each VM
- Templated hostname in `cloud-init.yaml` using `${hostname}`
- Each VM now has unique hostname: `k3s-master`, `k3s-gpu-worker`, `k3s-worker`

**Files Changed:**
- `terraform/cloudinit.tf` - Created per-VM cloud-init resources
- `terraform/cloud-init.yaml` - Added `hostname: ${hostname}`
- `terraform/vms.tf` - Updated to use per-VM cloud-init disks

### Issue #2: Token Mismatch on Cluster Rebuilds
**Problem:** When rebuilding master, workers kept old token/CA hash

**Solution:** Simplified worker playbook to:
- Check if token matches current master
- Auto-detect mismatches and reinstall cleanly
- Uses official k3s installer (no custom templates)

### Issue #3: SSH Host Key Changes
**Problem:** Rebuilding VMs caused "REMOTE HOST IDENTIFICATION HAS CHANGED" errors

**Solution:** Added to `~/.ssh/config`:
```
Host 192.168.100.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

### Issue #4: Ansible Idempotency vs KISS
**Decision:** For a learning POC, embrace `terraform destroy && apply` as reset button

**Implementation:**
- Created `scripts/rebuild-cluster.sh` - Full rebuild (VMs + k3s)
- Created `scripts/reinstall-k3s.sh` - Quick k3s reinstall
- Simplified Ansible playbooks to be honest about limitations
- Token mismatches trigger clean reinstall

## 📚 Lessons Learned

1. **Unique Hostnames are Critical**: k3s uses hostnames for node identity. Without unique hostnames, cluster formation fails.

2. **Cloud-init Best Practices**: Each VM should have its own cloud-init disk if any per-VM customization is needed (hostname, network, etc.)

3. **Idempotency Trade-offs**: For POCs, rebuilding from scratch is often faster/simpler than perfect idempotency.

4. **Token Management**: k3s tokens include CA certificate hashes. Master rebuild = new CA = workers need fresh tokens.

5. **Reference Good Code**: Fawkes-Terraform showed clean patterns for:
   - Dynamic hostname generation
   - Per-VM cloud-init configuration
   - Module-based architecture

## 📂 Project Structure Created

```
mlops-poc/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── storage.tf
│   ├── cloudinit.tf          # Per-VM cloud-init
│   ├── cloud-init.yaml        # Template with ${hostname}
│   └── vms.tf                 # VM definitions
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.yml
│   └── playbooks/
│       ├── setup-k3s-master.yml    # Idempotent master setup
│       ├── setup-k3s-workers.yml   # Auto-detects token mismatches
│       └── label-nodes.yml         # Node labeling
├── scripts/
│   ├── rebuild-cluster.sh          # Full rebuild
│   └── reinstall-k3s.sh           # Quick k3s reinstall
└── ai-docs/
    └── PLAN.md                     # Updated with lessons learned
```

## 🎯 Next Steps (Phase 4+)

### Phase 4: SMB Storage for Kubernetes
- [ ] Install SMB CSI driver
- [ ] Create StorageClass
- [ ] Test persistent volumes

### Phase 5: Model Inference Service
- [ ] Create FastAPI inference service
- [ ] Build Docker image
- [ ] Deploy to cluster

### Phase 6: Monitoring
- [ ] Deploy VictoriaMetrics
- [ ] Deploy Grafana
- [ ] Configure dashboards

### Phase 7: GPU Passthrough (Later)
- [ ] Identify GPU PCI address
- [ ] Bind to VFIO driver
- [ ] Update Terraform for passthrough
- [ ] Install NVIDIA drivers in VM

### Phase 8: GPU Integration with k8s (After Phase 7)
- [ ] Install NVIDIA container toolkit
- [ ] Deploy device plugin
- [ ] Test GPU scheduling

## 💡 Key Commands Reference

```bash
# Full cluster rebuild
./scripts/rebuild-cluster.sh

# Quick k3s reinstall (keeps VMs)
./scripts/reinstall-k3s.sh

# Check cluster status
ssh ubuntu@192.168.100.10 'kubectl get nodes'

# Verify unique hostnames
ssh ubuntu@192.168.100.10 'hostname'
ssh ubuntu@192.168.100.11 'hostname'
ssh ubuntu@192.168.100.12 'hostname'

# Apply Terraform changes
cd terraform && terraform apply

# Run Ansible playbooks
cd ansible
ansible-playbook playbooks/setup-k3s-master.yml
ansible-playbook playbooks/setup-k3s-workers.yml
ansible-playbook playbooks/label-nodes.yml
```

## 📝 Documentation Updates

- ✅ PLAN.md updated with "Lessons Learned" section
- ✅ Terraform examples corrected for unique hostnames
- ✅ Helper scripts documented
- ✅ Checkpoints marked for completed phases

---

**Status:** Ready to proceed with Phase 4 (SMB Storage for Kubernetes)
