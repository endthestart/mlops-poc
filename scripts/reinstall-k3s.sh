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
