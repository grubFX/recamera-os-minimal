# Submodule review

Every submodule in the repo, checked for: is it a fork of something upstream, is
it a blob, how old is it, and is there a better known alternative.

**Hard requirement:** the kernel code has to trace back to real upstream Linux
source. No proprietary code dressed up as Linux. This document is the evidence
for that requirement.

## Summary

| Submodule | Type | Trust | Recommendation |
|---|---|---|---|
| `linux_5.10` | fork of upstream Linux 5.10.4 | good, see below | keep |
| `buildroot-2021.05` | fork of buildroot 2021.05 | good, 6 commits ahead | keep |
| `u-boot-2021.10` | fork of u-boot v2021.10 | good, 3 commits ahead | keep |
| `opensbi` | fork of upstream OpenSBI | good, 10 commits ahead | keep |
| `FreeRTOS-Kernel` | fork of FreeRTOS | outdated (2024) | drop, see below |
| `Lab-Project-FreeRTOS-POSIX` | fork of FreeRTOS | outdated (2024) | drop |
| `freertos` | sophgo fork | vendor port | drop with the RTOS |
| `fsbl` | sophgo, GPL-2.0 | vendor | keep |
| `osdrv` | sophgo, source | vendor, unavoidable | keep |
| `ramdisk` | sophgo, source | vendor | keep, trim |
| `build` | sophgo, source | vendor | keep |
| `cvi_rtsp` | sophgo, source | vendor | keep |
| `cvi_mpi` | sophgo, source | vendor | keep |
| `isp_tuning` | sophgo, binary tuning files | vendor | keep |
| `SensorSupportList` | sophgo, BSD-2 | vendor | keep |
| `oss` | sophgo, tarballs | mixed, see below | trim hard |
| `host-tools` | sophgo, toolchain | vendor | keep |
| `flatbuffers` | fork of google/flatbuffers | outdated (2024) | drop with the TPU stack |
| `cnpy` | sophgo, MIT | only for the TPU | drop |
| `cvibuilder` | sophgo | only for the TPU | drop |
| `cvikernel` | sophgo | only for the TPU | drop |
| `cviruntime` | sophgo | only for the TPU | drop |
| `cvimath` | sophgo | only for the TPU | drop |
| `tdl_sdk` | sophgo | only for the TPU | drop |
| `ive` | sophgo | image processing, see below | decide |

## The kernel

### Provenance

The history of `sophgo/linux_5.10` on the `sg200x-dev` branch, oldest first:

```
b1313fe517  2020-12-30  Greg Kroah-Hartman   Linux 5.10.4
b4ca5efcaf  2024-02-14  sophgo-forum-service linux porting cvitek asic chips.
72ef337123  2024-02-14  sophgo-forum-service [fea] Init sg200x-dev branch.
```

Everything below `b1313fe517` is genuine upstream Linux, authored by the usual
upstream names (Linus Torvalds, Greg Kroah-Hartman, and the rest). Above it
there are exactly **two** Sophgo commits, then weekly stable releases:

```
2d84ae4338  2026-10-28  linux_5.10: weekly rls 2026.10.28
ae7d758476  2026-08-24  linux_5.10: weekly rls 2026.08.24
767d3c5ab1  2026-06-30  linux_5.10: weekly rls 2026.06.30
eef0cf7530  2026-03-24  linux_5.10: weekly rls 2026.03.24
f6eb6441ec  2025-12-17  linux_5.10: weekly rls 2025.12.17
...
```

So the kernel is real upstream Linux, plus one porting commit, plus stable
updates on top. No hidden history, no rewritten commits.

### What the porting commit contains

`b4ca5efcaf` touches 300 files. The breakdown:

- **Added**: the CV181X device trees, the clock driver, the DMA driver, the
  pinctrl driver, the sound driver, the wifi/bt pin drivers, and the
  documentation bindings for all of them.
- **Modified**: mostly `arch/riscv/` and `arch/csky/` files.

The modifications to `arch/riscv/` were checked against upstream. They are
**backports from later kernels, not original code**. Example,
`arch/riscv/kernel/ptrace.c`:

```
$ diff upstream-v5.10/ptrace.c sophgo-porting-commit/ptrace.c
+ #ifdef CONFIG_VECTOR
+ static int riscv_vr_get(...)          <- added in upstream v5.12
+ ...
+ static const struct pt_regs_offset regoffset_table[] = { ... }
```

`riscv_vr_get` and `regoffset_table` are upstream Linux code, taken from v5.12.
The Sophgo version matches upstream v5.15 more closely than v5.10. So the
kernel tree is upstream code that was moved forward, not code that was written
for Sophgo.

### Verdict

The kernel meets the hard requirement. It is upstream Linux 5.10.4, traceable
through the git history, with the vendor additions clearly separated in one
commit.

### Why not a newer kernel

This is the real reason the kernel is 5.10 and not 6.x or 7.x, and it is not
Sophgo being lazy. The camera drivers are not in the kernel at all.

`drivers/media/platform/cvitek/` in the kernel tree contains only a `Kconfig`
file. The actual drivers live in `osdrv/interdrv/`:

```
osdrv/interdrv/cif/       MIPI receiver
osdrv/interdrv/snsr_i2c/  sensor
osdrv/interdrv/vi/        video input
osdrv/interdrv/vpss/      video processing
osdrv/interdrv/cvi_vc_drv/ encoder and decoder
osdrv/interdrv/fb/        framebuffer
osdrv/interdrv/ive/       image processing
```

They are built as out-of-tree modules against the kernel. And they are written
for 5.10. The version guards in the sources stop at 5.10:

```
$ grep -rhoP "KERNEL_VERSION\(\d+, \d+, \d+\)" osdrv/interdrv/ | sort -u
KERNEL_VERSION(2, 6, 36)
KERNEL_VERSION(4, 10, 0)
KERNEL_VERSION(4, 11, 0)
KERNEL_VERSION(4, 15, 0)
KERNEL_VERSION(5, 10, 0)
```

There is no code path for anything newer. Moving to 6.4 or later breaks the
build outright, because `class_create()` lost its module argument in 6.4:

```
$ grep -rn "class_create(" osdrv/interdrv/ | grep -v THIS_MODULE
(no result)
```

Every call is the two argument form `class_create(THIS_MODULE, name)`, which
was removed in kernel 6.4. Porting the camera drivers to a 6.4+ kernel means
going through all of `osdrv/interdrv` and fixing the API breaks.

### What the newer Sophgo kernels have

| Kernel | Version | CVI video drivers | State |
|---|---|---|---|
| `sophgo/linux_5.10` | 5.10.4 | in `osdrv`, out of tree | used today |
| `sophgo/linux` `v6.8-rc1` | 6.8-rc1, Jan 2024 | none | frozen since 2024 |
| `sophgo/linux-riscv` master | 6.18, active | none | SoC only |
| `torvalds/linux` | current | none | SoC only |

`sophgo/linux-riscv` at 6.18 has `sg2002.dtsi`, but only with the clock, plic,
clint, sdhci and pinctrl. There is no `drivers/media/platform/sophgo`, no
`drivers/clk/cvitek`, no `drivers/soc/cvitek`. Mainline has the same: the
SG2002 support is SoC level only.

So a newer kernel does not exist for this camera. The 6.8 branch in `sophgo/linux`
is frozen at January 2024 and has no CVI drivers either.

### The honest position

The kernel is as clean as it can be for this hardware: real upstream Linux,
maintained with weekly stable releases, one clearly separated vendor commit.

What is not clean is that the camera drivers are out of tree in `osdrv`, written
against a 5.10 API. Porting them into the kernel tree as proper in-tree
drivers, and then onto a current kernel, is a large project with no upstream
to merge into. Nobody else does this for this chip.

**Recommendation:** keep the 5.10 kernel. Track the weekly stable releases, they
are the security updates. Do not spend the effort on a 6.x port, the driver
work is the expensive part and there is no upstream to merge into.

## The other forks

### buildroot

```
$ gh api /repos/sophgo/buildroot-2021.05/compare/2021.05...sg200x-dev
ahead=6 behind=0
```

Six commits on top of upstream buildroot 2021.05, nothing missing. The changes
are the board config and the init scripts. There is also a `buildroot-2023.11`
branch in the same repo, but it has no CV181X support.

Buildroot 2021.05 itself is end of life upstream. The security-relevant
packages in it are the ones to watch: dropbear, busybox, openssl. All three
are in the image.

### u-boot

The fork has three own commits on top of upstream v2021.10, then the same
weekly stable releases:

```
d80bb749  2021-10-04  Prepare v2021.10
d04cdbcc  2024-02-14  [fea] Init sg200x-dev branch.
396f6210  2024-03-29  [fix]: fix build error.
daa47cff  2024-06-03  fix build error when support bootlogo.
```

The same pattern as the kernel: upstream first, small vendor delta.

### OpenSBI

```
$ gh api /repos/sophgo/opensbi/compare/v1.2...sg200x-dev
ahead=10 behind=381
```

Ten commits ahead of upstream v1.2. The 381 behind are upstream commits after
v1.2. OpenSBI is a small, well reviewed project and the delta is small enough
to audit by hand.

### FreeRTOS

`FreeRTOS-Kernel` and `Lab-Project-FreeRTOS-POSIX` are forks of the FreeRTOS
projects, last touched February 2024, and upstream has moved on
(FreeRTOS-Kernel V11.3.3, October 2026).

The RTOS runs on the second core of the SG2002. The camera does not need it.
`CONFIG_ENABLE_FREERTOS=y` in the defconfig is what pulls it in.

**Recommendation:** drop FreeRTOS from the minimal image. The defconfig has
`CONFIG_ENABLE_FREERTOS`, `CONFIG_ENABLE_RTOS_DUMP_PRINT` and
`CONFIG_DUMP_PRINT_SZ_IDX`, all three go. That removes `freertos`,
`FreeRTOS-Kernel` and `Lab-Project-FreeRTOS-POSIX` from the build.

### flatbuffers

A fork of `google/flatbuffers`, last touched July 2024. Upstream is at 25.2.
Flatbuffers is used by the TPU SDK. With the TPU stack gone, flatbuffers goes
too.

## The blobs

These are the files that are not source code. This is the part that matters
most for trust.

### live555.tar.gz: a real blob

`sophgo/oss` at `oss_release_tarball/musl_riscv64/live555.tar.gz` contains
**only compiled binaries**:

```
$ tar tzf live555.tar.gz | grep -cE '\.(c|cpp)$'
1
$ tar tzf live555.tar.gz | grep -cE '\.(a|so)$'
4
$ tar tzf live555.tar.gz | wc -l
230
```

The four static libraries are exactly what the RTSP server links against:

```
lib/libliveMedia.a
lib/libBasicUsageEnvironment.a
lib/libUsageEnvironment.a
lib/libgroupsock.a
```

and `cvi_rtsp/Makefile.inc` expects them:

```make
LIVE555_DIR ?= /system
LIVE555_LIB ?= $(LIVE555_DIR)/lib/libliveMedia.a $(LIVE555_DIR)/lib/libBasicUsageEnvironment.a \
               $(LIVE555_DIR)/lib/libUsageEnvironment.a $(LIVE555_DIR)/lib/libgroupsock.a
```

The tarball also carries `bin/live555MediaServer`, the generic RTSP server that
`cvi_rtsp` builds on.

Live555 itself is not shady. It is a well known project (LGPL-3.0, maintained
by `rgaufman/live555`, last push July 2026). And Buildroot has a package for
it with a verified hash:

```
package/live555/live555.mk:
  LIVE555_VERSION = 2025.10.13
  LIVE555_SITE = https://download.videolan.org/contrib/live555
  LIVE555_LICENSE = LGPL-3.0+
```

**Recommendation:** build live555 from source with the Buildroot package and
point `cvi_rtsp` at it. The `cvi_rtsp` build already supports this, its
`build.sh` looks for `LIVE555_DIR` first and only falls back to the download:

```sh
if [ "${LIVE555_DIR}" = "" ]; then
    # downloads prebuilt/live555.tar.gz
fi
```

So the switch is: set `LIVE555_DIR` to the Buildroot build and the blob is
never fetched. The Buildroot package installs the same four static libraries
plus `liveMediaServer`, so the `Makefile.inc` paths work unchanged.

Two details to get right in the build:

- The Buildroot package builds with `BR2_STATIC_LIBS=y` into
  `linux` config, with `linux-with-shared-libraries` otherwise. The
  `cvi_rtsp` Makefile expects static archives, so `BR2_STATIC_LIBS=y`.
- The Buildroot package installs to the sysroot, the tarball installs to
  `/system`. `LIVE555_DIR` has to point at the right place, and
  `LIVE555_INC` uses `include/BasicUsageEnvironment`, `include/groupsock`,
  `include/liveMedia` and `include/UsageEnvironment` as separate include
  directories. The Buildroot layout has them in one `include` directory, so
  `LIVE555_INC` needs adjusting.


### opencv_aisdk.tar.gz: binaries

35 MB, zero source files. Part of the AI SDK, goes with the TPU stack.

### The rest of the oss tarballs

Mostly fine. Classified by content:

| Tarball | Source files | Binary files | Note |
|---|---|---|---|
| `curl` | 12 | 2 | source |
| `openssl` | 104 | 6 | source |
| `ffmpeg` | 137 | 8 | source |
| `opencv4.5` | 215 | 21 | source, goes with the TPU stack |
| `libwebsockets` | 79 | 2 | source |
| `eigen` | 424 | 0 | source |
| `stb` | 82 | 0 | source |
| `googletest` | 148 | 0 | source |
| `json-c`, `nlohmannjson`, `glog`, `nanomsg`, `uv`, `zlib`, `miniz`, `sqlite3`, `thttpd`, `flatbuffers` | source | | fine |
| `live555` | 1 | 4 | **blob** |
| `opencv_aisdk` | 0 | 0 | **blob** |

Only live555 and opencv_aisdk are real blobs. The rest ship the source and
build it.

### The reCamera.zip

The `reCamera` buildroot package pulls a zip and copies its install tree into
the target:

```make
RECAMERA_SOURCE = reCamera.zip
RECAMERA_SITE = https://github.com/Seeed-Studio/sscma-example-sg200x/archive
```

That resolves to `.../archive/reCamera.zip`, which is a **git branch** called
`reCamera`. The branch does not exist upstream any more:

```
$ gh api /repos/Seeed-Studio/sscma-example-sg200x/branches
dev, feat/multi-model, feat/ov5647-5mp, feature/halow, feature/sensecraft-classify-dashboard,
fix/ae-feedback, main, supervisor, yolo26
```

No `reCamera`. The package is already broken, so it cannot be in any recent
upstream build either.

**Recommendation:** remove it. It carries the web UI and the device manager,
not the camera.

### The one local patch

`external/cvi_rtsp/patches/` holds a single patch, applied by `external/setenv.sh`
before the build:

```
0001-emit-H264-sprop-parameter-sets-in-SDP.patch
```

It adds the H264 SPS and PPS parameter sets to the SDP, so that a client can
decode the stream without a separate request. The patch is well written and
documented, it explains the Annex-B parsing in the comment.

This is a local patch, not upstream code. It is a good one and it is needed for
the RTSP server to work with normal players. Two options: keep it as a patch,
or send it upstream to `sophgo/cvi_rtsp`. Keeping it as a patch is fine, the
patch is in the repo and readable.

## The TPU stack

`cviruntime`, `cvikernel`, `cvimath`, `cvibuilder`, `cnpy`, `tdl_sdk` and
`flatbuffers` are the AI accelerator SDK. They exist to run the sscma models.
A camera does not need them.

`ive` is different. It is the image processing engine, it does histogram,
threshold, alpha blend and similar operations. The ISP tuning and some of the
video pipeline use it. Keep it.

## What is left after the trimming

```
linux_5.10          upstream Linux 5.10.4 + 1 vendor commit
u-boot-2021.10      upstream v2021.10 + 3 vendor commits
opensbi             upstream v1.2 + 10 vendor commits
fsbl                sophgo, GPL-2.0
buildroot-2021.05   upstream 2021.05 + 6 vendor commits
osdrv               the camera drivers, source, unavoidable
cvi_rtsp            the RTSP server, source
cvi_mpi             the MPI API, source
isp_tuning          the sensor tuning data
SensorSupportList   the sensor modules
ramdisk             the boot overlay
build               the board definitions and rootfs
host-tools          the cross toolchain
```

That is a much smaller list, and every entry on it is either upstream Linux
with a small vendor delta, or vendor source code that has no alternative
because the hardware has no other driver.

## Open questions

- Is the RTOS really not needed? The camera works on the Linux core, the
  second core runs FreeRTOS. If nothing uses it, it goes.
- live555 from Buildroot: the `cvi_rtsp` build needs `LIVE555_DIR` set, and
  the Buildroot package installs to the sysroot. Check that the include and
  library paths line up.
- Buildroot 2021.05 is end of life. Dropbear, busybox and openssl in it have
  known CVEs. Worth a look at whether the image needs openssl at all, the
  minimal image has no TLS use case.
