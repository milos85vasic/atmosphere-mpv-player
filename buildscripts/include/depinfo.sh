#!/bin/bash -e

## Dependency versions
# Make sure to keep v_ndk and v_ndk_n in sync, both are listed on the NDK download page

v_sdk=11076708_latest
v_ndk=r29
v_ndk_n=29.0.14206865
v_sdk_platform=35
v_sdk_build_tools=35.0.0

v_lua=5.2.4
v_unibreak=6.1
v_harfbuzz=13.0.1
v_fribidi=1.0.16
v_freetype=2.14.2
v_mbedtls=3.6.5
v_libxml2=2.15.2
v_fontconfig=2.17.1

# ATMOSphere §GS-2 (Issue C): drm_prime → GL dmabuf interop deps for mpv hwdec_drmprime
v_libdrm=2.4.114
v_libdisplay_info=0.3.0


## Dependency tree

dep_mbedtls=()
dep_dav1d=()
dep_libxml2=()
dep_ffmpeg=(mbedtls dav1d libxml2)
dep_freetype2=()
dep_fontconfig=(libxml2 freetype2)
dep_fribidi=()
dep_harfbuzz=()
dep_unibreak=()
dep_libass=(freetype2 fontconfig fribidi harfbuzz unibreak)
dep_lua=()
dep_libplacebo=()
# ATMOSphere §GS-2 (Issue C): libdrm + libdisplay-info enable mpv's full DRM feature
# (features['drm'] gates hwdec_drmprime.c) + dmabuf-interop-gl, so the rkmpp drm_prime
# 10-bit surface reaches the GL/libplacebo VO instead of force-falling to pure SW.
dep_libdrm=()
dep_libdisplay_info=()
dep_mpv=(ffmpeg libass lua libplacebo libdrm libdisplay-info)
dep_mpv_android=(mpv)


## for CI workflow

# pinned ffmpeg revision
v_ci_ffmpeg=n8.0.1

# filename used to uniquely identify a build prefix
ci_tarball="prefix-ndk-${v_ndk}-lua-${v_lua}-unibreak-${v_unibreak}-harfbuzz-${v_harfbuzz}-fribidi-${v_fribidi}-freetype-${v_freetype}-libxml2-${v_libxml2}-fontconfig-${v_fontconfig}-mbedtls-${v_mbedtls}-ffmpeg-${v_ci_ffmpeg}.tgz"
