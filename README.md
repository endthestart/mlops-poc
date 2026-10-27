# Home lab platform

A home lab for learning platform and identity engineering: one set of
Kubernetes manifests, several environments. It began as an MLOps proof of
concept (GPU training on K3s across libvirt VMs). Those parts now live in
[mlops/](mlops/) and come back later.

## Layers

| Layer | macpro-colima | libvirt |
| --- | --- | --- |
| VM | Colima profile ([environments/macpro-colima](environments/macpro-colima/)) | Terraform and libvirt ([environments/libvirt](environments/libvirt/)) |
| K3s | installed by Colima | Ansible playbooks ([ansible/](ansible/)) |
| Cluster | shared manifests, one overlay per environment (coming) | same |

[K3S_VERSION](K3S_VERSION) pins the K3s release for every environment.

## Environments

- **macpro-colima**: a single-node K3s in a 2 vCPU, 8 GiB Colima VM on an
  Intel Mac Pro. Working.
- **libvirt**: K3s across libvirt VMs on a Linux host. It last ran in
  November 2025 and has been moved into this layout but not tested since. See
  [environments/libvirt/README.md](environments/libvirt/README.md).

## macpro-colima

Needs `colima`, `kubectl` and `jq` (`brew install colima kubectl jq`).

```bash
environments/macpro-colima/lab up      # start the VM and wait for K3s
environments/macpro-colima/lab status
environments/macpro-colima/lab down
```

The VM's size, runtime and K3s arguments are in
[colima.env](environments/macpro-colima/colima.env). The kubectl context is
`colima-homelab`.

`lab up` refuses to start when the host's VM policy would be broken. That
policy belongs to the host, not this repo, so it lives in
`~/.config/homelab/macpro-policy.env` (or the file named by `LAB_POLICY_FILE`):

```bash
MAX_VM_VCPU=2                  # per VM
MAX_VM_MEMORY_GIB=8            # per VM
MAX_TOTAL_VCPU=4               # all running VMs together
EXCLUSIVE_PROFILES="other-vm"  # Colima profiles this VM never runs alongside
UNCOUNTED_PROFILES=""          # Colima profiles left out of the total
UNCOUNTED_FUSION_VMS=""        # VMware Fusion VMs left out of the total
```

## Secrets

Nothing secret is committed here. Environment values and secrets, encrypted
with SOPS, live in a separate private repository. Scan before committing:
`gitleaks git --pre-commit --staged`.

## Roadmap

Ingress (Traefik), TLS (cert-manager with a lab CA) and Postgres
(CloudNativePG), then Keycloak and the identity work on top.
