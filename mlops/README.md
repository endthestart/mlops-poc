# MLOps

The GPU training side of the lab, kept from the original proof of concept. It
isn't running now and comes back when a GPU host does.

## Weekend training

Deploys a training pipeline to a GPU host as a Podman container with systemd
timers (not Kubernetes). The training code lives in its application repository;
this folder only deploys it.

```bash
cd ansible
ansible-playbook ../mlops/ansible/playbooks/setup-ml-training.yml
ansible-playbook ../mlops/ansible/playbooks/setup-ml-training.yml --tags build  # rebuild the image
ansible-playbook ../mlops/ansible/playbooks/setup-ml-training.yml --tags test
```

- `ml-ssh-tunnel.service`: a persistent SSH tunnel to the training database
- `ml-training-saturday.service`: the weekend training run
- `ml-training-saturday.timer`: fires Saturdays at 06:00

## GPU passthrough

See [GPU-PASSTHROUGH-GUIDE.md](GPU-PASSTHROUGH-GUIDE.md). `iommu.sh` lists the
host's IOMMU groups. [k8s/gpu](k8s/gpu/) holds the NVIDIA device plugin.

## SMB storage for the cluster

`ansible/playbooks/setup-smb-csi.yml` installs the SMB CSI driver. Copy
[smb-secret.example.yaml](k8s/storage/smb-secret.example.yaml) outside the
repo, fill it in, and apply it before the storage class:

```bash
kubectl apply -f /path/to/smb-secret.yaml
kubectl apply -f mlops/k8s/storage/smb-storageclass.yaml
kubectl apply -f mlops/k8s/storage/test-pvc.yaml
kubectl apply -f mlops/k8s/storage/test-pod.yaml
kubectl wait --for=condition=ready pod/test-smb-pod --timeout=60s
kubectl logs test-smb-pod
```

Clean up with `kubectl delete pod test-smb-pod`, `kubectl delete pvc
test-smb-pvc` and `kubectl delete storageclass smb`.
