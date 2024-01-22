# Use official Arch Linux image as base image
FROM archlinux:latest

# Setup
RUN pacman -Syu --noconfirm && \
    pacman -S --needed sudo vim git wget tar unzip zip --noconfirm && \
    rm -rf /var/cache/pacman/pkg/* && \
    pacman -Sc --noconfirm

# Create user 'builder'
RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers

# Switch to the new user for any future commands
USER builder

# Change directory to /home/builder
WORKDIR /home/builder

