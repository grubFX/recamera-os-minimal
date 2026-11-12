#!/bin/bash

# The vendor releases turn directories into symlinks (fsbl/plat/cv180x/prebuilt,
# osdrv/interdrv/*/chip/cv180x, ramdisk/rootfs/public/*, linux/scripts/dtc/...).
# rsync -a cannot replace an existing directory with a symlink and aborts with
# "could not make way for new symlink". Removing the offending directories first
# lets rsync create the symlinks. This only touches paths that are a symlink in
# the source tree, so build artefacts in the output are left alone.
function rsync_clear_symlink_conflicts()
{
    local src=$1
    local dst=$2
    local rel target

    [ -d "$src" ] || return 0

    while IFS= read -r rel; do
        target="$dst/${rel#./}"
        # only a real directory in the destination blocks the symlink
        if [ -d "$target" ] && [ ! -L "$target" ]; then
            rm -rf "$target"
        fi
    done < <(cd "$src" && find . -type l 2>/dev/null)
}

# The SensorSupportList submodule ships sensor/cv180x, sensor/cv181x and
# sensor/sg200x as symlinks to sensor/cv182x, and the ISP Makefile does
# "pushd sensor/$(chip_arch)" with chip_arch=cv181x. The sensor Makefiles
# resolve their own paths relative to the current directory ("PARAM_FILE=
# ../../../../../mpi_param.mk"), and a symlink puts the working directory one
# level deeper than the relative path expects. The result is an empty include
# path and "fatal error: linux/cvi_type.h: No such file or directory".
# Materialising the symlink as a real directory keeps the paths working.
function materialize_sensor_symlinks()
{
    local dst=$1
    local rel target link

    [ -d "$dst/sensor" ] || return 0

    for rel in cv180x cv181x sg200x; do
        target="$dst/sensor/$rel"
        [ -L "$target" ] || continue
        link=$(readlink "$target")
        rm -f "$target"
        cp -a "$dst/sensor/$link" "$target"
    done
}

function rsync_dir()
{
    if [ ! -d $1 ]; then
        echo "$1 not exist"
        return
    fi
    mkdir -p $PROJECT_OUT/$2

    # A trailing slash on the source means "copy the contents", without it
    # rsync creates <dest>/<basename of src>. The conflict cleanup has to
    # look at the same place rsync writes to.
    local base dst
    base=$(basename "${1%/}")
    if [ -n "${2%/}" ]; then
        dst="$PROJECT_OUT/${2%/}"
    else
        dst="$PROJECT_OUT"
    fi
    case "$1" in
        */) ;;                       # contents go directly into dst
        *)  dst="$dst/$base" ;;
    esac
    rsync_clear_symlink_conflicts "$1" "$dst"

    echo "rsync $1 -> $PROJECT_OUT/$2"; rsync -a --exclude='.git' $1 $PROJECT_OUT/$2 || exit 1
}

###################################
# rsync codes
###################################
mkdir -p $PROJECT_OUT
rsync_dir ./build
rsync_dir ./freertos
rsync_dir ./FreeRTOS-Kernel/ freertos/Source/
rsync_dir ./Lab-Project-FreeRTOS-POSIX/ freertos/Source/FreeRTOS-Plus-POSIX/
rsync_dir ./fsbl
rsync_dir ./opensbi
rsync_dir ./$UBOOT_DIR
rsync_dir ./$LINUX_DIR
rsync_dir ./ramdisk
rsync_dir ./osdrv
rsync_dir ./cvi_mpi
rsync_dir ./oss
rsync_dir ./$BUILDROOT_DIR
rsync_dir ./cnpy
rsync_dir ./cvibuilder
rsync_dir ./cvikernel
rsync_dir ./cvimath
rsync_dir ./cviruntime
rsync_dir ./flatbuffers
rsync_dir ./tdl_sdk
rsync_dir ./cvi_rtsp

###################################
# patch externals
###################################
rsync_dir $EXTERNAL/build .
# The build submodule carries local-only fixes that cannot be pushed upstream,
# ship them as patches here instead
pushd $PROJECT_OUT/build
for patch in "$EXTERNAL/build/patches"/*.patch; do
    [ -f "$patch" ] || continue
    echo "Applying build patch: $(basename "$patch")"
    patch -p1 --forward < "$patch" || {
        echo "Error: Failed to apply $patch"
        exit 1
    }
done
popd
rsync_dir $EXTERNAL/buildroot/ $BUILDROOT_DIR/
rsync_dir $EXTERNAL/isp_tuning .
rsync_dir $EXTERNAL/ramdisk/ ramdisk/
rsync_dir $EXTERNAL/u-boot/ $UBOOT_DIR/

# The sensor overlay in $EXTERNAL/SensorSupportList adds the ov5647 driver
# (5MP mode) and replaces sensor.mk. It has to be copied BEFORE the
# SensorSupportList submodule: the submodule ships sensor/cv180x, sensor/cv181x
# and sensor/sg200x as symlinks to sensor/cv182x, and the ISP Makefile does
# "pushd sensor/$(chip_arch)" with chip_arch=cv181x. An overlay copied on top
# turns that symlink into a real directory without a Makefile, and the build
# stops with "No rule to make target 'all'". Copied first, the submodule
# overwrites the directory with the symlink and the overlay's driver ends up in
# sensor/cv182x/ov_ov5647, which is what sensor.mk refers to.
rsync_clear_symlink_conflicts "$EXTERNAL/SensorSupportList" "$PROJECT_OUT/cvi_mpi/component/isp"
rsync -av $EXTERNAL/SensorSupportList/ $PROJECT_OUT/cvi_mpi/component/isp/

# after the overlay: the submodule wins for the symlinked chip directories
rsync_dir ./SensorSupportList/ cvi_mpi/component/isp
materialize_sensor_symlinks "$PROJECT_OUT/cvi_mpi/component/isp"

# patch linux kernel
# Apply all patches from the external patches directory
pushd $PROJECT_OUT/$LINUX_DIR
for patch in "$EXTERNAL/linux/patches"/*.patch "$EXTERNAL/linux/patches"/*.diff; do
    # Skip if no patch files match
    [ -f "$patch" ] || continue

    echo "Applying patch: $(basename "$patch")"
    # Apply patch with -p1, reading from stdin. --forward skips a patch that
    # is already applied, so a rebuild over a patched tree does not stop.
    patch -p1 --forward < "$patch" || {
        echo "Error: Failed to apply $patch"
        exit 1
    }
done
popd

# patch cvi_rtsp (submodule carries local-only commits that cannot be
# pushed upstream; ship fixes as patches here instead)
pushd $PROJECT_OUT/cvi_rtsp
for patch in "$EXTERNAL/cvi_rtsp/patches"/*.patch; do
    # Skip if no patch files match
    [ -f "$patch" ] || continue

    echo "Applying cvi_rtsp patch: $(basename "$patch")"
    patch -p1 --forward < "$patch" || {
        echo "Error: Failed to apply $patch"
        exit 1
    }
done
popd

echo "All patches applied successfully."

# patch buildroot packages
for subdir in $EXTERNAL/buildroot/package/*; do
    if [ -d $subdir ]; then
        pkg_name=$(basename $subdir)
        if [ -f $subdir/Config.in ]; then
            rsync -av --delete $subdir/ $PROJECT_OUT/$BUILDROOT_DIR/package/$pkg_name/
        else
            rsync -av $subdir/ $PROJECT_OUT/$BUILDROOT_DIR/package/$pkg_name/
        fi
    fi
done

ln -sf $TOPDIR/host-tools $PROJECT_OUT/

if [ ! -e "$PROJECT_OUT/cvi_rtsp/.git" ]; then
ln -s ../../../.git/modules/cvi_rtsp/ $PROJECT_OUT/cvi_rtsp/.git
ls -l $PROJECT_OUT/cvi_rtsp/.git
fi

if [ ! -e "$PROJECT_OUT/cvi_mpi/.git" ]; then
ln -s ../../../.git/modules/cvi_mpi/ $PROJECT_OUT/cvi_mpi/.git
ls -l $PROJECT_OUT/cvi_mpi/.git
fi

###################################
# modify build/Makefile
###################################
sed -i 's/${Q}$(MAKE) -C $(BR_DIR).*/${Q}$(MAKE) -C $(BR_DIR) $(BR_DEFCONFIG) BR2_TOOLCHAIN_EXTERNAL_PATH=$(CROSS_COMPILE_PATH) O=$(TARGET_OUTPUT_DIR)/' \
    $PROJECT_OUT/build/Makefile || exit 1
sed -i 's/${Q}$(MAKE) -j${NPROC} -C $(BR_DIR).*/${Q}$(MAKE) -j${NPROC} -C $(BR_DIR) O=$(TARGET_OUTPUT_DIR)/' \
    $PROJECT_OUT/build/Makefile || exit 1

sed -i '/EXTRA_LDFLAGS = $(LIBS).*/aEXTRA_LDFLAGS += -latomic' \
    $PROJECT_OUT/cvi_mpi/sample/venc/Makefile || exit 1

###################################
# modify envsetup_soc.sh
###################################
sed -i 's/^TOP_DIR=$(.*)/TOP_DIR=$PROJECT_OUT/' $PROJECT_OUT/build/envsetup_soc.sh || exit 1
echo "INFO: Change TOP_DIR to \"$PROJECT_OUT in envsetup_soc.sh"\"

sed -i 's/CVI_TARGET_PACKAGES_LIBDIR=.*/CVI_TARGET_PACKAGES_LIBDIR=$(make --no-print-directory print-target-packages-libdir)/' \
    $PROJECT_OUT/build/envsetup_soc.sh || exit 1
sed -i 's/CVI_TARGET_PACKAGES_INCLUDE=.*/CVI_TARGET_PACKAGES_INCLUDE=$(make --no-print-directory print-target-packages-include)/' \
    $PROJECT_OUT/build/envsetup_soc.sh || exit 1
echo "INFO: Fixed CVI_TARGET_PACKAGES_LIBDIR & CVI_TARGET_PACKAGES_INCLUDE in envsetup_soc.sh"\"

# overide build_middleware function
sed -i 's/function build_middleware()/function _build_middleware_()/g' $PROJECT_OUT/build/envsetup_soc.sh || exit 1
sed -i 's/function pack_cfg/function _pack_cfg_/g' $PROJECT_OUT/build/common_functions.sh || exit 1
sed -i 's/function pack_rootfs/function _pack_rootfs_/g' $PROJECT_OUT/build/common_functions.sh || exit 1


# build flatbuffers
sed -i 's/cmake -G Ninja -DCMAKE_INSTALL_PREFIX=$FLATBUFFERS_HOST_PATH/cmake -G Ninja -DFLATBUFFERS_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX=$FLATBUFFERS_HOST_PATH/g' \
    $PROJECT_OUT/cviruntime/build_tpu_sdk.sh || exit 1

# patch cvi_mpi
sed -i '/LOCAL_CFLAGS = $(DEFS) $(INCS)/i LIBS += -ltinyalsa' $PROJECT_OUT/cvi_mpi/modules/isp/cv181x/isp-tool-daemon/isp_daemon_tool/Makefile || exit 1

# override build_cvi_rtsp function
sed -i 's/function build_cvi_rtsp()/function _build_cvi_rtsp_()/g' $PROJECT_OUT/build/envsetup_soc.sh || exit 1
# MW_VER selects the middleware API generation: the service uses it in
# "#if (MW_VER == 2)" and "#if MW_VER == 1". Without it the preprocessor gets
# "-DMW_VER=" and the comparison becomes a syntax error. The middleware in
# this tree is generation 1: it has no pkgconfig directory and does not
# define _MIDDLEWARE_V2_, and the v1 code path uses CVI_BIN_SetBinName and
# CVI_VI_SetDevNum, which the headers do provide.
function build_cvi_rtsp()
{(
    cd "$CVI_RTSP_PATH" || return
    BUILD_SERVICE=1 MW_DIR=${MW_PATH} MW_VER=1 ./build.sh
    BUILD_SERVICE=1 MW_VER=1 make install DESTDIR="$(pwd)/install" || return "$?"
    make package DESTDIR="$(pwd)/install" || return "$?"
    BUILD_SERVICE=1 MW_VER=1 make install DESTDIR="${SYSTEM_OUT_DIR}/usr" || return "$?"
)}

# source envsetup_soc.sh
TPU_REL=1
source $PROJECT_OUT/build/envsetup_soc.sh || exit 1

###################################
# overwrite envsetup_soc.sh functions
###################################
function build_middleware()
{(
    print_notice "Run ${FUNCNAME[0]}() overided by $0"

    _build_middleware_ || return $?

    pushd "$MW_PATH"
    cp -fv sample/audio/sample_audio*  ${SYSTEM_OUT_DIR}/usr/bin
    popd

    # ramdisk/rootfs/public/pinmux/musl_riscv64/usr/sbin/cvi_pinmux
    cp -fv ${RAMDISK_PATH}/rootfs/public/pinmux/${SDK_VER}/usr/sbin/cvi_pinmux ${SYSTEM_OUT_DIR}/usr/bin
)}

function pack_cfg
{(
    print_notice "Run ${FUNCNAME[0]}() overided by $0"

    # isp parameter
    cp -v $TOPDIR/isp_tuning/copyBin.sh $ISP_TUNING_PATH
    
    SRC_DIR=${CHIP_ARCH,,}/src
    DST_DIR="$OUTPUT_DIR/rootfs/mnt/cfg/param"

    mkdir -p $DST_DIR

    pushd $ISP_TUNING_PATH
    find "$SRC_DIR" -type f -name "*.bin" -exec cp {} "$DST_DIR" \;
    popd

    mkdir -p $BR_OVERLAY_DIR/mnt
    cp -arf $OUTPUT_DIR/rootfs/mnt/cfg $BR_OVERLAY_DIR/mnt/
)}

function gen_boot_zip()
{
    echo "Run ${FUNCNAME[0]}"

    local targets="fip.bin boot.emmc"

    pushd $OUTPUT_DIR/rawimages
    rm -rfv ../*rawimages.zip
    cp -fv ../fip.bin . || exit 1
    md5sum $targets > md5sum.txt
    zip -j rawimages.zip $targets md5sum.txt || exit 1
    rm -rf fip.bin
    mv -fv rawimages.zip ../${1}.zip
    popd

    echo "${FUNCNAME[0]} ok"
}

function pack_rootfs
{(
    print_notice "Run ${FUNCNAME[0]}() overided by $0"

    gen_boot_zip boot_ota || exit 1
    mkdir -p $SYSTEM_OUT_DIR/resources/
    mv $OUTPUT_DIR/boot_ota.zip $SYSTEM_OUT_DIR/resources/

    _pack_rootfs_ || return $?
)}
