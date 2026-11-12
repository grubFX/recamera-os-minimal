# What a kernel upgrade would take

The question: the camera runs on Linux 5.10. Why not 6.4, or 7.x?

Short answer: the camera drivers are not in the kernel, they are built out of
tree from `osdrv` and written against the 5.10 API. Moving the kernel means
moving those drivers with it.

This document is the breakdown, with the actual numbers.

## First: 5.10 is not EOL

That was worth checking, because it changes the security argument.

```
$ gh api /repos/gregkh/linux/commits?sha=linux-5.10.y&per_page=1
2026-11-06  3a323bc2  Linux 5.10.274
```

Upstream Linux 5.10 is a longterm release and still gets fixes. The Sophgo
fork mirrors that with the weekly stable releases, the last one being
`2d84ae4338` from 2026-10-28.

So the kernel is not abandoned. It is behind, but it is maintained.

## Where the camera drivers live

Not in the kernel. In `osdrv/interdrv/`:

```
osdrv/interdrv/cif/       MIPI receiver
osdrv/interdrv/snsr_i2c/  sensor
osdrv/interdrv/vi/        video input
osdrv/interdrv/vpss/      video processing
osdrv/interdrv/cvi_vc_drv/ encoder and decoder
osdrv/interdrv/fb/        framebuffer
```

They are built as out-of-tree modules with
`make KERNEL_DIR=... INSTALL_DIR=.../ko`, from the `osdrv/Makefile`.

The kernel tree has only the Kconfig stubs for them:
`drivers/media/platform/cvitek/Kconfig` and `drivers/video/fbdev/cvitek/Kconfig`
contain the menu entries but no driver code.

## The version guards stop at 5.10

```
$ grep -rhoP "KERNEL_VERSION\(\d+, \d+, \d+\)" osdrv/interdrv/ | sort -u
KERNEL_VERSION(2, 6, 36)
KERNEL_VERSION(4, 10, 0)
KERNEL_VERSION(4, 11, 0)
KERNEL_VERSION(4, 15, 0)
KERNEL_VERSION(5, 10, 0)
```

The highest version anyone wrote code for is 5.10. Nothing above it.

## The concrete blockers

### 1. `class_create()` with the module argument, removed in 6.4

17 call sites in `osdrv`. The two argument form stopped working in kernel 6.4:

```c
dev->vi_class = class_create(THIS_MODULE, CVI_VI_CLASS_NAME);
```

has to become

```c
dev->vi_class = class_create(CVI_VI_CLASS_NAME);
```

That is a mechanical change, one line each. Not the hard part.

Where they are:

| Keep | Drop |
|---|---|
| `vi/common/vi_core.c` | `tpu/common/cvi_tpu_interface.c` |
| `vo/common/vo_core.c` | `jpeg/cvi_jpeg.c` |
| `cvi_vc_drv/cvi_vc_drv.c` | `mon/common/cvi_mon_interface.c` |
| `base/base.c` | `fast_image/fast_image.c` |
| `saradc/cv181x/cvi_saradc.c` | `rtos_cmdqu/rtos_cmdqu.c` |
| | `ive/common/cvi_ive_interface.c` |
| | `wiegand/cvi_wiegand.c` |
| | `vcodec/cvi_vcodec.c` |

Only five of them are in the camera path. The rest belong to the AI stack and
the parts that get dropped anyway.

### 2. `set_fs()`, removed in 5.18

174 call sites, but almost all of them are in old WiFi driver trees that the
camera does not use: Realtek rtl8188f, rtl8189fs, rtl8723ds, rtl8821cs,
MediaTek mt7603, Bouffalolab bl602c, Broadcom bcmdhd, and the GT9xx touch
controller.

In the camera path there is exactly one:

```
osdrv/interdrv/cvi_vc_drv/vcodec/vdi/linux/vdi_osal.c
```

in a file close path. Replacing it is a one line change.

### 3. `clk_hw_register_clkdev()`, removed in 6.5

This one is in the kernel tree, not in `osdrv`:

```
$ grep -rc clk_hw_register_clkdev linux_5.10/drivers/clk/cvitek/*.c
linux_5.10/drivers/clk/cvitek/clk-cv180x.c: 3
linux_5.10/drivers/clk/cvitek/clk-cv181x.c: 5
linux_5.10/drivers/clk/cvitek/clk-cv182x.c: 3
linux_5.10/drivers/clk/cvitek/clk-cv1835.c: 3
```

14 call sites in 9.276 lines of clock driver code. The function is gone in
6.1 already:

```
$ grep -c clk_hw_register_clkdev v6.1:include/linux/clk.h
0
$ grep -c clk_hw_register_clkdev v7.3:include/linux/clk.h
0
```

### 4. The CV181X DMA controller has no upstream driver

```
linux_5.10/drivers/dma/cvitek/   1 file, 2.200 lines
```

The 6.18 Sophgo kernel has no CV181X DMA driver at all. Not a different
version, nothing:

```
$ gh api /repos/sophgo/linux-riscv/contents/drivers/dma/cvitek
404 Not Found
```

`osdrv` uses this DMA controller for the video pipeline. Without the driver
there is no camera.

### 5. The scheduler patch touches kernel internals

`linux_5.10/kernel/sched/cvi_sched.h` is included by `kernel/sched/core.c` and
rewrites the scheduling policy:

```c
static inline void cvi_checkpriority(struct task_struct *p, struct sched_attr *attr)
```

It pins the vendor threads to a fixed priority list and caps every other
realtime task at priority 80. It works by writing directly into `sched_attr`,
which is the interface to `sched_setattr`.

From 6.6 on the scheduler is EEVDF, `sched_attr` gained fields, and the way
the core validates and applies priorities changed. This patch has to be
rewritten, not adjusted.

### 6. The file_operations and proc_ops changes

166 `read`/`write`/`read_iter`/`write_iter` assignments and 105
`proc_dir_operations` or `proc_ops` references. These are soft breaks, the
old names still compile for a long time with a warning.

## Why there is no ready made 6.x tree for this camera

| Kernel | Version | CVI video drivers | State |
|---|---|---|---|
| `sophgo/linux_5.10` | 5.10.4 | in `osdrv`, out of tree | used today |
| `sophgo/linux` `v6.8-rc1` | 6.8-rc1, Jan 2024 | none | frozen since 2024 |
| `sophgo/linux-riscv` master | 6.18, active | none | SoC only |
| `torvalds/linux` | 7.4-rc2 | none | SoC only |

The 6.8 branch in `sophgo/linux` is the interesting one. It has a branch
`soc/sg2000` and it is the same generation of hardware, but it was last touched
in January 2024 and it has no CVI video drivers either.

## The good news: Sophgo already modernized the SoC part

The 6.18 kernel has:

```
drivers/clk/sophgo/clk-cv1800.c        47 KB
drivers/pinctrl/sophgo/pinctrl-sg2002.c
drivers/phy/sophgo/phy-cv1800-usb2.c
```

The clock driver is the modernized successor of the 5.10 one. It is smaller
(47 KB against 71 KB) and it uses the current API:

```c
ret = devm_clk_hw_register(dev, hw);
```

instead of the removed `clk_hw_register_clkdev`. It is built against the
CV1800 and CV181x clock trees.

And Mainline has the same, which is the better starting point:

```
arch/riscv/boot/dts/sophgo/sg2002.dtsi
drivers/pinctrl/sophgo/pinctrl-sg2002.c
drivers/clk/sophgo/clk-cv1800.c
sound/soc/sophgo/cv1800b-sound-dac.c
sound/soc/sophgo/cv1800b-sound-adc.c
drivers/mmc/host/sdhci-of-dwcmshc.c
Documentation/devicetree/bindings/mailbox/sophgo,cv1800b-mailbox.yaml
```

So the SoC support for a modern kernel exists, is maintained and is upstream.
What does not exist is the camera part. Mainline has seven references to
CV181X and every one of them is SoC level.


## What a port would actually cost

Rough order of magnitude, for someone who does this kind of work:

| Work | Size | Notes |
|---|---|---|
| `class_create` migration | 5 call sites | Mechanical, an hour |
| `set_fs` removal | 1 call site | Mechanical |
| Clock driver to 6.5+ | 9.276 lines | The `clkdev` path has to be replaced with the `devm_` path. The modernized Sophgo version shows how, and Mainline has it already. |
| DMA driver | 2.200 lines | Has to be ported or written against the new DMA API |
| Scheduler patch | 100 lines | Rewrite for EEVDF, and check whether the pinning is still needed at all |
| `osdrv` API fixes | unknown until compiled | The compiler finds these one at a time |
| Bootloader | moderate | U-Boot and OpenSBI have their own deltas. Mainline U-Boot has the SG2002 device trees, so the board support can move there. |

And then the part that decides everything: **there is no upstream to merge
into.** The CV181X video drivers exist in one vendor tree, written for one
kernel version. Nobody else maintains them. A port is not a contribution, it
is a fork that only exists in this repository.

## The realistic path, if it is ever needed

Not a rewrite from 5.10, but a move onto what already exists:

1. Start from Mainline, or from `sophgo/linux-riscv` at 6.18. Both have the
   SoC support: `sg2002.dtsi`, `clk-cv1800.c`, `pinctrl-sg2002.c`, the sound
   codec drivers, the SDHCI host and the mailbox binding.
2. Move the board device tree. The reCamera board DTS lives in
   `external/build/boards/cv181x/sg2002_recamera_emmc/dts_riscv/` and only
   needs to be rewritten on top of the Mainline `sg2002.dtsi`.
3. Port the DMA driver. It is the smallest piece that has no successor
   anywhere, 2.200 lines.
4. Use the modernized clock driver instead of the 5.10 one.
5. Fix `osdrv` against the compiler. It is a known finite set of API breaks.
6. Decide about the scheduler patch, and whether the priority pinning is
   still wanted at all.
7. Move U-Boot to a version with the SG2002 device trees.

## The honest recommendation

For a camera that should do one thing, the effort is not justified now.

The kernel gets weekly stable releases with the upstream security fixes. The
packages that a network can reach, dropbear, busybox and openssl, are the
ones that need attention, and that is a package version bump, not a kernel
port.

The one thing worth doing is keeping the fork up to date with the weekly
stable releases. That is already the case.

If the kernel version becomes a requirement later, the path is the one above:
move onto Mainline or the 6.18 Sophgo tree, port the DMA driver, fix `osdrv`.


