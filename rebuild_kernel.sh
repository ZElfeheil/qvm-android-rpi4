#!/bin/bash
# =============================================================================
# AAOS Kernel Rebuild for QNX Hypervisor VirtIO MMIO Support
# =============================================================================
# This script rebuilds the Raspberry Pi 4 Android kernel with
# CONFIG_VIRTIO_MMIO=y, which is required for QNX Hypervisor's VirtIO devices.
#
# Prerequisites:
#   - Docker Desktop installed on Mac
#   - Internet connection for cloning kernel source
#
# Output:
#   - ./output/Image          (new kernel with VIRTIO_MMIO support)
#
# Usage:
#   chmod +x rebuild_kernel.sh
#   ./rebuild_kernel.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
mkdir -p "${OUTPUT_DIR}"

echo "============================================="
echo "  AAOS Kernel Rebuild for QNX VirtIO MMIO"
echo "============================================="
echo ""
echo "This will cross-compile the RPi4 kernel with"
echo "CONFIG_VIRTIO_MMIO=y using Docker."
echo ""
echo "Output will be in: ${OUTPUT_DIR}/"
echo ""

# Build kernel inside Docker
docker run --rm --platform linux/amd64 \
  -v "${OUTPUT_DIR}:/output" \
  ubuntu:22.04 \
  bash -c '
set -e

echo ">>> Installing build dependencies..."
apt-get update -qq
apt-get install -y -qq git make gcc-aarch64-linux-gnu bc flex bison \
  libssl-dev libelf-dev cpio python3 > /dev/null 2>&1

echo ">>> Cloning Raspberry Pi kernel (6.1.y branch)..."
git clone --depth 1 --branch rpi-6.1.y \
  https://github.com/raspberrypi/linux.git /build/linux
cd /build/linux

echo ">>> Configuring kernel (bcm2711_defconfig + Android + VirtIO)..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2711_defconfig

# ---- Enable Android features ----
./scripts/config --enable ANDROID
./scripts/config --enable ANDROID_BINDER_IPC
./scripts/config --enable ANDROID_BINDERFS
./scripts/config --enable ANDROID_BINDER_DEVICES
./scripts/config --set-str ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder"
./scripts/config --enable STAGING
./scripts/config --enable ASHMEM

# ---- Enable VirtIO (ALL transports) ----
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

# ---- Enable Android-required filesystems & features ----
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

# Resolve dependencies
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Verify VIRTIO_MMIO is set
echo ""
echo ">>> Verifying VirtIO, SELinux, and DM config:"
grep VIRTIO_MMIO /build/linux/.config
grep VIRTIO_BLK /build/linux/.config
grep -E "CONFIG_SECURITY_SELINUX|CONFIG_LSM" /build/linux/.config
grep -E "CONFIG_BLK_DEV_DM|CONFIG_DM_LINEAR" /build/linux/.config
echo ""

echo ">>> Building kernel Image (this takes 10-30 minutes)..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image -j$(nproc)

echo ">>> Copying output..."
cp arch/arm64/boot/Image /output/Image
echo ""
echo "============================================="
echo "  BUILD COMPLETE!"
echo "  Kernel Image: /output/Image"
echo "============================================="
'

echo ""
echo "============================================="
echo "  Kernel built successfully!"
echo "  Output: ${OUTPUT_DIR}/Image"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Copy kernel to RPi4:  scp ${OUTPUT_DIR}/Image root@<RPI4_IP>:/guests/android/Image"
echo "  2. Extract ramdisk (see below)"
echo "  3. Boot with: qvm @/guests/android/android.qvmconf"
