#!/bin/bash -e

# ATMOSphere §GS-2 (Issue C): libdisplay-info — required by mpv's full DRM feature
# (features['drm'] in meson.build gates hwdec_drmprime.c on libdrm + libdisplay-info
# + vt.h). drm_common.c #includes <libdisplay-info/{cta,edid,info}.h>. Pure C11,
# only -lm; builds a build-time pnp.ids search table via tool/gen-search-table.py.
# meson cross-build for Android, installed into the prefix.
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

# ATMOSphere §GS-2: libdisplay-info uses open_memstream() (memory-stream.c), which
# bionic only exposes from API 23 (__INTRODUCED_IN(23)). The rest of the build
# targets API 21, but this is a leaf C library — building it at API 23 is safe
# because the device runs Android 15 (API 35) and open_memstream resolves at
# runtime (the already-staged AOSP libdrm.so likewise imports open_memstream@LIBC).
# Build a dedicated API-23 cross-file from the prefix crossfile, swapping the
# compiler triple's API suffix 21 -> 23.
api23_cross="$prefix_dir/crossfile-api23-ldi.txt"
${SED:-sed} -E "s/(android)21(-clang)/\\123\\2/g" "$prefix_dir/crossfile.txt" > "$api23_cross"
# crossfile.txt references $CC ($cc_triple-clang). cc_triple ends in api level for
# arm64/x86/x86_64 (aarch64-linux-android21) but NOT armv7 (armv7a-linux-androideabi21).
${SED:-sed} -E "s/(androideabi)21(-clang)/\\123\\2/g" "$api23_cross" > "$api23_cross.tmp" && mv "$api23_cross.tmp" "$api23_cross"

unset CC CXX # meson wants these unset

# pnp.ids: libdisplay-info auto-detects hwdata (native) or falls back to
# /usr/share/hwdata/pnp.ids. The gen-search-table.py runs on the BUILD host
# (native), so the host hwdata is correct here. libdisplay-info 0.3.0 has no
# build options for tests; it unconditionally `subdir('di-edid-decode')` +
# `subdir('test')`. We build + install ONLY the shared library target so the
# cross-build never trips on tool/test harness executables, then install the
# library + headers + pkg-config manually — all mpv's features['drm'] needs.
meson setup $build --cross-file "$api23_cross" \
	--default-library shared

ninja -C $build -j$cores libdisplay-info.so
# Install the library, headers and pkg-config file explicitly (avoid building the
# di-edid-decode/test executables that `ninja install` would otherwise pull in).
install -D -m644 "$build/libdisplay-info.so" "$prefix_dir/lib/libdisplay-info.so"
mkdir -p "$prefix_dir/include/libdisplay-info"
install -m644 include/libdisplay-info/*.h "$prefix_dir/include/libdisplay-info/"
mkdir -p "$prefix_dir/lib/pkgconfig"
if [ -f "$build/meson-private/libdisplay-info.pc" ]; then
	install -m644 "$build/meson-private/libdisplay-info.pc" "$prefix_dir/lib/pkgconfig/libdisplay-info.pc"
else
	# synthesize a minimal pkg-config so mpv's dependency('libdisplay-info') resolves
	v_ver=$(${SED:-sed} -nE "s/.*version: '([0-9.]+)'.*/\\1/p" meson.build | head -1)
	cat > "$prefix_dir/lib/pkgconfig/libdisplay-info.pc" <<PC
prefix=/usr/local
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: libdisplay-info
Description: EDID and DisplayID library (ATMOSphere §GS-2 Android stage)
Version: ${v_ver:-0.3.0}
Libs: -L\${libdir} -ldisplay-info
Cflags: -I\${includedir}
PC
fi
