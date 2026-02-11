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

# Install SMB CSI driver
echo "Step 8: Installing SMB CSI driver..."
ansible-playbook playbooks/setup-smb-csi.yml
echo

# Get new kubeconfig
cd ../
echo "Step 9: Apply storage configuration..."
scp ubuntu@192.168.100.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/192.168.100.10/g' ~/.kube/config
kubectl get nodes
echo

# Apply storage configuration
echo "Step 9: Apply storage configuration..."
kubectl apply -f k8s/storage/smb-secret.yaml
kubectl apply -f k8s/storage/smb-storageclass.yaml
kubectl get sc
echo

# Deploy pod
echo "Step 10: Deploy test pod..."
kubectl apply -f k8s/storage/test-pvc.yaml
kubectl apply -f k8s/storage/test-pod.yaml
kubectl wait --for=condition=ready pod/test-smb-pod --timeout=60s
kubectl logs test-smb-pod
echo


# Deploy nvidia inference service
echo "Step 11: Deploy nvidia inference service..."
kubectl apply -f k8s/gpu/nvidia-device-plugin.yaml
# Verify
kubectl get pods -n kube-system | grep nvidia
kubectl describe node k3s-gpu-worker | grep nvidia.com/gpu
echo


echo "=== Cluster rebuild complete! ==="
