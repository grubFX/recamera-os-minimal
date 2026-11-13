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
# The cvi_mpi submodule is pinned to an older vendor release, see the note
# further down. The checkout has to happen before the tree is copied into the
# output directory.
MPI_VERSION=693a72a
if [ -e "$TOP_DIR/cvi_mpi/.git" ]; then
    MPI_CURRENT=$(git -C "$TOP_DIR/cvi_mpi" rev-parse --short HEAD)
    if [ "$MPI_CURRENT" != "$MPI_VERSION" ]; then
        echo "checking out cvi_mpi $MPI_VERSION"
        git -C "$TOP_DIR/cvi_mpi" checkout --quiet "$MPI_VERSION" || exit 1
    fi
fi

rsync_dir ./cvi_mpi
rsync_dir ./oss
rsync_dir ./$BUILDROOT_DIR
rsync_dir ./cnpy
rsync_dir ./cvibuilder
rsync_dir ./cvikernel
rsync_dir ./cvimath
rsync_dir ./cviruntime
rsync_dir ./flatbuffers
# The tdl_sdk moves files between releases. Without --delete the copies of
# files that were moved or renamed stay in the output and are compiled
# together with the new ones. That breaks the build: the old
# src/components/nn/tdl_model_factory.cpp calls BaseModel::modelOpen with a
# path, the current header takes a device id.
# The build and install directories are excluded: build/ holds the third
# party sources that CMake fetched over the network, and they are not part of
# the source tree. rsync does not delete excluded files on the receiver.
rsync -a --delete --exclude='.git' --exclude='/build/' --exclude='/install/' \
    ./tdl_sdk/ $PROJECT_OUT/tdl_sdk/
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

# The Buildroot submodule carries local-only fixes that cannot be pushed
# upstream, ship them as patches here instead. The patch is applied in the
# output, after the submodule was copied there.
# A patch that deletes a file which is already gone is not an error: the
# file was removed in an earlier run and the output still has the hole.
# patch reports that as a failure, so the exit code is checked against the
# output, not against the exit code of patch.
pushd "$PROJECT_OUT/$BUILDROOT_DIR"
for patch in "$EXTERNAL/buildroot/patches"/*.patch; do
    [ -f "$patch" ] || continue
    echo "Applying buildroot patch: $(basename "$patch")"
    patch -p1 --forward < "$patch" | sed 's/^/    /'
    if patch -p1 --forward --dry-run < "$patch" >/dev/null 2>&1; then
        continue
    fi
    # The patch did not apply cleanly. Check whether everything in it is
    # already there: a file that the patch deletes does not exist any more.
    missing=0
    while read -r deleted; do
        [ -n "$deleted" ] || continue
        if [ -e "$deleted" ]; then
            echo "Error: Failed to apply $patch, $deleted is still there"
            missing=1
        fi
    done < <(awk '
        /^diff --git/ { file = $4; sub(/^b\//, "", file); next }
        /^deleted file mode/ { print file }
    ' "$patch")
    if [ "$missing" != 0 ]; then
        echo "Error: Failed to apply $patch"
        exit 1
    fi
    echo "    (already applied)"
done
popd

rsync_dir $EXTERNAL/isp_tuning .
rsync_dir $EXTERNAL/ramdisk/ ramdisk/
rsync_dir $EXTERNAL/u-boot/ $UBOOT_DIR/

# The oss submodule ships prebuilt third party tarballs. The flatbuffers one
# is version 1.11, but the flatbuffers submodule is on 2.0.8, and the TPU
# build uses both: the submodule builds the host flatc that generates
# cvimodel_generated.h, and the oss tarball provides the library that gets
# linked into libcviruntime.so. The generated header has a static_assert on
# the flatbuffers version, so the two must match. The overlay carries the
# 2.0.8 build of the musl_riscv64 tarball and replaces the 1.11 one.
if [ -d "$EXTERNAL/oss/oss_release_tarball" ]; then
    echo "Applying the oss overlay"
    rsync -a "$EXTERNAL/oss/oss_release_tarball/" \
        "$PROJECT_OUT/oss/oss_release_tarball/"
fi

# The cvi_rtsp submodule switched from the master branch to sg200x-dev, which
# is the branch that matches the middleware of this tree. The old branch had
# files that the new one does not have, and rsync without --delete leaves
# them in the output, where they are compiled. Remove what the source tree
# does not have, so the output matches the source.
rsync -a --delete --exclude='.git' ./cvi_rtsp/ $PROJECT_OUT/cvi_rtsp/

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
    # A patch that creates a file fails on a rebuild, because the file is
    # already there and "patch --forward" skips it. Remove the files the
    # patch creates first, so the patch applies the same way every time.
    # Only "--- /dev/null" marks a file as new, a normal "--- a/..." header
    # means the file is modified and has to stay.
    awk '/^--- \/dev\/null$/{newfile=1; next} /^--- /{newfile=0} newfile && /^\+\+\+ b\//{print substr($0, 7)}' "$patch" |
    while read -r created; do
        rm -f "$created"
    done
    patch -p1 --forward < "$patch" || {
        echo "Error: Failed to apply $patch"
        exit 1
    }
done
popd

echo "All patches applied successfully."

# patch buildroot packages
# The directory in external/buildroot/package only holds the files that
# differ from the Buildroot in the submodule. The output holds the complete
# package, copied from the submodule. So the files are copied on top of it.
# A file that this tree removed from the overlay has to be removed from the
# output as well, otherwise it is still there and, in the case of a patch,
# still applied. The files that belong to the Buildroot in the submodule stay.
for subdir in $EXTERNAL/buildroot/package/*; do
    if [ -d $subdir ]; then
        pkg_name=$(basename $subdir)
        dst="$PROJECT_OUT/$BUILDROOT_DIR/package/$pkg_name/"
        src="$TOPDIR/$BUILDROOT_DIR/package/$pkg_name/"
        if [ ! -d "$dst" ]; then
            echo "WARNING: package $pkg_name is not in the Buildroot tree, skipped"
            continue
        fi
        for f in "$dst"*; do
            [ -e "$f" ] || continue
            name=$(basename "$f")
            if [ ! -e "$subdir/$name" ] && [ ! -e "$src/$name" ]; then
                echo "removing stale $pkg_name/$name"
                rm -rf "$f"
            fi
        done
        rsync -av $subdir/ $dst
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
# The vendor release 923e41a (weekly rls 2026.10.28) deleted modules/isp
# without a replacement. The ISP implementation, the ISP headers in
# modules/isp/include and the isp_bin headers that modules/bin needs are all
# gone, but the samples that are installed into the image still link against
# -lisp, -lisp_algo, -lae, -laf, -lawb, -lcvi_bin and -lcvi_bin_isp. The
# release also left the module list in modules/Makefile pointing at the
# removed directories and it lost the compile rule for the sensor sources in
# component/isp/sensor/<arch>/Makefile_full.
#
# The release before it, 693a72a (weekly rls 2026.08.24), is consistent: it
# has modules/isp with the headers and the implementation, it has no
# component/isp and it has no broken sensor rule. The submodule is therefore
# pinned to that release instead of patching five different holes in the
# newer one.
# The isp-tool-daemon of the vendor release links against libtinyalsa but does
# not put it in the link line.
ISP_DAEMON_MAKEFILE=$PROJECT_OUT/cvi_mpi/modules/isp/cv181x/isp-tool-daemon/isp_daemon_tool/Makefile
if [ -f "$ISP_DAEMON_MAKEFILE" ]; then
    echo "patching the cvi_mpi isp-tool-daemon for libtinyalsa"
    if ! grep -q 'LIBS += -ltinyalsa' "$ISP_DAEMON_MAKEFILE"; then
        sed -i '/LOCAL_CFLAGS = $(DEFS) $(INCS)/i LIBS += -ltinyalsa' "$ISP_DAEMON_MAKEFILE" || exit 1
    fi
fi

# The sensor sources in component/isp/sensor/<arch> have no compile rule.
# Without it the objects are built with the implicit rule of make, which uses
# the host compiler and no include path. The build then fails twice: the host
# compiler produces x86 objects that the riscv linker rejects, and the sensor
# sources include <linux/cvi_type.h> which is not found.
#
# The same file has a typo, the shared library depends on OBJS_PATH but the
# variable is called OBJS. OBJS_PATH is empty, so the library is linked
# before the objects exist and the link fails with "cannot find ... .o".
for CHIP_ARCH_L in cv180x cv181x cv182x sg200x; do
    MPI_SENSOR_MK=$PROJECT_OUT/cvi_mpi/component/isp/sensor/$CHIP_ARCH_L/Makefile_full
    if [ -f "$MPI_SENSOR_MK" ]; then
        echo "fixing the cvi_mpi sensor build for $CHIP_ARCH_L"
        # remove a rule from an earlier run of this script
        sed -i '/^\$(SRCS:\.c=\.o): %.o : %.c$/,+2d' "$MPI_SENSOR_MK" || exit 1
        sed -i '/^EXTRA_CFLAGS += -I\$(MW_INC) -I\$(ISP_INC) -I\$(KERNEL_INC) -I\$(SENSOR_LIST_INC)$/d' \
            "$MPI_SENSOR_MK" || exit 1
        sed -i 's|^\$(TARGET_SO): \$(OBJS_PATH)$|$(TARGET_SO): $(OBJS)|' "$MPI_SENSOR_MK" || exit 1
        cat >> "$MPI_SENSOR_MK" <<'EOF'

EXTRA_CFLAGS += -I$(MW_INC) -I$(ISP_INC) -I$(KERNEL_INC) -I$(SENSOR_LIST_INC)

$(SRCS:.c=.o): %.o : %.c
	@$(CC) $(DEPFLAGS) $(CFLAGS) $(EXTRA_CFLAGS) -c $< -o $@
	@echo [$(notdir $(CC))] $(notdir $@)
EOF
    fi
done

# override build_cvi_rtsp function
sed -i 's/function build_cvi_rtsp()/function _build_cvi_rtsp_()/g' $PROJECT_OUT/build/envsetup_soc.sh || exit 1

# source envsetup_soc.sh
TPU_REL=1
source $PROJECT_OUT/build/envsetup_soc.sh || exit 1

###################################
# overwrite envsetup_soc.sh functions
###################################
# MW_DIR points the RTSP build at the middleware of this tree. Without it the
# service looks for the headers in ../middleware/<version>, which does not
# exist, and the build stops with "cvi_type.h: No such file or directory".
# The definition has to come after the source above, otherwise the source
# overwrites it with the original function.
function build_cvi_rtsp()
{(
    cd "$CVI_RTSP_PATH" || return

    # The tdl_sdk links the RTSP service statically and expects the live555
    # archives in cvi_rtsp/prebuilt/lib (tdl_sdk/cmake/cvi_rtsp.cmake). The
    # RTSP build does not create that directory: external/build.sh exports
    # LIVE555_DIR to the TPU SDK, so cvi_rtsp/build.sh takes the "use the
    # prebuilt library" branch and never unpacks the tarball. Without the
    # links the tdl_sdk configure step fails with "Cannot find source file:
    # cvi_rtsp/prebuilt/lib/libBasicUsageEnvironment.a".
    local live_lib="$TPU_SDK_INSTALL_PATH/lib"
    if [ -f "$live_lib/libliveMedia.a" ]; then
        mkdir -p prebuilt/lib
        for lib in libliveMedia.a libBasicUsageEnvironment.a libUsageEnvironment.a libgroupsock.a; do
            ln -sf "$live_lib/$lib" "prebuilt/lib/$lib"
        done
    fi

    BUILD_SERVICE=1 MW_DIR=${MW_PATH} ./build.sh
    BUILD_SERVICE=1 MW_DIR=${MW_PATH} make install DESTDIR="$(pwd)/install" || return "$?"
    make package DESTDIR="$(pwd)/install" || return "$?"
    BUILD_SERVICE=1 MW_DIR=${MW_PATH} make install DESTDIR="${SYSTEM_OUT_DIR}/usr" || return "$?"
)}

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
