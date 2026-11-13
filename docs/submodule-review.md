# Submodule review

Every submodule in the repo, checked for: is it a fork of something upstream, is it a blob, how old is it, and is there a better known alternative. **Hard requirement:** the kernel code has to trace back to real upstream Linux source. No proprietary code dressed up as Linux. This document is the evidence for that requirement.

## Summary

There are 25 submodules, not 27. The build of the target touches eight of
them. Nine of the 25 are forks with a known upstream, sixteen are Sophgo
own code.

| Submodule | Type | Vendor commits over upstream | Recommendation |
|---|---|---|---|
| `linux_5.10` | fork of upstream Linux 5.10.4 | 31 | keep, used |
| `buildroot-2021.05` | fork of buildroot 2021.05 | 6 | keep, used |
| `u-boot-2021.10` | fork of u-boot v2021.10 | 25 | keep, used |
| `opensbi` | fork of upstream OpenSBI | 7 | keep, used |
| `FreeRTOS-Kernel` | fork of FreeRTOS | 1 | drop, see below |
| `Lab-Project-FreeRTOS-POSIX` | fork of FreeRTOS | 1 | drop |
| `freertos` | sophgo fork | 7 | drop with the RTOS |
| `flatbuffers` | **now google/flatbuffers** | **0** | **replaced with google/flatbuffers v2.0.8** |
| `cnpy` | fork of rogersce/cnpy | 1 | drop with the TPU stack |
| `fsbl` | sophgo, GPL-2.0 | own code | keep, used |
| `osdrv` | sophgo, source | own code | keep, used |
| `ramdisk` | sophgo, source | own code | keep, trim |
| `build` | sophgo, source | own code | keep, used |
| `cvi_rtsp` | sophgo, source | own code | keep, used |
| `cvi_mpi` | sophgo, source | own code | keep, **pinned to `693a72a`**, see below |
| `isp_tuning` | sophgo, binary tuning files | own code | keep |
| `SensorSupportList` | sophgo, BSD-2 | own code | keep |
| `oss` | sophgo, tarballs | own code | trim hard |
| `host-tools` | sophgo, toolchain | own code | keep |
| `cvibuilder` | sophgo | own code | drop with the TPU stack |
| `cvikernel` | sophgo | own code | drop with the TPU stack |
| `cviruntime` | sophgo | own code | drop with the TPU stack |
| `cvimath` | sophgo | own code | drop with the TPU stack |
| `tdl_sdk` | sophgo | own code | drop with the TPU stack |
| `ive` | sophgo | own code | image processing, keep |

## The cvi_mpi release 923e41a is broken

The vendor release `923e41a` (weekly rls 2026.10.28) cannot be built. It
was pulled in by commit `ad96efd` ("Update all vendor submodules and fix the
build pipeline"). The release deletes `modules/isp` without putting
anything in its place, and it leaves several references to the removed
directories behind. Five separate failures come out of it, and they have
to be worked around one after the other:

| # | What the vendor did | How the build fails |
|---|---|---|
| 1 | deleted `modules/isp` | the samples that go into the image link against `-lisp`, `-lisp_algo`, `-lae`, `-laf`, `-lawb`, `-lcvi_bin`, `-lcvi_bin_isp`. The libraries are gone. |
| 2 | left `isp` in `SUB_DIRS` of `modules/Makefile` | `make: No such file or directory` for the missing directory |
| 3 | left `bin` in `SUB_DIRS` | `modules/bin` still exists but needs `isp_bin.h` and `cvi_json_struct_comm.h` from the removed `modules/isp` |
| 4 | dropped the compile rule for the sensor sources in `component/isp/sensor/<arch>/Makefile_full` | the objects are built with the implicit rule of make, which uses the **host** compiler and no include path. The build produces x86 objects that the riscv linker rejects, and the sensor sources do not find `<linux/cvi_type.h>`. |
| 5 | `Makefile_full` says `$(TARGET_SO): $(OBJS_PATH)` but the variable is called `OBJS` | `OBJS_PATH` is empty, so the library is linked before the objects exist |

The release before it, `693a72a` (weekly rls 2026.08.24), is consistent. It
has `modules/isp` with the headers and the implementation, and the sensor
bug is older than the release and also in `693a72a`.

So the submodule is pinned to `693a72a` and the sensor build gets a patch.
That is one pin plus one patch, instead of five patches against a release
whose ISP implementation the vendor deleted on purpose.

> The upstream `modules/isp` in `693a72a` is 98,000 lines of ISP code. The
> vendor replaced it with `component/isp`, which only holds the sensor
> drivers, and dropped the ISP implementation itself. There is no public
> replacement for it, it is the proprietary part of the camera pipeline.

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

A fork of `google/flatbuffers`, last touched January 2020. It is not a
vendor fork in the sense that Sophgo changed something. The commit it sits
on is upstream flatbuffers 1.11.0 plus 208 upstream commits, and it carries
zero Sophgo commits. It **has been replaced** by the Google repository at
tag `v2.0.8`, see
[Upstream alternatives](#upstream-alternatives).

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
| `json-c`, `nlohmannjson`, `glog`, `nanomsg`, `uv`, `zlib`, `miniz`, `sqlite3`, `thttpd` | source | | fine |
| `flatbuffers` | source | | **not used**, the SDK builds it from the submodule now |
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

The TPU is the neural network accelerator in the SoC. The CV181x has a
separate compute unit for it, and it is what the sscma model demos run on.
The camera itself does not need it.

What the stack consists of, and what each part does:

| Part | What it is |
|---|---|
| `cviruntime` | the runtime library. It loads a compiled model and executes it on the TPU. This is the entry point of the whole stack. |
| `cvikernel` | the kernel driver for the TPU hardware. Registers the device, handles the interrupt and the DMA of the model execution. |
| `cvimath` | the math library the runtime uses for the layers, matrix operations, quantisation, activations. |
| `cvibuilder` | the compiler that turns a trained model into the binary format the runtime loads. It also holds the flatbuffers schema of that format. |
| `cnpy` | reads and writes the NumPy `.npy` and `.npz` files that the training pipeline produces. It is a convenience for the tools, the runtime does not need it. |
| `tdl_sdk` | the model deployment SDK, the higher level API on top of the runtime, with the pre and post processing around a model. |
| `flatbuffers` | the serialization format the model file is written in. The model file is a flatbuffer, `cvimodel_tool` reads and writes it. |

The chain runs like this: a trained model comes out of the training pipeline
as a NumPy file, `cnpy` reads it, `cvibuilder` compiles it into a flatbuffer
model file, `tdl_sdk` wraps it with the pre and post processing, and
`cviruntime` executes it on the TPU, which `cvikernel` drives.

### What it costs

The stack is not small and it is not free to build:

- `build_tpu_sdk()` in `build/envsetup_soc.sh` runs `cviruntime/build_tpu_sdk.sh`. That script builds **flatbuffers**, **opencv** and **curl** from source as host tools, then builds the runtime and the kernel driver against them.
- The result lands in `output/.../tpu_musl_riscv64/cvitek_tpu_sdk`, together with a `third_party` directory that holds 20 source tarballs, including two OpenCV variants.

### What lands in the image

The runtime is not only built, it is flashed. `libcviruntime.so`,
`libcvikernel.so` and the kernel module `cv181x_tpu.ko` are in the system
partition. So the stack is currently in the image, it is just not used by
anything in it.

That means dropping it is not only a build time question. It also needs:
- `cv181x_tpu.ko` removed from the module list
- the two shared libraries removed from the target packages
- `build_tpu_sdk()` removed from the build

`ive` is different. It is the image vector engine, it does histogram,
threshold, alpha blend and similar operations. The ISP tuning and some of
the video pipeline use it. Keep it.

## What is left after the trimming

```
linux_5.10          upstream Linux 5.10.4 + 31 vendor commits
u-boot-2021.10      upstream v2021.10 + 25 vendor commits
opensbi             upstream OpenSBI + 7 vendor commits
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

Not all 25 submodules are needed for a build. The build log
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
| `flatbuffers` | serialization for the TPU | no, the SDK builds its own from the submodule |
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

Nine of the 25 submodules are plain forks with a known upstream. For each one
the question is whether the vendor delta can be carried as a patch.

The numbers below are measured, not estimated. `Vendor commits` counts the
commits on top of the upstream branch, `Delta` is the content difference
against the upstream point the fork was branched from, and `Files` is how
many files that touches.

| Submodule | Upstream | Vendor commits | Delta | Files | Replaceable? |
|---|---|---|---|---|---|
| `flatbuffers` | `google/flatbuffers` | **0** | **0** | 0 | **yes, it is already upstream** |
| `cnpy` | `rogersce/cnpy` | 1 | 4 files, +655 / -312 | 4 of 9 | possible, but the upstream is dead since 2018 |
| `buildroot-2021.05` | `buildroot/buildroot` 2021.05 | 6 | 35 files, +1423 / -21 | 35 of 12463 | no, the board config lives here |
| `FreeRTOS-Kernel` | `FreeRTOS/FreeRTOS-Kernel` V10.4.6 | 1 | 9 files, +528 / -238 | 9 of 609 | no, the RISC-V and CA53 ports are patched |
| `Lab-Project-FreeRTOS-POSIX` | `FreeRTOS/Lab-Project-FreeRTOS-POSIX` | 1 | 20 files, +350 / -772 | 20 of 36 | no |
| `opensbi` | `riscv-software-src/opensbi` | 7 | cv181x suspend to RAM, reset ecall, RTC fixes | 6 patches | no |
| `freertos` | `FreeRTOS/FreeRTOS` | 7 | C906 boot up, tracealyzer | 2 real patches | no |
| `u-boot-2021.10` | `u-boot/u-boot` v2021.10 | 25 | 290 files, +51302 / -1856 | 290 of 17949 | no, the board init needs `cvitek.h` |
| `linux_5.10` | `XUANTIE-RV/linux`, and upstream Linux 5.10 | 31 | 2042 files, +544526 / -2107 | 2042 | no |

The answer is no for everything that is used. The reason is the same in
every case: the vendor delta is not a patch that can be re-applied, it is
the hardware support.

### flatbuffers

This one is different, and the earlier note in this document was wrong. It
said the fork was "identical to upstream v2.0.8". It is not. The fork sits
on commit `6da1cf79`, which is **flatbuffers 1.11.0 plus 208 upstream
commits**, dated 2020-01-19. It carries zero Sophgo commits. It is a
pure upstream snapshot that the vendor never touched again.

So the submodule can simply point at Google. The question is which version.

| Version | Date | What it changes against the current fork |
|---|---|---|
| `v1.12.0` | 2020-03-12 | 38 commits, the closest successor of the current stand |
| `v2.0.0` | 2020-10 | the major version bump, flatbuffers 2.0 changed the generated API |
| `v2.0.8` | 2022-08-29 | the last 2.0 release, 1248 files differ from the current fork |
| `v25.x` | 2026 | current upstream, far too large a jump |

`v2.0.8` is the version that is used now. It is a release, it is stable, and
it is close enough to the current stand that the generated code stays
compatible. Going to `v25.x` would mean a much larger jump for no gain, the
TPU SDK does not use anything newer.

#### The two flatbuffers

The TPU build uses flatbuffers twice, and the two have to match:

| Where | What | Version |
|---|---|---|
| the `flatbuffers` submodule | the host `flatc` that generates `cvimodel_generated.h` and `parameter_generated.h` | 2.0.8 |
| the same submodule, built for riscv64-musl | the library and headers that get linked into `libcviruntime.so` | 2.0.8 |

The generated header has a `static_assert` on the flatbuffers version, so a
mismatch is a compile error, not a runtime surprise. With the old fork the
host side was 1.11 and the target side was 1.11, and it worked. With the
submodule on 2.0.8 the target side had to follow.

Both sides are built from the same source now. The target library is not
taken from the `oss` tarball, which is a prebuilt binary package from
Sophgo and was still on 1.11. `external/setenv.sh` patches
`cviruntime/build_tpu_sdk.sh` to build the submodule with the riscv64-musl
toolchain instead of extracting the tarball, using the CMake file
`cviruntime/scripts/toolchain-riscv64-linux-musl-x86_64.cmake`. The build
installs into the same directory the tarball was extracted to, so the rest
of the script does not change and the result has the same layout, the same
40 files including `bin/flatc`.

`build_3rd_party` unpacked the same tarball a second time, into the root of
the SDK. That one was 1.11 too and nothing used it, so the entry is taken
out of the list there and the stale tarball is removed from the `oss` tree.

Nothing from flatbuffers ends up in the image, it is build material only.

#### What was checked

- `flatc` from `v2.0.8` builds, and `cvibuilder` builds against it
- the generated headers differ from the old ones only in three ways: a
  `static_assert` on the version, enums with an explicit `uint8_t` base
  type, and a size argument for `VerifyField`. No API break
- the cviruntime sources that use the generated headers compile against both
  the host and the target toolchain
- a deliberate mismatch, new headers against the old library, fails with
  `static assertion failed: Non-compatible flatbuffers version included`.
  That is the expected behaviour
- the whole image builds from an empty output directory, and
  `libcviruntime.so`, `libcvikernel.so` and `cv181x_tpu.ko` come out of it
- the target flatbuffers that is built from the submodule has the same
  layout as the tarball it replaces, and reports version 2.0.8

Only one file in the whole TPU stack includes flatbuffers directly,
`cviruntime/tool/cvimodel_tool.cpp`. Everything else uses the generated
headers.

> A stale copy of the old library survived in the output from an earlier
> build. The build does not clean the output, it only copies over it, and the
> old file had a newer timestamp than the new one, so `cp` left it alone.
> The result was a `libcviruntime.so` that reported `FlatBuffers 1.11.0`
> even though everything was built with 2.0.8. Removing the output
> directory and building again gives the same three copies of the library
> with the same checksum.

### The other forks

The kernel carries the CVITEK drivers for SDHCI, NAND, I2S, DMA and ION.
The FreeRTOS fork patches the RISC-V and the CA53 port layers, the context
switch and the interrupt handling. The u-boot fork adds
`board/cvitek/cvi_board_init.c` and `include/cvitek/cvitek.h`. The opensbi
fork adds cv181x suspend to RAM and a reset ecall. None of that can be
carried as a small patch, and none of it has an upstream equivalent,
because the hardware has no other driver.

The other direction is the opposite of replacing: going to a newer upstream.
The kernel is on 5.10 and cannot move. The camera drivers in `osdrv` use
the two argument `class_create()`, which was removed in kernel 6.4, and
their version guards stop at 5.10. See `kernel-upgrade.md`.

## Newer versions in the vendor repos

Every submodule was scanned against its vendor repository. Four have a
branch that is newer than the checked out commit:

| Submodule | Checked out | Newer branch | What it is |
|---|---|---|---|
| `cvikernel` | 2024-05-13 | `master` 2026-11-12 | the TPU kernel driver, not used by this target |
| `cviruntime` | 2026-10-28 | `master` 2026-11-12 | builds the TPU SDK, 15 days newer |
| `SensorSupportList` | 2026-10-29 | `master` 2026-11-12 | the sensor module list, 14 days newer |
| `cvi_rtsp` | 2026-06-30 | `master` 2026-10-27 | the RTSP server, 4 months newer |

These are the `master` branches of the same repositories. The vendor keeps
the board specific work on the `sg200x-dev` branch, and the `master` branch
is where the newer chips land. `cvikernel` for example has a `master` from
2026-11-12, but that is the tree for the cv190x, not for the SG2002.

So a blind `git pull` on these four would pull in the code of a different
SoC generation. They are not updates, they are a different product line.
The right move for `cviruntime` and `SensorSupportList` is to check whether
the two week old commits are worth taking, by reading them, not by pulling.

The rest is at the newest commit of the vendor branch that carries the
SG2002 work.

The vendor repositories also carry branches for the other chips, which are
not relevant here but show how the vendor organises the work:
`cv18xx-v4.1.x`, `cv18xx-v4.2.x`, `cv184x-v6.x`, `cv190x-v5.x`, `edge_dev`,
`bm1688` and `bm1688_dev`.
I2S, DMA and ION. The FreeRTOS fork patches the RISC-V and the CA53 port
layers, the context switch and the interrupt handling. The u-boot fork
adds `board/cvitek/cvi_board_init.c` and `include/cvitek/cvitek.h`.

The one that can be replaced is `flatbuffers`. It carries no vendor commits
at all, so the submodule can point at Google directly, and the newer
`v2.0.8` produces compatible generated headers.

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

