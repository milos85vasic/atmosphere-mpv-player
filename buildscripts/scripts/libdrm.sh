#!/bin/bash -e

# ATMOSphere §GS-2 (Issue C): libdrm — provides xf86drm.h + drm_fourcc.h + libdrm.so
# required by mpv's hwdec_drmprime (drm_prime path) and FFmpeg's --enable-libdrm
# (AV_PIX_FMT_DRM_PRIME). meson cross-build for Android, installed into the prefix.
. ../../include/path.sh

build=_build$ndk_suffix

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf $build
	exit 0
else
	exit 255
fi

# ATMOSphere §GS-2: upstream libdrm's xf86drm.c uses open_memstream() (the
# AMD modifier-name helper), which bionic only exposes from API 23
# (__INTRODUCED_IN(23)). Build this leaf C library at API 23 — safe because the
# device runs Android 15 (API 35) and open_memstream resolves at runtime
# (the AOSP libdrm.so likewise imports open_memstream@LIBC). Build a dedicated
# API-23 cross-file by swapping the compiler triple's API suffix 21 -> 23.
api23_cross="$prefix_dir/crossfile-api23-libdrm.txt"
${SED:-sed} -E "s/(android)21(-clang)/\\123\\2/g; s/(androideabi)21(-clang)/\\123\\2/g" \
	"$prefix_dir/crossfile.txt" > "$api23_cross"

unset CC CXX # meson wants these unset

# libdrm only needs the core userspace lib for DRM_PRIME / GEM ioctls on Android.
# Disable all KMS test/demo tools and the vendor-specific drivers we don't use.
meson setup $build --cross-file "$api23_cross" \
	--default-library shared \
	-Dintel=disabled -Dradeon=disabled -Damdgpu=disabled \
	-Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled \
	-Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled \
	-Dvc4=disabled -Detnaviv=disabled \
	-Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled \
	-Dtests=false -Dinstall-test-programs=false \
	-Dudev=false

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install
