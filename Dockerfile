# syntax=docker/dockerfile:1

FROM rockylinux:8 AS builder-base
ENV LANG C.UTF-8
ENV LIBRARY_PATH /usr/local/lib64:/usr/local/lib:/lib64:/lib:/usr/lib64:/usr/lib
ENV LD_LIBRARY_PATH $LIBRARY_PATH
ENV PKG_CONFIG_PATH /usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig

RUN dnf -y install epel-release \
	&& dnf config-manager --set-enabled powertools \
	&& dnf -y install autoconf automake libtool pkgconfig make patch git \
		python3.11-pip python3.11-devel gperf flex bison clang lld yasm \
		file which perl-open perl-XML-Parser perl-IPC-Cmd xorg-x11-util-macros \
		gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils \
		libffi-devel fontconfig-devel freetype-devel libX11-devel \
		alsa-lib-devel pulseaudio-libs-devel mesa-libGL-devel mesa-libEGL-devel \
		mesa-libgbm-devel libdrm-devel vulkan-devel libva-devel libvdpau-devel \
		glib2-devel at-spi2-core-devel gtk3-devel boost1.78-devel fmt-devel \
	&& dnf clean all

SHELL [ "bash", "-c", ". /opt/rh/gcc-toolset-12/enable; exec bash -c \"$@\"", "-s"]

WORKDIR /usr/src/Libraries

RUN python3 -m pip install meson ninja

RUN mkdir /opt/cmake \
	&& curl -sSLo cmake-3.27.6-Linux-x86_64.sh https://github.com/Kitware/CMake/releases/download/v3.27.6/cmake-3.27.6-Linux-x86_64.sh \
	&& sh cmake-3.27.6-Linux-x86_64.sh --prefix=/opt/cmake --skip-license \
	&& ln -s /opt/cmake/bin/cmake /usr/local/bin/cmake \
	&& rm cmake-3.27.6-Linux-x86_64.sh

FROM builder-base AS builder
ENV AR gcc-ar
ENV RANLIB gcc-ranlib
ENV NM gcc-nm
ENV CFLAGS -g -O3 -flto=auto -ffat-lto-objects -pipe -fPIC -fno-omit-frame-pointer -fstack-protector-all -fstack-clash-protection -fcf-protection -DNDEBUG -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS
ENV CXXFLAGS $CFLAGS

FROM builder AS patches
RUN git init patches \
	&& cd patches \
	&& git remote add origin https://github.com/desktop-app/patches.git \
	&& git fetch --depth=1 origin b85bc8bb1ba866dfa3d1ee983dc642fa6ccff12a \
	&& git reset --hard FETCH_HEAD \
	&& rm -rf .git

FROM builder AS nasm
RUN git clone -b nasm-2.15.05 --depth=1 https://github.com/netwide-assembler/nasm.git \
	&& cd nasm \
	&& ./autogen.sh \
	&& ./configure \
	&& make -j$(nproc) \
	&& mkdir -p "/usr/src/Libraries/nasm-cache/usr/local/bin" \
	&& install -c nasm "/usr/src/Libraries/nasm-cache/usr/local/bin/nasm" \
	&& cd .. \
	&& rm -rf nasm

FROM builder AS zlib
RUN git init zlib \
	&& cd zlib \
	&& git remote add origin https://github.com/madler/zlib.git \
	&& git fetch --depth=1 origin 643e17b7498d12ab8d15565662880579692f769d \
	&& git reset --hard FETCH_HEAD \
	&& ./configure \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/zlib-cache" install \
	&& cd .. \
	&& rm -rf zlib

FROM builder AS xz
RUN git clone -b v5.4.4 --depth=1 https://github.com/tukaani-project/xz.git \
	&& cd xz \
	&& cmake -B build . -DCMAKE_BUILD_TYPE=None \
	&& cmake --build build -j$(nproc) \
	&& DESTDIR="/usr/src/Libraries/xz-cache" cmake --install build \
	&& cd .. \
	&& rm -rf xz

FROM builder AS protobuf
RUN git clone -b v21.9 --depth=1 --recursive https://github.com/protocolbuffers/protobuf.git \
	&& cd protobuf \
	&& git init third_party/abseil-cpp \
	&& cd third_party/abseil-cpp \
	&& git remote add origin https://github.com/abseil/abseil-cpp.git \
	&& git fetch --depth=1 origin 273292d1cfc0a94a65082ee350509af1d113344d \
	&& git reset --hard FETCH_HEAD \
	&& cd ../.. \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-Dprotobuf_BUILD_TESTS=OFF \
		-Dprotobuf_BUILD_PROTOBUF_BINARIES=ON \
		-Dprotobuf_BUILD_LIBPROTOC=ON \
		-Dprotobuf_WITH_ZLIB_DEFAULT=OFF \
		-Dprotobuf_DEBUG_POSTFIX="" \
	&& cmake --build build --parallel \
	&& rm -rf .git

FROM builder AS lcms2
RUN git clone -b lcms2.15 --depth=1 https://github.com/mm2/Little-CMS.git \
	&& cd Little-CMS \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
	&& meson compile -C build \
	&& DESTDIR="/usr/src/Libraries/lcms2-cache" meson install -C build \
	&& cd .. \
	&& rm -rf Little-CMS

FROM builder AS brotli
RUN git clone -b v1.1.0 --depth=1 https://github.com/google/brotli.git \
	&& cd brotli \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DBROTLI_DISABLE_TESTS=ON \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/brotli-cache" cmake --install build \
	&& cd .. \
	&& rm -rf brotli

FROM builder AS highway
RUN git clone -b 1.0.7 --depth=1 https://github.com/google/highway.git \
	&& cd highway \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_TESTING=OFF \
		-DHWY_ENABLE_CONTRIB=OFF \
		-DHWY_ENABLE_EXAMPLES=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/highway-cache" cmake --install build \
	&& cd .. \
	&& rm -rf highway

FROM builder AS mozjpeg
RUN git clone -b v4.1.4 --depth=1 https://github.com/mozilla/mozjpeg.git \
	&& cd mozjpeg \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DCMAKE_INSTALL_PREFIX=/usr/local \
		-DWITH_JPEG8=ON \
		-DPNG_SUPPORTED=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/mozjpeg-cache" cmake --install build \
	&& cd .. \
	&& rm -rf mozjpeg

FROM builder AS opus
RUN git clone -b v1.4 --depth=1 https://github.com/xiph/opus.git \
	&& cd opus \
	&& ./autogen.sh \
	&& ./configure \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/opus-cache" install \
	&& cd .. \
	&& rm -rf opus

FROM builder AS dav1d
COPY --link --from=nasm /usr/src/Libraries/nasm-cache /

RUN git clone -b 1.4.1 --depth=1 https://github.com/videolan/dav1d.git \
	&& cd dav1d \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Denable_tools=false \
		-Denable_tests=false \
	&& meson compile -C build \
	&& DESTDIR="/usr/src/Libraries/dav1d-cache" meson install -C build \
	&& cd .. \
	&& rm -rf dav1d

FROM builder AS libde265
RUN git clone -b v1.0.15 --depth=1 https://github.com/strukturag/libde265.git \
	&& cd libde265 \
	&& cmake -GNinja . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DENABLE_DECODER=OFF \
		-DENABLE_SDL=OFF \
	&& cmake --build . --parallel \
	&& DESTDIR="/usr/src/Libraries/libde265-cache" cmake --install . \
	&& cd .. \
	&& rm -rf libde265

FROM builder AS libvpx
RUN git init libvpx \
	&& cd libvpx \
	&& git remote add origin https://github.com/webmproject/libvpx.git \
	&& git fetch --depth=1 origin 51057f4ba894e13f9bba278905bacf6aaaecd992 \
	&& git reset --hard FETCH_HEAD \
	&& CFLAGS="$CFLAGS -fno-lto" CXXFLAGS="$CXXFLAGS -fno-lto" ./configure \
		--disable-examples \
		--disable-unit-tests \
		--disable-tools \
		--disable-docs \
		--enable-vp8 \
		--enable-vp9 \
		--enable-webm-io \
		--size-limit=4096x4096 \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libvpx-cache" install \
	&& cd .. \
	&& rm -rf libvpx

FROM builder AS libwebp
RUN git clone -b chrome-m116-5845 --depth=1 https://github.com/webmproject/libwebp.git \
	&& cd libwebp \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DWEBP_BUILD_ANIM_UTILS=OFF \
		-DWEBP_BUILD_CWEBP=OFF \
		-DWEBP_BUILD_DWEBP=OFF \
		-DWEBP_BUILD_GIF2WEBP=OFF \
		-DWEBP_BUILD_IMG2WEBP=OFF \
		-DWEBP_BUILD_VWEBP=OFF \
		-DWEBP_BUILD_WEBPMUX=OFF \
		-DWEBP_BUILD_WEBPINFO=OFF \
		-DWEBP_BUILD_EXTRAS=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/libwebp-cache" cmake --install build \
	&& cd .. \
	&& rm -rf libwebp

FROM builder AS libavif
COPY --link --from=dav1d /usr/src/Libraries/dav1d-cache /

RUN git clone -b v1.0.4 --depth=1 https://github.com/AOMediaCodec/libavif.git \
	&& cd libavif \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DAVIF_CODEC_DAV1D=ON \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/libavif-cache" cmake --install build \
	&& cd .. \
	&& rm -rf libavif

FROM builder AS libheif
COPY --link --from=libde265 /usr/src/Libraries/libde265-cache /

RUN git clone -b v1.17.6 --depth=1 https://github.com/strukturag/libheif.git \
	&& cd libheif \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_TESTING=OFF \
		-DENABLE_PLUGIN_LOADING=OFF \
		-DWITH_X265=OFF \
		-DWITH_AOM_DECODER=OFF \
		-DWITH_AOM_ENCODER=OFF \
		-DWITH_RAV1E=OFF \
		-DWITH_RAV1E_PLUGIN=OFF \
		-DWITH_SvtEnc=OFF \
		-DWITH_SvtEnc_PLUGIN=OFF \
		-DWITH_DAV1D=OFF \
		-DWITH_EXAMPLES=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/libheif-cache" cmake --install build \
	&& cd .. \
	&& rm -rf libheif

FROM builder AS libjxl
COPY --link --from=lcms2 /usr/src/Libraries/lcms2-cache /
COPY --link --from=brotli /usr/src/Libraries/brotli-cache /
COPY --link --from=highway /usr/src/Libraries/highway-cache /

RUN git clone -b v0.8.2 --depth=1 https://github.com/libjxl/libjxl.git \
	&& cd libjxl \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_TESTING=OFF \
		-DJPEGXL_ENABLE_DEVTOOLS=OFF \
		-DJPEGXL_ENABLE_TOOLS=OFF \
		-DJPEGXL_ENABLE_JPEGLI_LIBJPEG=OFF \
		-DJPEGXL_ENABLE_DOXYGEN=OFF \
		-DJPEGXL_ENABLE_MANPAGES=OFF \
		-DJPEGXL_ENABLE_BENCHMARK=OFF \
		-DJPEGXL_ENABLE_EXAMPLES=OFF \
		-DJPEGXL_ENABLE_JNI=OFF \
		-DJPEGXL_ENABLE_SJPEG=OFF \
		-DJPEGXL_ENABLE_OPENEXR=OFF \
		-DJPEGXL_ENABLE_SKCMS=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/libjxl-cache" cmake --install build \
	&& cd .. \
	&& rm -rf libjxl

FROM builder AS rnnoise
RUN git clone -b master --depth=1 https://github.com/desktop-app/rnnoise.git \
	&& cd rnnoise \
	&& cmake -GNinja -B build . -DCMAKE_BUILD_TYPE=None \
	&& cmake --build build --parallel \
	&& mkdir -p "/usr/src/Libraries/rnnoise-cache/usr/local/include" \
	&& cp "include/rnnoise.h" "/usr/src/Libraries/rnnoise-cache/usr/local/include/" \
	&& mkdir -p "/usr/src/Libraries/rnnoise-cache/usr/local/lib" \
	&& cp "build/librnnoise.a" "/usr/src/Libraries/rnnoise-cache/usr/local/lib/" \
	&& cd .. \
	&& rm -rf rnnoise

FROM builder AS xcb-proto
RUN git clone -b xcb-proto-1.16.0 --depth=1 https://github.com/gitlab-freedesktop-mirrors/xcbproto.git \
	&& cd xcbproto \
	&& ./autogen.sh \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-proto-cache" install \
	&& cd .. \
	&& rm -rf xcbproto

FROM builder AS xcb
COPY --link --from=xcb-proto /usr/src/Libraries/xcb-proto-cache /

RUN git clone -b libxcb-1.16 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxcb.git \
	&& cd libxcb \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-cache" install \
	&& cd .. \
	&& rm -rf libxcb

FROM builder AS xcb-wm
RUN git clone -b xcb-util-wm-0.4.2 --depth=1 --recursive https://github.com/gitlab-freedesktop-mirrors/libxcb-wm.git \
	&& cd libxcb-wm \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-wm-cache" install \
	&& cd .. \
	&& rm -rf libxcb-wm

FROM builder AS xcb-util
RUN git clone -b xcb-util-0.4.1 --depth=1 --recursive https://github.com/gitlab-freedesktop-mirrors/libxcb-util.git \
	&& cd libxcb-util \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-util-cache" install \
	&& cd .. \
	&& rm -rf libxcb-util

FROM builder AS xcb-image
COPY --link --from=xcb-util /usr/src/Libraries/xcb-util-cache /

RUN git clone -b xcb-util-image-0.4.1 --depth=1 --recursive https://github.com/gitlab-freedesktop-mirrors/libxcb-image.git \
	&& cd libxcb-image \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-image-cache" install \
	&& cd .. \
	&& rm -rf libxcb-image

FROM builder AS xcb-keysyms
RUN git clone -b xcb-util-keysyms-0.4.1 --depth=1 --recursive https://github.com/gitlab-freedesktop-mirrors/libxcb-keysyms.git \
	&& cd libxcb-keysyms \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-keysyms-cache" install \
	&& cd .. \
	&& rm -rf libxcb-keysyms

FROM builder AS xcb-render-util
RUN git clone -b xcb-util-renderutil-0.3.10 --depth=1 --recursive https://github.com/gitlab-freedesktop-mirrors/libxcb-render-util.git \
	&& cd libxcb-render-util \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-render-util-cache" install \
	&& cd .. \
	&& rm -rf libxcb-render-util

FROM builder AS xcb-cursor
COPY --link --from=xcb-util /usr/src/Libraries/xcb-util-cache /
COPY --link --from=xcb-image /usr/src/Libraries/xcb-image-cache /
COPY --link --from=xcb-render-util /usr/src/Libraries/xcb-render-util-cache /

RUN git clone -b xcb-util-cursor-0.1.4 --depth=1 --recursive https://github.com/gitlab-freedesktop-mirrors/libxcb-cursor.git \
	&& cd libxcb-cursor \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/xcb-cursor-cache" install \
	&& cd .. \
	&& rm -rf libxcb-cursor

FROM builder AS libXext
RUN git clone -b libXext-1.3.5 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxext.git \
	&& cd libxext \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXext-cache" install \
	&& cd .. \
	&& rm -rf libxext

FROM builder AS libXtst
RUN git clone -b libXtst-1.2.4 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxtst.git \
	&& cd libxtst \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXtst-cache" install \
	&& cd .. \
	&& rm -rf libxtst

FROM builder AS libXfixes
RUN git clone -b libXfixes-5.0.3 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxfixes.git \
	&& cd libxfixes \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXfixes-cache" install \
	&& cd .. \
	&& rm -rf libxfixes

FROM builder AS libXv
COPY --link --from=libXext /usr/src/Libraries/libXext-cache /

RUN git clone -b libXv-1.0.12 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxv.git \
	&& cd libxv \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXv-cache" install \
	&& cd .. \
	&& rm -rf libxv

FROM builder AS libXrandr
RUN git clone -b libXrandr-1.5.3 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxrandr.git \
	&& cd libxrandr \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXrandr-cache" install \
	&& cd .. \
	&& rm -rf libxrandr

FROM builder AS libXrender
RUN git clone -b libXrender-0.9.11 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxrender.git \
	&& cd libxrender \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXrender-cache" install \
	&& cd .. \
	&& rm -rf libxrender

FROM builder AS libXdamage
RUN git clone -b libXdamage-1.1.6 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxdamage.git \
	&& cd libxdamage \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXdamage-cache" install \
	&& cd .. \
	&& rm -rf libxdamage

FROM builder AS libXcomposite
RUN git clone -b libXcomposite-0.4.6 --depth=1 https://github.com/gitlab-freedesktop-mirrors/libxcomposite.git \
	&& cd libxcomposite \
	&& ./autogen.sh --enable-static \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/libXcomposite-cache" install \
	&& cd .. \
	&& rm -rf libxcomposite

FROM builder AS wayland
RUN git clone -b 1.19.0 --depth=1 https://github.com/gitlab-freedesktop-mirrors/wayland.git \
	&& cd wayland \
	&& sed -i "/subdir('tests')/d" meson.build \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Ddocumentation=false \
		-Ddtd_validation=false \
		-Dicon_directory=/usr/share/icons \
	&& meson compile -C build \
	&& DESTDIR="/usr/src/Libraries/wayland-cache" meson install -C build \
	&& cd .. \
	&& rm -rf wayland

FROM builder AS nv-codec-headers
RUN git clone -b n12.0.16.0 --depth=1 https://github.com/FFmpeg/nv-codec-headers.git \
	&& DESTDIR="/usr/src/Libraries/nv-codec-headers-cache" make -C nv-codec-headers install \
	&& rm -rf nv-codec-headers

FROM builder AS ffmpeg
COPY --link --from=opus /usr/src/Libraries/opus-cache /
COPY --link --from=dav1d /usr/src/Libraries/dav1d-cache /
COPY --link --from=libvpx /usr/src/Libraries/libvpx-cache /
COPY --link --from=libXext /usr/src/Libraries/libXext-cache /
COPY --link --from=libXv /usr/src/Libraries/libXv-cache /
COPY --link --from=nv-codec-headers /usr/src/Libraries/nv-codec-headers-cache /

RUN git clone -b n5.1.3 --depth=1 https://github.com/FFmpeg/FFmpeg.git \
	&& cd FFmpeg \
	&& ./configure \
		--extra-cflags="-DCONFIG_SAFE_BITSTREAM_READER=1" \
		--extra-cxxflags="-DCONFIG_SAFE_BITSTREAM_READER=1" \
		--disable-debug \
		--disable-optimizations \
		--disable-inline-asm \
		--disable-programs \
		--disable-doc \
		--disable-network \
		--disable-autodetect \
		--disable-everything \
		--enable-libdav1d \
		--enable-libopus \
		--enable-libvpx \
		--enable-vaapi \
		--enable-vdpau \
		--enable-xlib \
		--enable-libdrm \
		--enable-ffnvcodec \
		--enable-nvdec \
		--enable-cuvid \
		--enable-protocol=file \
		--enable-hwaccel=av1_vaapi \
		--enable-hwaccel=av1_nvdec \
		--enable-hwaccel=h264_vaapi \
		--enable-hwaccel=h264_vdpau \
		--enable-hwaccel=h264_nvdec \
		--enable-hwaccel=hevc_vaapi \
		--enable-hwaccel=hevc_vdpau \
		--enable-hwaccel=hevc_nvdec \
		--enable-hwaccel=mpeg2_vaapi \
		--enable-hwaccel=mpeg2_vdpau \
		--enable-hwaccel=mpeg2_nvdec \
		--enable-hwaccel=mpeg4_vaapi \
		--enable-hwaccel=mpeg4_vdpau \
		--enable-hwaccel=mpeg4_nvdec \
		--enable-hwaccel=vp8_vaapi \
		--enable-hwaccel=vp8_nvdec \
		--enable-decoder=aac \
		--enable-decoder=aac_fixed \
		--enable-decoder=aac_latm \
		--enable-decoder=aasc \
		--enable-decoder=ac3 \
		--enable-decoder=alac \
		--enable-decoder=av1 \
		--enable-decoder=av1_cuvid \
		--enable-decoder=eac3 \
		--enable-decoder=flac \
		--enable-decoder=gif \
		--enable-decoder=h264 \
		--enable-decoder=hevc \
		--enable-decoder=libdav1d \
		--enable-decoder=libvpx_vp8 \
		--enable-decoder=libvpx_vp9 \
		--enable-decoder=mp1 \
		--enable-decoder=mp1float \
		--enable-decoder=mp2 \
		--enable-decoder=mp2float \
		--enable-decoder=mp3 \
		--enable-decoder=mp3adu \
		--enable-decoder=mp3adufloat \
		--enable-decoder=mp3float \
		--enable-decoder=mp3on4 \
		--enable-decoder=mp3on4float \
		--enable-decoder=mpeg4 \
		--enable-decoder=msmpeg4v2 \
		--enable-decoder=msmpeg4v3 \
		--enable-decoder=opus \
		--enable-decoder=pcm_alaw \
		--enable-decoder=pcm_f32be \
		--enable-decoder=pcm_f32le \
		--enable-decoder=pcm_f64be \
		--enable-decoder=pcm_f64le \
		--enable-decoder=pcm_lxf \
		--enable-decoder=pcm_mulaw \
		--enable-decoder=pcm_s16be \
		--enable-decoder=pcm_s16be_planar \
		--enable-decoder=pcm_s16le \
		--enable-decoder=pcm_s16le_planar \
		--enable-decoder=pcm_s24be \
		--enable-decoder=pcm_s24daud \
		--enable-decoder=pcm_s24le \
		--enable-decoder=pcm_s24le_planar \
		--enable-decoder=pcm_s32be \
		--enable-decoder=pcm_s32le \
		--enable-decoder=pcm_s32le_planar \
		--enable-decoder=pcm_s64be \
		--enable-decoder=pcm_s64le \
		--enable-decoder=pcm_s8 \
		--enable-decoder=pcm_s8_planar \
		--enable-decoder=pcm_u16be \
		--enable-decoder=pcm_u16le \
		--enable-decoder=pcm_u24be \
		--enable-decoder=pcm_u24le \
		--enable-decoder=pcm_u32be \
		--enable-decoder=pcm_u32le \
		--enable-decoder=pcm_u8 \
		--enable-decoder=pcm_zork \
		--enable-decoder=vorbis \
		--enable-decoder=vp8 \
		--enable-decoder=wavpack \
		--enable-decoder=wmalossless \
		--enable-decoder=wmapro \
		--enable-decoder=wmav1 \
		--enable-decoder=wmav2 \
		--enable-decoder=wmavoice \
		--enable-encoder=libopus \
		--enable-filter=atempo \
		--enable-parser=aac \
		--enable-parser=aac_latm \
		--enable-parser=flac \
		--enable-parser=h264 \
		--enable-parser=hevc \
		--enable-parser=mpeg4video \
		--enable-parser=mpegaudio \
		--enable-parser=opus \
		--enable-parser=vorbis \
		--enable-demuxer=aac \
		--enable-demuxer=flac \
		--enable-demuxer=gif \
		--enable-demuxer=h264 \
		--enable-demuxer=hevc \
		--enable-demuxer=matroska \
		--enable-demuxer=m4v \
		--enable-demuxer=mov \
		--enable-demuxer=mp3 \
		--enable-demuxer=ogg \
		--enable-demuxer=wav \
		--enable-muxer=ogg \
		--enable-muxer=opus \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/ffmpeg-cache" install \
	&& cd .. \
	&& rm -rf ffmpeg

FROM builder AS pipewire
RUN git clone -b 0.3.25 --depth=1 https://github.com/PipeWire/pipewire.git \
	&& cd pipewire \
	&& meson build \
		--buildtype=plain \
		-Dtests=disabled \
		-Dexamples=disabled \
		-Dspa-plugins=disabled \
	&& meson compile -C build \
	&& DESTDIR="/usr/src/Libraries/pipewire-cache" meson install -C build \
	&& cd .. \
	&& rm -rf pipewire

FROM builder AS openal
COPY --link --from=pipewire /usr/src/Libraries/pipewire-cache /

RUN git clone -b 1.23.1 --depth=1 https://github.com/kcat/openal-soft.git \
	&& cd openal-soft \
	&& cmake -GNinja -B build . \
		-DCMAKE_BUILD_TYPE=None \
		-DLIBTYPE:STRING=STATIC \
		-DALSOFT_EXAMPLES=OFF \
		-DALSOFT_UTILS=OFF \
		-DALSOFT_INSTALL_CONFIG=OFF \
	&& cmake --build build --parallel \
	&& DESTDIR="/usr/src/Libraries/openal-cache" cmake --install build \
	&& cd .. \
	&& rm -rf openal-soft

FROM builder AS openssl
RUN git clone -b openssl-3.2.1 --depth=1 https://github.com/openssl/openssl.git \
	&& cd openssl \
	&& ./config \
		--openssldir=/etc/ssl \
		no-tests \
		no-dso \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/openssl-cache" install_sw \
	&& cd .. \
	&& rm -rf openssl

FROM builder AS xkbcommon
COPY --link --from=xcb /usr/src/Libraries/xcb-cache /

RUN git clone -b xkbcommon-1.6.0 --depth=1 https://github.com/xkbcommon/libxkbcommon.git \
	&& cd libxkbcommon \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Denable-docs=false \
		-Denable-wayland=false \
		-Denable-xkbregistry=false \
		-Dxkb-config-root=/usr/share/X11/xkb \
		-Dxkb-config-extra-path=/etc/xkb \
		-Dx-locale-root=/usr/share/X11/locale \
	&& meson compile -C build \
	&& DESTDIR="/usr/src/Libraries/xkbcommon-cache" meson install -C build \
	&& cd .. \
	&& rm -rf libxkbcommon

FROM builder AS glib
RUN git clone -b 2.78.1 --depth=1 https://github.com/GNOME/glib.git \
	&& cd glib \
	&& meson build \
		--buildtype=plain \
		--default-library=both \
		-Dtests=false \
		-Dmm-common:use-network=true \
	&& meson compile -C build \
	&& DESTDIR="/usr/src/Libraries/glib-cache" meson install -C build \
	&& cd .. \
	&& rm -rf glib

FROM builder AS gobject-introspection
COPY --link --from=glib /usr/src/Libraries/glib-cache /

RUN git clone -b 1.78.1 --depth=1 https://github.com/GNOME/gobject-introspection.git \
	&& cd gobject-introspection \
	&& meson build --buildtype=plain \
	&& meson compile -C build \
	&& DESTDIR="/usr/src/Libraries/gobject-introspection-cache" meson install -C build \
	&& cd .. \
	&& rm -rf gobject-introspection

FROM patches AS qt
COPY --link --from=zlib /usr/src/Libraries/zlib-cache /
COPY --link --from=lcms2 /usr/src/Libraries/lcms2-cache /
COPY --link --from=mozjpeg /usr/src/Libraries/mozjpeg-cache /
COPY --link --from=xcb /usr/src/Libraries/xcb-cache /
COPY --link --from=xcb-wm /usr/src/Libraries/xcb-wm-cache /
COPY --link --from=xcb-util /usr/src/Libraries/xcb-util-cache /
COPY --link --from=xcb-image /usr/src/Libraries/xcb-image-cache /
COPY --link --from=xcb-keysyms /usr/src/Libraries/xcb-keysyms-cache /
COPY --link --from=xcb-render-util /usr/src/Libraries/xcb-render-util-cache /
COPY --link --from=xcb-cursor /usr/src/Libraries/xcb-cursor-cache /
COPY --link --from=wayland /usr/src/Libraries/wayland-cache /
COPY --link --from=openssl /usr/src/Libraries/openssl-cache /
COPY --link --from=xkbcommon /usr/src/Libraries/xkbcommon-cache /
COPY --link --from=libwebp /usr/src/Libraries/libwebp-cache /

RUN git clone -b v6.7.0-rc2 --depth=1 https://github.com/qt/qt5.git \
	&& cd qt5 \
	&& git submodule update --init --recursive --depth=1 qtbase qtdeclarative qtwayland qtimageformats qtsvg qtshadertools \
	&& cd qtbase \
	&& find ../../patches/qtbase_6.7.0 -type f -print0 | sort -z | xargs -r0 git apply \
	&& cd ../qtwayland \
	&& find ../../patches/qtwayland_6.7.0 -type f -print0 | sort -z | xargs -r0 git apply \
	&& cd .. \
	&& ./configure \
		CMAKE_BUILD_TYPE=None \
		-opensource \
		-confirm-license \
		-qt-libpng \
		-qt-harfbuzz \
		-qt-pcre \
		-no-icu \
		INPUT_forkfd_pidfd=no \
		-no-feature-xcb-sm \
		-static \
		-dbus-runtime \
		-openssl-linked \
		-system-webp \
		-nomake examples \
		-nomake tests \
	&& cmake --build . --parallel \
	&& DESTDIR="/usr/src/Libraries/qt-cache" cmake --install . \
	&& cd .. \
	&& rm -rf qt5

FROM builder AS breakpad
RUN git clone -b v2023.06.01 --depth=1 https://chromium.googlesource.com/breakpad/breakpad.git \
	&& cd breakpad \
	&& git clone -b v2022.10.12 --depth=1 https://chromium.googlesource.com/linux-syscall-support.git src/third_party/lss \
	&& env -u CFLAGS -u CXXFLAGS ./configure \
	&& make -j$(nproc) \
	&& make DESTDIR="/usr/src/Libraries/breakpad-cache" install \
	&& cd .. \
	&& rm -rf breakpad

FROM builder AS webrtc
COPY --link --from=mozjpeg /usr/src/Libraries/mozjpeg-cache /
COPY --link --from=opus /usr/src/Libraries/opus-cache /
COPY --link --from=libvpx /usr/src/Libraries/libvpx-cache /
COPY --link --from=ffmpeg /usr/src/Libraries/ffmpeg-cache /
COPY --link --from=openssl /usr/src/Libraries/openssl-cache /
COPY --link --from=libXtst /usr/src/Libraries/libXtst-cache /
COPY --link --from=pipewire /usr/src/Libraries/pipewire-cache /

# Shallow clone on a specific commit.
RUN git init tg_owt \
	&& cd tg_owt \
	&& git remote add origin https://github.com/desktop-app/tg_owt.git \
	&& git fetch --depth=1 origin afd9d5d31798d3eacf9ed6c30601e91d0f1e4d60 \
	&& git reset --hard FETCH_HEAD \
	&& git submodule update --init --recursive --depth=1 \
	&& rm -rf .git \
	&& env -u CFLAGS -u CXXFLAGS cmake -G"Ninja Multi-Config" -B out . \
		-DCMAKE_C_FLAGS_RELEASE="$CFLAGS" \
		-DCMAKE_C_FLAGS_DEBUG="-g -pipe -fPIC -fstack-protector-all -fstack-clash-protection -fcf-protection -D_GLIBCXX_ASSERTIONS" \
		-DCMAKE_CXX_FLAGS_RELEASE="$CXXFLAGS" \
		-DCMAKE_CXX_FLAGS_DEBUG="-g -pipe -fPIC -fstack-protector-all -fstack-clash-protection -fcf-protection -D_GLIBCXX_ASSERTIONS" \
		-DTG_OWT_SPECIAL_TARGET=linux \
		-DTG_OWT_LIBJPEG_INCLUDE_PATH=/usr/local/include \
		-DTG_OWT_OPENSSL_INCLUDE_PATH=/usr/local/include \
		-DTG_OWT_OPUS_INCLUDE_PATH=/usr/local/include/opus \
		-DTG_OWT_LIBVPX_INCLUDE_PATH=/usr/local/include \
		-DTG_OWT_FFMPEG_INCLUDE_PATH=/usr/local/include

WORKDIR tg_owt

FROM webrtc AS webrtc_release
RUN cmake --build out --config Release --parallel \
	&& find out -mindepth 1 -maxdepth 1 ! -name Release -exec rm -rf {} \;

FROM webrtc AS webrtc_debug
RUN cmake --build out --config Debug --parallel \
	&& find out -mindepth 1 -maxdepth 1 ! -name Debug -exec rm -rf {} \;

FROM builder-base
COPY --link --from=zlib /usr/src/Libraries/zlib-cache /
COPY --link --from=xz /usr/src/Libraries/xz-cache /
COPY --link --from=protobuf /usr/src/Libraries/protobuf protobuf
COPY --link --from=lcms2 /usr/src/Libraries/lcms2-cache /
COPY --link --from=brotli /usr/src/Libraries/brotli-cache /
COPY --link --from=highway /usr/src/Libraries/highway-cache /
COPY --link --from=mozjpeg /usr/src/Libraries/mozjpeg-cache /
COPY --link --from=opus /usr/src/Libraries/opus-cache /
COPY --link --from=dav1d /usr/src/Libraries/dav1d-cache /
COPY --link --from=libde265 /usr/src/Libraries/libde265-cache /
COPY --link --from=libvpx /usr/src/Libraries/libvpx-cache /
COPY --link --from=libavif /usr/src/Libraries/libavif-cache /
COPY --link --from=libheif /usr/src/Libraries/libheif-cache /
COPY --link --from=libjxl /usr/src/Libraries/libjxl-cache /
COPY --link --from=rnnoise /usr/src/Libraries/rnnoise-cache /
COPY --link --from=xcb /usr/src/Libraries/xcb-cache /
COPY --link --from=xcb-wm /usr/src/Libraries/xcb-wm-cache /
COPY --link --from=xcb-util /usr/src/Libraries/xcb-util-cache /
COPY --link --from=xcb-image /usr/src/Libraries/xcb-image-cache /
COPY --link --from=xcb-keysyms /usr/src/Libraries/xcb-keysyms-cache /
COPY --link --from=xcb-render-util /usr/src/Libraries/xcb-render-util-cache /
COPY --link --from=xcb-cursor /usr/src/Libraries/xcb-cursor-cache /
COPY --link --from=libXext /usr/src/Libraries/libXext-cache /
COPY --link --from=libXfixes /usr/src/Libraries/libXfixes-cache /
COPY --link --from=libXv /usr/src/Libraries/libXv-cache /
COPY --link --from=libXtst /usr/src/Libraries/libXtst-cache /
COPY --link --from=libXrandr /usr/src/Libraries/libXrandr-cache /
COPY --link --from=libXrender /usr/src/Libraries/libXrender-cache /
COPY --link --from=libXdamage /usr/src/Libraries/libXdamage-cache /
COPY --link --from=libXcomposite /usr/src/Libraries/libXcomposite-cache /
COPY --link --from=wayland /usr/src/Libraries/wayland-cache /
COPY --link --from=ffmpeg /usr/src/Libraries/ffmpeg-cache /
COPY --link --from=openal /usr/src/Libraries/openal-cache /
COPY --link --from=openssl /usr/src/Libraries/openssl-cache /
COPY --link --from=xkbcommon /usr/src/Libraries/xkbcommon-cache /
COPY --link --from=glib /usr/src/Libraries/glib-cache /
COPY --link --from=gobject-introspection /usr/src/Libraries/gobject-introspection-cache /
COPY --link --from=qt /usr/src/Libraries/qt-cache /
COPY --link --from=breakpad /usr/src/Libraries/breakpad-cache /
COPY --link --from=webrtc /usr/src/Libraries/tg_owt tg_owt
COPY --link --from=webrtc_release /usr/src/Libraries/tg_owt/out/Release tg_owt/out/Release
COPY --link --from=libwebp /usr/src/Libraries/libwebp-cache /
COPY --link --from=webrtc_debug /usr/src/Libraries/tg_owt/out/Debug tg_owt/out/Debug

#WORKDIR ../tdesktop
ENV QT 6.7.0
ENV BOOST_INCLUDEDIR /usr/include/boost1.78
ENV BOOST_LIBRARYDIR /usr/lib64/boost1.78

#VOLUME [ "/usr/src/tdesktop" ]
ENTRYPOINT [ "scl", "enable", "gcc-toolset-12", "--" ]
#CMD [ "/usr/src/tdesktop/Telegram/build/docker/centos_env/build.sh" ]

