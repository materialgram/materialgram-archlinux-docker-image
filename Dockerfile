FROM archlinux/archlinux:latest

# Setup
RUN pacman -Syu --noconfirm && \
    pacman -S --needed base-devel sudo github-cli cmake git ninja python boost fmt range-v3 tl-expected microsoft-gsl meson extra-cmake-modules wayland-protocols plasma-wayland-protocols libtg_owt gobject-introspection mm-common libxcomposite hunspell ffmpeg hicolor-icon-theme lz4 minizip openal rnnoise ttf-opensans glibmm-2.68 qt6-imageformats qt6-svg qt6-wayland xxhash pipewire libxtst libxrandr jemalloc abseil-cpp libdispatch openssl protobuf pacman-contrib chrpath python-packaging kcoreaddons --noconfirm && \
    rm -rf /var/cache/pacman/pkg/* && \
    pacman -Sc --noconfirm

RUN mkdir /home/builder

WORKDIR /home/builder
