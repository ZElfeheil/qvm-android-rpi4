#!/bin/bash
# =============================================================================
# AAOS Guest Kernel Rebuild Script (Docker Orchestration)
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
DOCKER_DIR="${SCRIPT_DIR}/docker"

mkdir -p "${OUTPUT_DIR}"

echo "============================================="
echo "  AAOS Kernel Rebuild for QNX Guest VM"
echo "============================================="
echo "This will orchestrate the cross-compilation"
echo "of the guest kernel inside a Docker container."
echo ""
echo "Output will be located in: ${OUTPUT_DIR}/Image"
echo "============================================="
echo ""

# Build the Docker compilation environment image
echo ">>> Building Docker compilation image..."
docker build -t qvm-android-kernel-builder "${DOCKER_DIR}"

# Run the container to compile the kernel, mounting our output directory
echo ">>> Running kernel compilation inside Docker..."
docker run --rm \
  -v "${OUTPUT_DIR}:/output" \
  qvm-android-kernel-builder

echo ""
echo "============================================="
echo "  BUILD RUN SUCCESSFUL!"
echo "  Kernel Image generated at: ${OUTPUT_DIR}/Image"
echo "============================================="
echo ""
echo "Next steps:"
echo "  Copy kernel to QNX host: scp ${OUTPUT_DIR}/Image root@<RPI4_IP>:/guests/android/Image"
echo ""
