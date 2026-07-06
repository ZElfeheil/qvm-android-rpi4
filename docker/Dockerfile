# Use Ubuntu 22.04 as the base image for the cross-compilation environment
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install kernel compilation and cross-build dependencies
RUN apt-get update -qq && apt-get install -y -qq \
    git \
    make \
    gcc-aarch64-linux-gnu \
    bc \
    flex \
    bison \
    libssl-dev \
    libelf-dev \
    cpio \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Set up build directories
WORKDIR /build

# Copy the build execution script into the container
COPY build_kernel.sh /build/build_kernel.sh
RUN chmod +x /build/build_kernel.sh

# Start the build by default
CMD ["/build/build_kernel.sh"]
