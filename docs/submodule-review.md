# Submodule review

Every submodule in the repo, checked for: is it a fork of something upstream, is it a blob, how old is it, and is there a better known alternative. **Hard requirement:** the kernel code has to trace back to real upstream Linux source. No proprietary code dressed up as Linux. This document is the evidence for that requirement.

## Summary

The build of the target touches eight of the 27 submodules. The table says
for each one whether it is used, and if it can be replaced by upstream.

| Submodule | Type | Trust | Recommendation |
|---|---|---|---|
| `linux_5.10` | fork of upstream Linux 5.10.4 | good, see below | keep, used |
| `buildroot-2021.05` | fork of buildroot 2021.05 | good, 6 commits ahead | keep, used |
| `u-boot-2021.10` | fork of u-boot v2021.10 | good, 3 commits ahead | keep, used |
| `opensbi` | fork of upstream OpenSBI | good, 10 commits ahead | keep, used |
| `FreeRTOS-Kernel` | fork of FreeRTOS | outdated (2024) | drop, see below |
| `Lab-Project-FreeRTOS-POSIX` | fork of FreeRTOS | outdated (2024) | drop |
| `freertos` | sophgo fork | vendor port | drop with the RTOS |
| `fsbl` | sophgo, GPL-2.0 | vendor | keep, used |
| `osdrv` | sophgo, source | vendor, unavoidable | keep, used |
| `ramdisk` | sophgo, source | vendor | keep, trim |
| `build` | sophgo, source | vendor | keep, used |
| `cvi_rtsp` | sophgo, source | vendor | keep, used |
| `cvi_mpi` | sophgo, source | vendor | keep, used |
| `isp_tuning` | sophgo, binary tuning files | vendor | keep |
| `SensorSupportList` | sophgo, BSD-2 | vendor | keep |
| `oss` | sophgo, tarballs | mixed, see below | trim hard |
| `host-tools` | sophgo, toolchain | vendor | keep |
| `flatbuffers` | fork of google/flatbuffers | identical to upstream v2.0.8 | drop with the TPU stack |
| `cnpy` | sophgo, MIT | only for the TPU | drop |
| `cvibuilder` | sophgo | only for the TPU | drop |
| `cvikernel` | sophgo | only for the TPU | drop |
| `cviruntime` | sophgo | builds the TPU SDK | drop with the TPU stack |
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

Everything below `b1313fe517` is genuine upstream Linux, authored by the usual upstream names (Linus Torvalds, Greg Kroah-Hartman, and the rest). Above it there are exactly **three** Sophgo commits:

```
b4ca5efcaf  2024-02-14  linux porting cvitek asic chips.
72ef337123  2024-02-14  [fea] Init sg200x-dev branch.
25faa0d62f  2024-03-29  [fix] fix linux build error..
```

and then 28 weekly stable releases:

```
2d84ae4338  2026-10-28  linux_5.10: weekly rls 2026.10.28
ae7d758476  2026-08-24  linux_5.10: weekly rls 2026.08.24
767d3c5ab1  2026-06-30  linux_5.10: weekly rls 2026.06.30
eef0cf7530  2026-03-24  linux_5.10: weekly rls 2026.03.24
f6eb6441ec  2025-12-17  linux_5.10: weekly rls 2025.12.17
...
```

So the kernel is real upstream Linux, plus three vendor commits, plus stable updates on top. No hidden history, no rewritten commits.

### What the porting commit contains

`b4ca5efcaf` touches 300 files. The breakdown:

- **Added**: the CV181X device trees, the clock driver, the DMA driver, the
pinctrl driver, the sound driver, the wifi/bt pin drivers, and the documentation bindings for all of them.
- **Modified**: mostly `arch/riscv/` and `arch/csky/` files.

The modifications to `arch/riscv/` were checked against upstream. They are **backports from later kernels, not original code**. Example, `arch/riscv/kernel/ptrace.c`:

```
$ diff upstream-v5.10/ptrace.c sophgo-porting-commit/ptrace.c
+ #ifdef CONFIG_VECTOR
+ static int riscv_vr_get(...)          <- added in upstream v5.12
+ ...
+ static const struct pt_regs_offset regoffset_table[] = { ... }
```

`riscv_vr_get` and `regoffset_table` are upstream Linux code, taken from v5.12. The Sophgo version matches upstream v5.15 more closely than v5.10. So the kernel tree is upstream code that was moved forward, not code that was written for Sophgo.

### Verdict

The kernel meets the hard requirement. It is upstream Linux 5.10.4, traceable through the git history, with the vendor additions clearly separated in one commit. It is also not abandoned. Upstream Linux 5.10 is a longterm release and still gets fixes, the Sophgo fork mirrors that with the weekly stable releases. The last upstream commit was `3a323bc2` "Linux 5.10.274" on 2026-11-06, the last fork commit `2d84ae4338` on 2026-10-28. **The kernel is behind, not unmaintained.** What a newer kernel would cost is in [kernel-upgrade.md](./kernel-upgrade.md).

### Why not a newer kernel

This is the real reason the kernel is 5.10 and not 6.x or 7.x, and it is not Sophgo being lazy. The camera drivers are not in the kernel at all. `drivers/media/platform/cvitek/` in the kernel tree contains only a `Kconfig` file. The actual drivers live in `osdrv/interdrv/`:

```
osdrv/interdrv/cif/       MIPI receiver
osdrv/interdrv/snsr_i2c/  sensor
osdrv/interdrv/vi/        video input
osdrv/interdrv/vpss/      video processing
osdrv/interdrv/cvi_vc_drv/ encoder and decoder
osdrv/interdrv/fb/        framebuffer
osdrv/interdrv/ive/       image processing
```

They are built as out-of-tree modules against the kernel. And they are written for 5.10. The version guards in the sources stop at 5.10:

```
$ grep -rhoP "KERNEL_VERSION\(\d+, \d+, \d+\)" osdrv/interdrv/ | sort -u
KERNEL_VERSION(2, 6, 36)
KERNEL_VERSION(4, 10, 0)
KERNEL_VERSION(4, 11, 0)
KERNEL_VERSION(4, 15, 0)
KERNEL_VERSION(5, 10, 0)
```

There is no code path for anything newer. Moving to 6.4 or later breaks the build outright, because `class_create()` lost its module argument in 6.4:

```
$ grep -rn "class_create(" osdrv/interdrv/ | grep -v THIS_MODULE
(no result)
```

Every call is the two argument form `class_create(THIS_MODULE, name)`, which was removed in kernel 6.4. Porting the camera drivers to a 6.4+ kernel means going through all of `osdrv/interdrv` and fixing the API breaks. Two more version facts, so the list is complete:

- **`set_fs()`** is an architecture implementation on RISC-V in
`arch/riscv/include/asm/uaccess.h`. It is gone from 6.1 on. There are 174 call sites in `osdrv`, but 173 of them are in old WiFi driver trees for chips the camera does not have. One is in the camera path.
- **`clk_hw_register_clkdev()`** is *not* removed. It is still declared in
`include/linux/clkdev.h` with an unchanged signature, all the way up to v7.3. The CVI clock driver uses it, the modernized 6.18 driver uses `devm_clk_hw_register` instead. That is a cleanup, not a port. The full breakdown with the numbers is in [kernel-upgrade.md](./kernel-upgrade.md).

### What the newer Sophgo kernels have

| Kernel | Version | CVI video drivers | State |
|---|---|---|---|
| `sophgo/linux_5.10` | 5.10.4 | in `osdrv`, out of tree | used today |
| `sophgo/linux` `v6.8-rc1` | 6.8-rc1, Jan 2024 | none | frozen since 2024 |
| `sophgo/linux-riscv` master | 6.18, active | none | SoC only |
| `torvalds/linux` | 7.4-rc2, active | none | SoC only |

`sophgo/linux-riscv` at 6.18 has `sg2002.dtsi`, but only with the clock, plic, clint, sdhci and pinctrl. There is no `drivers/media/platform/sophgo`, no `drivers/clk/cvitek`, no `drivers/soc/cvitek`. Mainline has the same: the SG2002 support is SoC level only. So a newer kernel does not exist for this camera. The 6.8 branch in `sophgo/linux` is frozen at January 2024 and has no CVI drivers either. The SoC part is in good shape though. Mainline has the modernized clock driver `drivers/clk/sophgo/clk-cv1800.c`, the pinctrl, the sound codec drivers, the SDHCI host and the mailbox binding. The DesignWare DMA controller of the CV181X is also upstream, as `drivers/dma/dw/`. What is missing is only the video pipeline, and that lives in `osdrv`. The details are in [kernel-upgrade.md](./kernel-upgrade.md).

### The honest position

The kernel is as clean as it can be for this hardware: real upstream Linux, maintained with weekly stable releases, one clearly separated vendor commit. What is not clean is that the camera drivers are out of tree in `osdrv`, written against a 5.10 API. Porting them into the kernel tree as proper in-tree drivers, and then onto a current kernel, is a large project with no upstream to merge into. Nobody else does this for this chip. **Recommendation:** keep the 5.10 kernel. Track the weekly stable releases, they are the security updates. Do not spend the effort on a 6.x port, the driver work is the expensive part and there is no upstream to merge into. The details are in [kernel-upgrade.md](./kernel-upgrade.md).

## The other forks

### buildroot

```
$ gh api /repos/sophgo/buildroot-2021.05/compare/2021.05...sg200x-dev
ahead=6 behind=0
```

Six commits on top of upstream buildroot 2021.05, nothing missing. The changes are the board config and the init scripts:

```
8d456c1c  2024-01-30  [buildroot] Supports generating CV181X CV182X ext4 file system.
c15bdd8f  2024-01-30  [buildroot] Fix some runtime errors
ab7661e7  2024-01-30  buildroot: weekly update 2023-04-26
50b37637  2024-01-30  buildroot: weekly-rls-2023-12-22
5b7acd1b  2019-10-09  (master): Support Xuantie toolchains, and modify the defconfigs.
4e338c31  2025-12-25  (buildroot): add link options for musl toochain
```

Three of them are stable updates for a newer release line, one is the toolchain support that predates the 2021.05 tag. Two of them touch external packages and are worth a look:

- `package/freetype/0001-fix-TOP_DIR-value-error-for-CVITEK-platform.patch`
- `package/zlog/0001-mod-if-DEBUG-equal-0-then-enable-debug-info-output.patch`

Neither package is needed in a camera image. `freetype` is a font library, only useful with a text renderer. `zlog` is a logging library from the Sophgo SDK. Both patches can go with the packages. `package/busybox/busybox.config` is the busybox configuration. It is worth reading, it is the config that defines what the shell and the applets in the image can do. The init scripts in `board/cvitek/CV181X/overlay/etc/init.d/` are the ones that start the services. `S99user` is the interesting one, it sources `/mnt/system/auto.sh` which starts the vendor application. **Buildroot 2021.05 is end of life.** The upstream branch got its last commit in June 2021 and no security fixes since. That matters, because the image carries dropbear, busybox and openssl from it. There is a `buildroot-2023.11` branch in the same Sophgo repo, but it has no CV181X support:

```
$ gh api /repos/sophgo/buildroot-2021.05/contents/board/sophgo?ref=buildroot-2023.11
bm1688_wevb_emmc
common
cv186ah_wevb_emmc
edge_buildroot
```

No `CV181X`. The board folder is also renamed from `cvitek` to `sophgo` there. So 2021.05 is the only Buildroot that can build this camera, with the Sophgo delta on top. **Recommendation:** stay on 2021.05. Then watch the three packages that carry the attack surface:

- **dropbear**: the SSH server. Check the version in the image against the
upstream advisories.
- **busybox**: the shell and the init. Check the version, the `ash` shell and
the applets have had CVEs.
- **openssl**: needed by `wpa_supplicant_s1g` for WPA2/WPA3. It stays, so its
version needs to be checked. If any of them is too old, the practical option is to bump the single package in the Buildroot fork rather than to move the whole tree. A newer Buildroot would need the CV181X board support ported over, which is more work than patching one package.

### u-boot

The fork has three own commits on top of upstream v2021.10, then the same weekly stable releases:

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

Ten commits ahead of upstream v1.2. The 381 behind are upstream commits after v1.2. OpenSBI is a small, well reviewed project and the delta is small enough to audit by hand. The own commits are the same pattern as the kernel:

```
ba54b003  2024-02-14  note: sync patch from T-Head.
216793f1  2024-02-14  (opensbi): Init branch sg200x-dev
```

plus the weekly stable releases. The T-Head patch is a sync of an upstream vendor patch for the same generation of RISC-V cores, it does not touch the CV181X support.

### FreeRTOS

`FreeRTOS-Kernel` and `Lab-Project-FreeRTOS-POSIX` are forks of the FreeRTOS projects, last touched February 2024, and upstream has moved on (FreeRTOS-Kernel V11.3.3, October 2026). The RTOS runs on the second core of the SG2002. The camera does not need it. `CONFIG_ENABLE_FREERTOS=y` in the defconfig is what pulls it in. **Recommendation:** drop FreeRTOS from the minimal image. The defconfig has `CONFIG_ENABLE_FREERTOS`, `CONFIG_ENABLE_RTOS_DUMP_PRINT` and `CONFIG_DUMP_PRINT_SZ_IDX`, all three go. That removes `freertos`, `FreeRTOS-Kernel` and `Lab-Project-FreeRTOS-POSIX` from the build.

### flatbuffers

A fork of `google/flatbuffers`, last touched July 2024. Upstream is at 25.2. Flatbuffers is used by the TPU SDK. With the TPU stack gone, flatbuffers goes too.

## The blobs

These are the files that are not source code. This is the part that matters most for trust.

### live555.tar.gz: a real blob

`sophgo/oss` at `oss_release_tarball/musl_riscv64/live555.tar.gz` contains the Live555 headers and **compiled libraries**:

```
$ tar tzf live555.tar.gz | grep -cE '\.(h|hh)$'
182
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

The tarball also carries `bin/live555MediaServer`. That binary is not used by `cvi_rtsp`. The server class in `cvi_rtsp` is `CVI_RTSP`, it inherits from the Live555 `RTSPServer` class and links the four libraries above. The generic `live555MediaServer` is a separate program that comes with the same tarball.

#### The headers are verified upstream code

All 181 headers were compared against the `rgaufman/live555` Git mirror, which mirrors the official source. The blob is Live555 **2020.07.21**.

```
live.2020.04.24   175 of 181 headers byte identical
                   6 differ, 4 of them only in the version string
```

The version files say `2020.07.21` instead of `2020.04.24`, which makes the blob one release newer than the compared commit. The other two differences are `liveMedia.hh`, an include list, and `ProxyServerMediaSession.hh`.

**There is no injected code in the headers.** They are unmodified upstream Live555.

#### The archives are not verifiable

```
$ ar t lib/libUsageEnvironment.a
UsageEnvironment.o
HashTable.o
strDup.o

$ strings lib/libUsageEnvironment.a | grep GCC
GCC: (Xuantie-900 linux-5.10.4 musl gcc Toolchain V2.6.1 B-20220906) 10.2.0
```

Compiled objects, no source. Built with the Sophgo cross compiler, not with the upstream build. The source is identifiable and matches upstream, but the compiled artifacts cannot be checked against a reference build without reproducing the vendor toolchain.

#### The Buildroot package needs a fix

Live555 itself is not shady. It is a well known project (LGPL-3.0, mirrored at `rgaufman/live555`, last push July 2026). And Buildroot has a package for it:

```
package/live555/live555.mk:
  LIVE555_VERSION = 2021.05.03
  LIVE555_SITE = http://www.live555.com/liveMedia/public
  LIVE555_LICENSE = LGPL-3.0+
  live555.hash: md5 + sha256
```

The problem is that the official site no longer serves the tarballs:

```
http://www.live555.com/liveMedia/public/live.2021.05.03.tar.gz   404
http://www.live555.com/liveMedia/public/live.2020.05.21.tar.gz   404
http://www.live555.com/liveMedia/public/live.2025.10.13.tar.gz   404
```

The homepage loads, the `public/` directory does not. The package has to switch to a Git clone against the mirror with a pinned commit.

**Recommendation:** build live555 from source with the Buildroot package and point `cvi_rtsp` at it. The `cvi_rtsp` build already supports this, its `build.sh` looks for `LIVE555_DIR` first and only falls back to the download:

```sh
if [ "${LIVE555_DIR}" = "" ]; then
    # downloads prebuilt/live555.tar.gz
fi
```

So the switch is: set `LIVE555_DIR` to the Buildroot build and the blob is never fetched. The Buildroot package installs the same four static libraries plus `live555MediaServer`, so the `Makefile.inc` paths work unchanged. Two details to get right in the build:

- The Buildroot package builds with `BR2_STATIC_LIBS=y` into
`linux` config, with `linux-with-shared-libraries` otherwise. The `cvi_rtsp` Makefile expects static archives, so `BR2_STATIC_LIBS=y`.
- The Buildroot package installs to the sysroot, the tarball installs to
`/system`. `LIVE555_DIR` has to point at the right place, and `LIVE555_INC` uses `include/BasicUsageEnvironment`, `include/groupsock`, `include/liveMedia` and `include/UsageEnvironment` as separate include directories. The Buildroot layout has them in one `include` directory, so `LIVE555_INC` needs adjusting.

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
| `live555` | 181 headers | 4 archives | **blob** |
| `opencv_aisdk` | 0 | 0 | **blob** |

Only live555 and opencv_aisdk are real blobs. The rest ship the source and build it.

The live555 headers were verified against the upstream source and are unmodified. The four archives are compiled objects without source, built with the vendor toolchain, so they do not count as verifiable.

### The reCamera.zip

The `reCamera` buildroot package pulls a zip and copies its install tree into the target:

```make
RECAMERA_SOURCE = reCamera.zip
RECAMERA_SITE = https://github.com/Seeed-Studio/sscma-example-sg200x/archive
```

That resolves to `.../archive/reCamera.zip`, which is a **git branch** called `reCamera`. The branch does not exist upstream any more:

```
$ gh api /repos/Seeed-Studio/sscma-example-sg200x/branches
dev, feat/multi-model, feat/ov5647-5mp, feature/halow, feature/sensecraft-classify-dashboard,
fix/ae-feedback, main, supervisor, yolo26
```

No `reCamera`. The package is already broken, so it cannot be in any recent upstream build either. **Recommendation:** remove it. It carries the web UI and the device manager, not the camera.

### The one local patch

`external/cvi_rtsp/patches/` holds a single patch, applied by `external/setenv.sh` before the build:

```
0001-emit-H264-sprop-parameter-sets-in-SDP.patch
```

It adds the H264 SPS and PPS parameter sets to the SDP, so that a client can decode the stream without a separate request. The patch is well written and documented, it explains the Annex-B parsing in the comment. This is a local patch, not upstream code. It is a good one and it is needed for the RTSP server to work with normal players. Two options: keep it as a patch, or send it upstream to `sophgo/cvi_rtsp`. Keeping it as a patch is fine, the patch is in the repo and readable.

## The TPU stack

`cviruntime`, `cvikernel`, `cvimath`, `cvibuilder`, `cnpy`, `tdl_sdk` and `flatbuffers` are the AI accelerator SDK. They exist to run the sscma models. A camera does not need them. `ive` is different. It is the image processing engine, it does histogram, threshold, alpha blend and similar operations. The ISP tuning and some of the video pipeline use it. Keep it.

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

That is a much smaller list, and every entry on it is either upstream Linux with a small vendor delta, or vendor source code that has no alternative because the hardware has no other driver.

## Open questions

- Is the RTOS really not needed? The camera works on the Linux core, the
second core runs FreeRTOS. If nothing uses it, it goes.
- live555 from Buildroot: the `cvi_rtsp` build needs `LIVE555_DIR` set, and
the Buildroot package installs to the sysroot. Check that the include and library paths line up.
- Buildroot 2021.05 is end of life. Dropbear, busybox and openssl in it have
known CVEs. Worth a look at whether the image needs openssl at all, the minimal image has no TLS use case.

## Who is Sophgo

Sophgo Technologies (算能, sophgo.com) is a Chinese chip company, founded
2022, based in China. It makes the SG200x and CV181x TPU processors, the
SoC in the reCamera. The GitHub organisation `github.com/sophgo` was created
2022-01-17 and holds 106 public repositories. Its Open Source contact is
opensource@sophgo.com.

Every submodule in this repo comes from that organisation. There is no
upstream project of the reCamera OS itself. The vendor ships the hardware
reference SDK, and this repo is the trimmed down version of it.

That has one consequence worth keeping in mind: the vendor decides when a
release lands. The `weekly rls` commits show the cadence, roughly every
four to six weeks. There is no way to get a fix faster from upstream,
because upstream does not exist for the vendor parts.

## What the build actually uses

Not all 27 submodules are needed for a build. The build log
`output/sg2002_recamera_emmc/build-host.log` shows which directories the
make targets entered:

```
build               the board definitions and the rootfs rules
buildroot-2021.05   the package build
u-boot-2021.10      the bootloader
fsbl                the first stage bootloader
linux_5.10          the kernel
osdrv               the camera drivers
cvi_mpi             the MPI API
cvi_rtsp            the RTSP server
```

Eight directories. Everything else is either pulled in as a source tree
for a later step or not used at all for this target.

`cviruntime` is the special case. It is not entered as a build directory
but it is copied into the output and `build_tpu_sdk()` is run from
`cviruntime/build_sdk`. That builds the AI accelerator SDK, including
flatbuffers, opencv and curl, and installs it to
`output/.../tpu_musl_riscv64/cvitek_tpu_sdk`.

The remaining submodules are not part of the target build:

| Submodule | Role | In the build? |
|---|---|---|
| `cviruntime` | builds the TPU SDK | yes, as a source tree |
| `cvikernel` | the TPU kernel driver | no |
| `cvimath` | the TPU math library | no |
| `cvibuilder` | the TPU Docker setup | no |
| `cnpy` | NumPy file access for the TPU tools | no |
| `tdl_sdk` | the model deployment SDK | no |
| `flatbuffers` | serialization for the TPU | no, the SDK has its own |
| `ive` | the image vector engine | no, but the ISP wants it |
| `freertos` | the RTOS distribution | no |
| `FreeRTOS-Kernel` | the RTOS kernel | no |
| `Lab-Project-FreeRTOS-POSIX` | the POSIX layer | no |
| `oss` | sample applications | no |
| `isp_tuning` | the sensor tuning data | no |
| `SensorSupportList` | the sensor module list | no |
| `ramdisk` | the boot overlay | no |
| `host-tools` | the cross toolchain | no, the toolchain is in the image |

## Upstream alternatives

Eight of the submodules are plain forks with a known upstream. The question
for each one is whether the vendor delta can be carried as a patch.

| Submodule | Upstream | Delta | Can it be replaced? |
|---|---|---|---|
| `linux_5.10` | `XUANTIE-RV/linux`, and upstream Linux 5.10 | 250 vendor commits, of which 3 are the actual port | no |
| `u-boot-2021.10` | `u-boot/u-boot` v2021.10 | 3 vendor commits | no, the board init needs `cvitek.h` |
| `opensbi` | `riscv-software-src/opensbi` | 1 snapshot commit, patches `platform/template` | no |
| `buildroot-2021.05` | `buildroot/buildroot` 2021.05 | 6 vendor commits | no, the board config lives here |
| `flatbuffers` | `google/flatbuffers` | 1 commit, identical to upstream v2.0.8 | yes, it is upstream |
| `FreeRTOS-Kernel` | `FreeRTOS/FreeRTOS-Kernel` | 1 commit, 9 files changed in the RISC-V and CA53 ports | no |
| `Lab-Project-FreeRTOS-POSIX` | `FreeRTOS/Lab-Project-FreeRTOS-POSIX` | 1 commit | no |
| `freertos` | `FreeRTOS/FreeRTOS` | snapshot commits | no |

The answer is no for everything that is used. The reason is the same in
every case: the vendor delta is not a patch that can be re-applied, it is
the hardware support. The kernel carries the CVITEK drivers for SDHCI, NAND,
I2S, DMA and ION. The FreeRTOS fork patches the RISC-V and the CA53 port
layers, the context switch and the interrupt handling. The u-boot fork
adds `board/cvitek/cvi_board_init.c` and `include/cvitek/cvitek.h`.

The one that could go is `flatbuffers`, and only because the TPU stack goes
with it. It is already upstream, there is nothing to carry over.

The other direction is the opposite of replacing: going to a newer upstream.
The kernel is on 5.10 and cannot move. The camera drivers in `osdrv` use
the two argument `class_create()`, which was removed in kernel 6.4, and
their version guards stop at 5.10. See `kernel-upgrade.md`.

## The devcontainer distribution

The devcontainer runs Debian 13 (trixie, glibc 2.41). The CI runner runs
Ubuntu 26.04 (resolute, glibc 2.43).

Ubuntu 26.04 works for the devcontainer as well. The requirements are
checked:

- `buildpack-deps:26.04-curl` exists as a Docker image.
- glibc 2.43 satisfies everything. The oldest symbol the prebuilt host
  tools need is `GLIBC_2.14` in `make_ext4fs`, and `mkimage` needs
  `GLIBC_2.25`. Both are well below 2.41.
- All packages of the Dockerfile exist on 26.04. `ninja-build`,
  `android-sdk-libsparse-utils`, `scons`, `parallel`, `tree`,
  `python3-pip` and `nodejs` are in universe, the rest is in main.

Two packages need a different name on Ubuntu:

| Debian | Ubuntu |
|---|---|
| `tclsh` | `tcl` |
| `ssh-client` | `openssh-client` |

And two versions are lower than they should be. Ubuntu 26.04 ships
Node.js 22.22.1, the Dockerfile asks for Node 24. The NodeSource
repository does not publish a resolute repository yet, so Node 24 would
have to come from the NodeSource setup script, which does not know
resolute either. Python is 3.14.3 on Ubuntu against 3.13 on Debian.

> The base image is a choice, not a constraint. Debian 13 works today and
> the build does not care. Ubuntu 26.04 would be one distribution for the
> container and the runner, which is worth something for the shared host
> tool list.

