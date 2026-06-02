#!/bin/bash -e

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

unset CC CXX # meson wants these unset

# ATMOSphere §GS-2 (Issue C): relax mpv's dmabuf-interop-gl gate so egl-android
# satisfies it. deps/mpv is gitignored + re-cloned on clean builds, so the on-disk
# meson.build edit is lost every clean cycle — re-apply here, AFTER fetch/checkout,
# BEFORE meson setup, idempotently, via an in-place sed (robust to upstream line
# drift, unlike a context patch). cwd is buildscripts/deps/mpv.
#
# Why: on Android there is no pkg-config 'egl' (so features['egl'] is false), but
# egl-android provides the GL RA + EGL lib and the Mali driver advertises
# EGL_EXT_image_dma_buf_import(_modifiers). dmabuf_interop_gl.c only needs ra_is_gl
# + runtime EGL extensions, NOT the pkg-config egl dependency. Without this,
# hwdec_drmprime.c compiles but its interop_inits[] is empty (HAVE_DMABUF_INTEROP_GL=0)
# → "drmprime hwdec requires at least one dmabuf interop backend" → SW fallback.
mpv_gs2_pristine="features += {'dmabuf-interop-gl': features['egl'] and drm.found()}"
mpv_gs2_patched="features += {'dmabuf-interop-gl': (features['egl'] or features['egl-android']) and drm.found()}"
if grep -qF "$mpv_gs2_patched" meson.build; then
	echo "ATMOSphere §GS-2: dmabuf-interop-gl egl-android patch already applied (skipping)"
elif grep -qF "$mpv_gs2_pristine" meson.build; then
	${SED:-sed} -i "s|features += {'dmabuf-interop-gl': features\['egl'\] and drm.found()}|features += {'dmabuf-interop-gl': (features['egl'] or features['egl-android']) and drm.found()}|" meson.build
	grep -qF "$mpv_gs2_patched" meson.build \
		&& echo "ATMOSphere §GS-2: dmabuf-interop-gl egl-android patch applied" \
		|| { echo "ATMOSphere §GS-2: ERROR — sed patch did not take effect" >&2; exit 1; }
else
	echo "ATMOSphere §GS-2: WARNING — neither pristine nor patched dmabuf-interop-gl line found in meson.build; interop gate may differ from expected" >&2
fi

# ATMOSphere §GS-2: -Ddrm=enabled forces the full DRM feature (compiles hwdec_drmprime.c)
# given staged libdrm + libdisplay-info + NDK vt.h. -Degl-android=enabled keeps the GL RA.
# -Dgbm=disabled: gbm requires features['drm'] but is unused on Android (egl-android context).
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	--default-library shared \
	-Diconv=disabled -Dlua=enabled \
	-Dlibmpv=true -Dcplayer=false \
	-Dmanpage-build=disabled \
	-Ddrm=enabled -Degl-android=enabled -Dgbm=disabled

ninja -C $build -j$cores
if [ -f $build/libmpv.a ]; then
	echo >&2 "Meson fucked up, forcing rebuild."
	$0 clean
	exec $0 build
fi
DESTDIR="$prefix_dir" ninja -C $build install
