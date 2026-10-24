# GPU PCI Passthrough Setup for Arch Linux (Headless Mode)
**Date Created:** November 30, 2025  
**System:** Arch Linux with systemd-boot  
**GPU:** NVIDIA GeForce RTX 4080 SUPER [10de:2702]  
**GPU Audio:** NVIDIA AD103 Audio [10de:22bb]  
**CPU:** AMD (requires amd_iommu=on)

## ⚠️ WARNING
Following these steps will make your system headless (no display output). You MUST access the system via SSH after applying these changes. **Ensure SSH is working before proceeding!**

---

## Prerequisites Check

Before starting, verify:
```bash
# 1. Verify SSH is enabled and working
systemctl status sshd
# Test SSH from another machine: ssh your_username@your_ip

# 2. Note your current IP address
ip addr show

# 3. Verify GPU PCI IDs
lspci -nn | grep -i nvidia
# Should show: 10de:2702 (GPU) and 10de:22bb (Audio)
```

---

## Step-by-Step Setup Instructions

### Step 1: Backup Current Configuration

```bash
# Backup systemd-boot entries
sudo cp -r /boot/loader /boot/loader.backup

# Backup current boot entry (find your current entry first)
sudo ls /boot/loader/entries/
# Then backup it (replace XXXXX with your actual entry name):
sudo cp /boot/loader/entries/XXXXX.conf /boot/loader/entries/XXXXX.conf.backup

# Backup mkinitcpio config
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.backup
```

### Step 2: Enable VFIO Kernel Modules

Create VFIO modules configuration:

```bash
sudo nano /etc/modprobe.d/vfio.conf
```

Add the following content:
```
# Bind GPU and its audio device to VFIO at boot
options vfio-pci ids=10de:2702,10de:22bb

# Prevent NVIDIA driver from loading
softdep nvidia pre: vfio-pci
softdep nvidia_drm pre: vfio-pci
softdep nvidia_modeset pre: vfio-pci
softdep nouveau pre: vfio-pci
```

Save and exit (Ctrl+O, Enter, Ctrl+X).

### Step 3: Configure mkinitcpio to Load VFIO Early

Edit mkinitcpio configuration:

```bash
sudo nano /etc/mkinitcpio.conf
```

Find the `MODULES=()` line and change it to:
```
MODULES=(vfio_pci vfio vfio_iommu_type1)
```

**Note:** Keep the parentheses. If there are already modules listed, add these at the beginning.

Save and exit.

### Step 4: Regenerate initramfs

```bash
sudo mkinitcpio -P
```

This will regenerate all kernel initramfs images with the new VFIO modules.

### Step 5: Add Kernel Parameters for IOMMU

Find your current systemd-boot entry:

```bash
sudo ls /boot/loader/entries/
```

Edit your boot entry (replace `XXXXX.conf` with your actual entry):

```bash
sudo nano /boot/loader/entries/XXXXX.conf
```

Find the line starting with `options` and add these parameters to the end:
```
amd_iommu=on iommu=pt vfio-pci.ids=10de:2702,10de:22bb
```

**Example - Your options line might look like:**
```
options initrd=\initramfs-linux-cachyos.img root=UUID=38d14ebe-52ec-4477-9967-5019deb1d4b4 rw rootflags=subvol=/@ zswap.enabled=0 nowatchdog splash amd_iommu=on iommu=pt vfio-pci.ids=10de:2702,10de:22bb
```

Save and exit.

### Step 6: Disable Display Manager (Make System Headless)

```bash
# Switch to multi-user (non-graphical) target
sudo systemctl set-default multi-user.target

# This prevents any graphical login from starting
```

### Step 7: Verify SSH Will Auto-Start

```bash
# Ensure SSH starts on boot
sudo systemctl enable sshd

# Verify it's enabled
systemctl is-enabled sshd
# Should output: enabled
```

### Step 8: (Optional) Configure Static IP

If you want to ensure you can always find your machine after reboot:

```bash
# Check your network interface name
ip link

# If using NetworkManager, set static IP (replace values):
nmcli con mod "YOUR_CONNECTION_NAME" ipv4.addresses "192.168.1.100/24"
nmcli con mod "YOUR_CONNECTION_NAME" ipv4.gateway "192.168.1.1"
nmcli con mod "YOUR_CONNECTION_NAME" ipv4.dns "8.8.8.8"
nmcli con mod "YOUR_CONNECTION_NAME" ipv4.method manual
```

### Step 9: Reboot into Headless Mode

```bash
# Final check - make sure you can SSH to this machine!
# From another computer: ssh your_username@your_ip

# When ready:
sudo reboot
```

After reboot:
- **The system will have NO display output**
- You MUST connect via SSH
- The GPU will be bound to VFIO and available for passthrough to VMs

### Step 10: Verify GPU is Bound to VFIO (After Reboot, via SSH)

After SSHing back into the system:

```bash
# Check that GPU is using vfio-pci driver
lspci -nnk -d 10de:2702

# Should show:
# Kernel driver in use: vfio-pci
```

If you see `vfio-pci` as the driver, success! Your GPU is ready for passthrough.

---

## Configuring a VM with GPU Passthrough

Once the GPU is bound to VFIO, you can configure a VM (QEMU/KVM, libvirt, etc.):

### Using virt-manager:
1. SSH into your machine with X forwarding: `ssh -X user@host virt-manager`
2. Or use a web-based solution like Cockpit with the Virtual Machines plugin

### Using virsh/XML:
Add to your VM's XML configuration:
```xml
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='0x0000' bus='0x07' slot='0x00' function='0x0'/>
  </source>
</hostdev>
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='0x0000' bus='0x07' slot='0x00' function='0x1'/>
  </source>
</hostdev>
```

---

## 🔄 REVERTING EVERYTHING - Step-by-Step

If you need to go back to normal (GPU used by host with display):

### Revert Step 1: Restore Display Manager

```bash
# SSH into the machine
ssh your_username@your_ip

# Re-enable graphical target
sudo systemctl set-default graphical.target
```

### Revert Step 2: Remove VFIO Configuration

```bash
# Remove VFIO modprobe config
sudo rm /etc/modprobe.d/vfio.conf
```

### Revert Step 3: Restore mkinitcpio Configuration

```bash
# Restore original mkinitcpio config
sudo cp /etc/mkinitcpio.conf.backup /etc/mkinitcpio.conf

# Or manually edit:
sudo nano /etc/mkinitcpio.conf
# Change MODULES line back to: MODULES=()
# (or whatever it was originally)
```

### Revert Step 4: Regenerate initramfs

```bash
sudo mkinitcpio -P
```

### Revert Step 5: Remove Kernel Parameters

```bash
# Find your boot entry
sudo ls /boot/loader/entries/

# Edit it (replace XXXXX.conf with your actual entry)
sudo nano /boot/loader/entries/XXXXX.conf

# Remove these parameters from the options line:
# amd_iommu=on iommu=pt vfio-pci.ids=10de:2702,10de:22bb
```

### Revert Step 6: Reboot

```bash
sudo reboot
```

After reboot, your system should start with a display again, and the GPU will be used by the host with the NVIDIA driver.

### Revert Step 7: Verify GPU is Back to Normal

```bash
# Check GPU driver
lspci -nnk -d 10de:2702

# Should show:
# Kernel driver in use: nvidia (or nouveau)
```

### Revert Step 8: (Optional) Restore Network Settings

If you set a static IP and want to go back to DHCP:

```bash
nmcli con mod "YOUR_CONNECTION_NAME" ipv4.method auto
nmcli con up "YOUR_CONNECTION_NAME"
```

---

## Troubleshooting

### Can't SSH After Reboot?
1. Connect a monitor temporarily (if possible) or boot from live USB
2. Boot into rescue mode by editing the boot entry and adding `systemd.unit=rescue.target`
3. Follow revert steps above

### GPU Still Not Bound to VFIO?
```bash
# Check IOMMU is enabled
dmesg | grep -i iommu

# Check VFIO modules loaded
lsmod | grep vfio

# Check kernel parameters were applied
cat /proc/cmdline
```

### Need to Access Console Temporarily?
From SSH:
```bash
# Switch to graphical target temporarily (before rebooting)
sudo systemctl isolate graphical.target

# Switch back to headless
sudo systemctl isolate multi-user.target
```

---

## Important Notes

1. **Always ensure SSH access before making changes**
2. Some NVIDIA GPUs have a reset bug - research your specific model
3. You may need to add `video=efifb:off` to kernel parameters if you have display issues
4. Consider setting up a serial console as a backup access method
5. The GPU audio device (10de:22bb) should also be passed through to the VM for full functionality

---

## Additional Resources

- [Arch Wiki: PCI Passthrough](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [VFIO Subreddit](https://reddit.com/r/VFIO)
- [Looking Glass](https://looking-glass.io/) - For low-latency display from VM to host

---

**End of Guide**
