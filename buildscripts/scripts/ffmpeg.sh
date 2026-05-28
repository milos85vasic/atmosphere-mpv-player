#!/bin/bash -e

. ../../include/path.sh

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf _build$ndk_suffix
	exit 0
else
	exit 255
fi

# ATMOSphere §GS-1: apply the rkmpp configure-sentinel patch.
# deps/ffmpeg is gitignored + re-fetched (git clone) on clean builds, so the
# on-disk configure edit is lost every clean cycle. Re-apply from the TRACKED
# patch here — AFTER fetch/checkout, BEFORE configure — idempotently.
# cwd is buildscripts/deps/ffmpeg (buildall.sh `pushd deps/$1`), so ../.. is buildscripts.
ffmpeg_gs1_patch="../../patches/ffmpeg/0001-rkmpp-configure-sentinel-atmosphere-GS1.patch"
if grep -q 'mpp_create mpp_buffer_sync_begin_f' configure; then
	# pristine sentinel present -> apply
	git apply -p1 "$ffmpeg_gs1_patch"
	echo "ATMOSphere §GS-1: rkmpp configure-sentinel patch applied"
elif grep -q 'ATMOSphere §GS-1' configure; then
	echo "ATMOSphere §GS-1: rkmpp configure-sentinel patch already applied (skipping)"
else
	echo "ATMOSphere §GS-1: WARNING — neither pristine sentinel nor patch marker found in configure; rkmpp ABI check may differ from expected" >&2
fi

mkdir -p _build$ndk_suffix
cd _build$ndk_suffix

cpu=armv7-a
[[ "$ndk_triple" == "aarch64"* ]] && cpu=armv8-a
[[ "$ndk_triple" == "x86_64"* ]] && cpu=generic
[[ "$ndk_triple" == "i686"* ]] && cpu="i686 --disable-asm"

cpuflags=
[[ "$ndk_triple" == "arm"* ]] && cpuflags="$cpuflags -mfpu=neon -mcpu=cortex-a8"

args=(
	--target-os=android --enable-cross-compile
	--cross-prefix=$ndk_triple- --cc=$CC --pkg-config=pkg-config --nm=llvm-nm
	--arch=${ndk_triple%%-*} --cpu=$cpu
	--extra-cflags="-I$prefix_dir/include $cpuflags" --extra-ldflags="-L$prefix_dir/lib"

	--enable-{jni,mediacodec,mbedtls,libdav1d,libxml2} --disable-vulkan
	# ATMOSphere §GS-1: Rockchip MPP HW decode (HEVC/H.264/VP9) on RK3588 + libdrm for AV_PIX_FMT_DRM_PRIME
	--enable-rkmpp --enable-libdrm
	--disable-static --enable-shared --enable-{gpl,version3}

	# disable unneeded parts
	--disable-{stripping,doc,programs}
	# to keep the build lean we disable some feature quite aggressively:
	# - muxers, encoders: mpv-android does not have any way to use these
	# - devices: no practical use on Android
	--disable-{muxers,encoders,devices}
	# useful to taking screenshots
	--enable-encoder=mjpeg,png
	# useful for the `dump-cache` command
	--enable-muxer=mov,matroska,mpegts
)
../configure "${args[@]}"

make -j$cores
make DESTDIR="$prefix_dir" install
