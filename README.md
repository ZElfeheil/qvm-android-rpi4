# QVM Android RPi4: Run Android Automotive OS (AAOS) as a Guest VM on QNX 8.0

This repository contains the configuration files, cross-compilation scripts, and in-place partition patchers required to successfully run and boot **Android Automotive OS (AOSP / GloDroid Android 13)** as a virtualized Guest VM inside the **QNX Hypervisor (QVM)** on a **Raspberry Pi 4 (8GB)**.

---

## Features

*   **GICv2 Virtualization**: Maps CPU and distributor interfaces directly to the QVM Guest virtual boundaries.
*   **VirtIO MMIO Storage**: Configures QVM's virtual block driver (`vdev virtio-blk`) to boot Android directly from an emulated partition table.
*   **Interactive Root Shell**: Connects the guest UART console (`pl011`) directly to the QVM terminal stdout/stdin for real-time interaction.
*   **Encryption & Quota Bypass**: Patches the virtual disk images and filesystem superblocks in-place to enable unencrypted ext4 booting, bypassing missing kernel `dm-default-key` and `CONFIG_QUOTA` drivers.
*   **PSI Support**: Activates Pressure Stall Information (`psi=1`) required to prevent Low Memory Killer (`lmkd`) boot loop crashes.

---

## Repository Structure

```text
├── README.md               # This setup and integration guide
├── android.qvmconf         # QNX Hypervisor QVM configuration file
├── bcm2711.dtb             # Clean Device Tree Blob (Copy from QNX BSP)
├── ramdisk_patched.img     # Pre-patched ramdisk (1.67MB) with fstab.rpi4car injected
├── rebuild_kernel.sh       # Orchestrator script to build and run the Docker environment
├── docker/
│   ├── Dockerfile          # Builds the compiler container image (Ubuntu 22.04 + toolchain)
│   └── build_kernel.sh     # Inside-container compilation script (clones and builds kernel)
└── scripts/
    ├── modify_userdata.py  # Superblock patcher to disable ext4 quota remotely
    └── patch_super_fstab.py # In-place vendor fstab editor inside sdcard_virtio.img
```


---

## Memory Layout & Mapping Architecture

The guest VM is configured with **4GB of RAM (`ram 0x80000000,4G`)**, leaving 4GB for the QNX host. The virtual hardware and interrupt layout is mapped as follows:

| Component | Guest Physical Address (GPA) | Host Physical Address (HPA) | Description |
| :--- | :--- | :--- | :--- |
| **Guest RAM** | `0x80000000` - `0x17FFFFFFF` | Dynamic (Mapped by MMU Stage 2) | 4GB virtual RAM range allocated to the Guest. |
| **Kernel Load Address** | `0x80080000` | Inside Guest RAM | standard load offset (`+512KB` from base `0x80000000`) for the kernel. |
| **Virtual GIC Distributor** | `0x09000000` | Host GICD: `0xFF841000` | Virtualized Generic Interrupt Controller Distributor interface. |
| **Virtual GIC CPU Interface**| `0x09002000` | Host GICV: `0xFF846000` | Virtualized Generic Interrupt Controller CPU interface. |
| **PL011 UART** | `0x1C090000` | Physical: `0xFE201000` (RPi4 UART0) | Emulated serial port routed to terminal standard I/O. |
| **VirtIO Block Device** | `0x1C0D0000` | N/A (Emulated in software) | Memory-Mapped I/O (MMIO) boundary for the disk device. |

---

## Implementation Paths

You can use this project via two different methods:

### Option 1: Quick Deployment (Using Binary & Python Patchers)
This option is ideal if you already have a compiled AOSP/GloDroid `sdcard.img` and want to boot it as a guest VM on QNX without setting up the full AOSP building environment.

#### 1. Transfer configurations to QNX
Copy `android.qvmconf`, `ramdisk_patched.img` (renamed to `ramdisk.img`), and your QNX BSP DTB to the target RPi4:
```bash
# On your Mac:
scp android.qvmconf root@<RPI4_IP>:/guests/android/android.qvmconf
scp ramdisk_patched.img root@<RPI4_IP>:/guests/android/ramdisk.img

# Extract and copy bcm2711-rpi-4-b.dtb from your QNX BSP workspace:
scp /path/to/qnx800/bsp/raspberrypi-rpi4/images/bcm2711-rpi-4-b.dtb root@<RPI4_IP>:/guests/android/bcm2711.dtb
```

#### 2. Cross-Compile the VirtIO Kernel
Run the build script on your development machine. It will automatically build the local Docker compilation environment image (`qvm-android-kernel-builder`) and execute it to output the custom kernel `Image` containing VirtIO MMIO and SELinux parameters:
```bash
# On your Mac:
chmod +x rebuild_kernel.sh
./rebuild_kernel.sh

# Transfer the compiled Image to QNX host:
scp output/Image root@<RPI4_IP>:/guests/android/Image
```


#### 3. Patch the Android Disk Image
Generate your GloDroid/AOSP `sdcard.img`, rename it to `sdcard_virtio.img`, transfer it to `/guests/android/sdcard_virtio.img` on the QNX host, and run the Python patchers to configure unencrypted booting:
```bash
# Disable the ext4 quota feature flag in the userdata partition (vda10) superblock:
python3 scripts/modify_userdata.py

# Patch /vendor/etc/fstab.rpi4 inside the dynamic super partition (vda8) in-place:
python3 scripts/patch_super_fstab.py
```

#### 4. Launch the Guest VM
SSH into the QNX host and boot the guest:
```bash
qvm @/guests/android/android.qvmconf
```
*Press Enter when boot completes to drop into the interactive root shell:* `console:/ $`

---

### Option 2: Native AOSP Integration (Building From Source)
If you are compiling Android Automotive from source, you can integrate all kernel and filesystem configurations directly into the AOSP tree to avoid post-build patching scripts:

#### 1. Kernel Configuration Integration
Append the VirtIO, Device Mapper, and PSI config flags natively to your kernel config fragment:
*   **File**: `device/glodroid/rpi4/kernel.config` (or AOSP kernel defconfig for broadcom/rpi4).
*   **Append**:
    ```config
    CONFIG_VIRTIO=y
    CONFIG_VIRTIO_MMIO=y
    CONFIG_VIRTIO_BLK=y
    CONFIG_VIRTIO_NET=y
    CONFIG_VIRTIO_CONSOLE=y
    CONFIG_VIRTIO_GPU=y
    CONFIG_BLK_DEV_DM=y
    CONFIG_DM_LINEAR=y
    CONFIG_PSI=y
    ```

#### 2. Native Fstab Integration
Edit the fstab template in the device tree directly so AOSP packs the clean version into `/vendor` and `/first_stage_ramdisk` automatically:
*   **File**: `device/glodroid/rpi4/fstab.rpi4`
*   **Action**:
    1.  Add the `slotselect` option to the `/system`, `/vendor`, `/product`, and `/system_ext` entries.
    2.  Modify `/data` (userdata) to use `ext4` and remove `quota`, `fileencryption=...`, and `metadata_encryption=...` options:
        ```text
        /dev/block/by-name/userdata /data ext4 noatime,nosuid,nodev,barrier=1 wait,check,latemount,formattable
        ```

#### 3. Bypassing Encryption Natively
Disable product-level file-based encryption (FBE) overrides:
*   **File**: `device/glodroid/rpi4/device.mk` (or `rpi4car.mk`).
*   **Action**: Comment out or modify variables that default `ro.crypto.state=encrypted`.

#### 4. Flash and Boot
Build the AOSP project natively and flash the image output directly onto your target. Start the Guest VM using:
```bash
qvm @/guests/android/android.qvmconf
```

---

## References

*   **QNX Hypervisor BSP & Board Support**: [QNX Hypervisor Getting Started GitLab](https://gitlab.com/qnx/hypervisor/getting-started?ref=devblog.qnx.com)
*   **GloDroid Platform Source**: [GitHub - GloDroid](https://github.com/GloDroid)
*   **A3M Android Automotive Manifest**: [GitHub - a3m-rpi-manifest](https://github.com/aospandaaos/a3m-rpi-manifest)
