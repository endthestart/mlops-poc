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
