#!/bin/bash
# =============================================================================
# Custom RPi4 Guest Kernel Build Script (Executes inside Docker Container)
# =============================================================================
set -e

echo ">>> Cloning Raspberry Pi kernel source (rpi-6.1.y branch)..."
git clone --depth 1 --branch rpi-6.1.y \
  https://github.com/raspberrypi/linux.git /build/linux

cd /build/linux

echo ">>> Configuring kernel with bcm2711_defconfig..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2711_defconfig

echo ">>> Enabling Android Binder and Ashmem driver configs..."
./scripts/config --enable ANDROID
./scripts/config --enable ANDROID_BINDER_IPC
./scripts/config --enable ANDROID_BINDERFS
./scripts/config --enable ANDROID_BINDER_DEVICES
./scripts/config --set-str ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder"
./scripts/config --enable STAGING
./scripts/config --enable ASHMEM

echo ">>> Enabling QVM VirtIO MMIO/PCI drivers and features..."
./scripts/config --enable VIRTIO
./scripts/config --enable VIRTIO_MMIO
./scripts/config --enable VIRTIO_PCI
./scripts/config --enable VIRTIO_BLK
./scripts/config --enable VIRTIO_NET
./scripts/config --enable VIRTIO_CONSOLE
./scripts/config --enable VIRTIO_INPUT
./scripts/config --enable VIRTIO_GPU
./scripts/config --enable VIRTIO_BALLOON
./scripts/config --enable DRM_VIRTIO_GPU
./scripts/config --enable VIRTIO_DMA_SHARED_BUFFER
./scripts/config --enable VIRTIO_MMIO_CMDLINE_DEVICES
./scripts/config --enable HW_RANDOM_VIRTIO

echo ">>> Enabling Android filesystems, Device Mapper, and SELinux..."
./scripts/config --enable TMPFS
./scripts/config --enable TMPFS_POSIX_ACL
./scripts/config --enable FUSE_FS
./scripts/config --enable OVERLAY_FS
./scripts/config --enable SQUASHFS
./scripts/config --enable CGROUPS
./scripts/config --enable NAMESPACES
./scripts/config --enable NET_NS
./scripts/config --enable PID_NS
./scripts/config --enable USER_NS
./scripts/config --enable UTS_NS
./scripts/config --enable IPC_NS
./scripts/config --enable DEVTMPFS
./scripts/config --enable DEVTMPFS_MOUNT
./scripts/config --enable IKCONFIG
./scripts/config --enable IKCONFIG_PROC
./scripts/config --enable PSI
./scripts/config --enable MEMCG
./scripts/config --enable CPUSETS
./scripts/config --enable CGROUP_CPUACCT
./scripts/config --enable CGROUP_SCHED
./scripts/config --enable BLK_CGROUP
./scripts/config --enable SECURITY
./scripts/config --enable SECURITY_SELINUX
./scripts/config --enable SECURITY_SELINUX_BOOTPARAM
./scripts/config --enable SECURITY_SELINUX_DEVELOP
./scripts/config --set-str LSM "landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,bpf"
./scripts/config --enable AUDIT
./scripts/config --enable EXT4_FS
./scripts/config --enable EXT4_FS_POSIX_ACL
./scripts/config --enable F2FS_FS
./scripts/config --enable EROFS_FS
./scripts/config --enable BLK_DEV_DM
./scripts/config --enable DM_LINEAR
./scripts/config --enable DM_VERITY

echo ">>> Resolving Kconfig dependencies..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Output config status for verification
echo ""
echo ">>> Config verification status:"
grep VIRTIO_MMIO .config
grep VIRTIO_BLK .config
grep -E "CONFIG_SECURITY_SELINUX|CONFIG_LSM" .config
grep -E "CONFIG_BLK_DEV_DM|CONFIG_DM_LINEAR" .config
grep CONFIG_PSI .config
echo ""

echo ">>> Compiling kernel Image using $(nproc) jobs..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image -j$(nproc)

echo ">>> Copying compiled Image to output volume..."
mkdir -p /output
cp arch/arm64/boot/Image /output/Image

echo "============================================="
echo "  KERNEL COMPILED SUCCESSFULY!"
echo "============================================="
