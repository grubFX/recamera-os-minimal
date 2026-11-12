# Requirements

Hard requirements for the minimal reCamera OS. These are not preferences.

## 1. The kernel has to be real upstream Linux

The kernel source has to trace back to genuine upstream Linux source code. No proprietary code, no closed blobs, nothing that only pretends to be Linux. **Status: met.** The kernel is `sophgo/linux_5.10`, whose history starts at `b1313fe517` "Linux 5.10.4" by Greg Kroah-Hartman and continues with upstream authors. Above that there are exactly three Sophgo commits, then weekly stable releases. The vendor additions are in one commit (`b4ca5efcaf` "linux porting cvitek asic chips"), which adds the CV181X device trees and drivers. The modifications to `arch/riscv/` are backports from upstream v5.12/v5.15, verified by diffing against the upstream releases. The kernel is also not abandoned. Upstream Linux 5.10 is a longterm release and still gets fixes, the last one `3a323bc2` "Linux 5.10.274" from 2026-11-06. The fork mirrors that with the weekly stable releases. The evidence is in [submodule-review.md](./submodule-review.md), the cost of a newer kernel in [kernel-upgrade.md](./kernel-upgrade.md).

## 2. No prebuilt binaries in the image

Every binary in the image has to be built from source that is in the repo or that comes from a verifiable upstream release with a checked hash. **Status: not met yet.** Two blobs to remove:

- `oss/oss_release_tarball/musl_riscv64/live555.tar.gz` contains only compiled
binaries. Live555 is LGPL-3.0 and available as a Buildroot package with a verified hash. Build it from source instead.
- `oss/oss_release_tarball/*/opencv_aisdk.tar.gz` contains only libraries.
Goes with the TPU stack. The `reCamera.zip` blob is already dead, its source branch no longer exists upstream.

### The live555 blob was checked in detail

The blob was verified against the upstream source, header by header, using the `rgaufman/live555` Git mirror.

```
live.2020.04.24   175 of 181 headers byte identical
                   6 differ, 4 of them only in the version string
```

The blob is Live555 **2020.07.21**, one release newer than the commit that was compared. The headers are unmodified upstream code, there is no injected code in them.

The four static archives are the problem:

```
lib/libUsageEnvironment.a
  UsageEnvironment.o
  HashTable.o
  strDup.o

GCC: (Xuantie-900 linux-5.10.4 musl gcc Toolchain V2.6.1 B-20220906) 10.2.0
```

Compiled objects, no source, built with the vendor cross compiler. The source is identifiable, but the compiled artifacts cannot be verified against a reference build without reproducing the vendor toolchain. That is what requirement 2 forbids, so the blob goes and Live555 is built from source.

One problem with the Buildroot package has to be fixed along the way: the official site no longer serves the tarballs.

```
http://www.live555.com/liveMedia/public/live.2021.05.03.tar.gz   404
```

The package has to switch to a Git clone with a pinned commit.

## 3. No hidden code in the forks

The forks of upstream software must be small enough to audit, and the delta must be documented. **Status: met.**

| Fork | Own commits | Behind upstream |
|---|---|---|
| `linux_5.10` | 31 ahead of upstream 5.10.4 | 0 |
| `buildroot-2021.05` | 6 | 0 |
| `u-boot-2021.10` | 3 | 0 |
| `opensbi` | 10 | 381 |

The 31 commits of the kernel break down into three vendor commits and the weekly stable releases:

```
b4ca5efcaf  2024-02-14  linux porting cvitek asic chips.
72ef337123  2024-02-14  [fea] Init sg200x-dev branch.
25faa0d62f  2024-03-29  [fix] fix linux build error..
```

plus 28 `weekly rls` commits. The stable releases carry upstream fixes, not vendor code.

### The vendor app stack is a separate question

The `sscma-example-sg200x` fork is not in this table, because it is not a fork of an upstream project. It is the Seeed application stack, Apache-2.0, and it is the source of the code the minimal image reuses.

The ONVIF implementation comes from there, and it was checked: it is in the public repository under `solutions/sscma-node/main/node/onvif/`, 1267 lines across 8 files, with the Apache-2.0 license header intact. It has no reference to the video pipeline at all.

## 4. Normal Linux, no weird patches

The result has to be a normal Linux system. No patched binaries, no initializer that only works on this one device, no hidden state. **Status: open.** The boot overlay sets up an overlayfs over nine directories on the userdata partition. That is a design decision of the vendor image. It also carries the factory reset and the OTA update, which are worth keeping for a camera that can be bricked by a bad flash. One thing does not fit the description of a normal Linux system and goes: `auto_download.sh` polls the GitHub release feed of `reCamera-OS` every 60 seconds and installs whatever it finds. The decision per piece is in [plan.md](./plan.md).

## 5. The camera has to work

Camera, RTSP, ONVIF, SSH, WiFi, NTP.

**Status: open.** This is what the plan is for.

## 6. ONVIF, without a SOAP stack

The camera has to be discoverable and controllable from a standard ONVIF client. Without pulling a SOAP stack into the image.

**Status: open, approach decided, implementation found.**

The vendor stack already has an ONVIF implementation. It is in the public Apache-2.0 repository `Seeed-Studio/sscma-example-sg200x`, in the directory `solutions/sscma-node/main/node/onvif/`, 1267 lines across 8 files. The CHANGELOG entry for 0.2.5 records it as a shipped feature.

```
GetProfiles            GetStreamUri             GetCapabilities
GetDeviceInformation   GetServices              GetSystemDateAndTime
GetVideoEncoderConfiguration
GetGuaranteedNumberOfVideoEncoderInstances
GetHostname            GetUsers                 GetEndpointReference
```

The dependency situation is the reason to prefer it:

| Need | Vendor implementation | `onvif_simple_server` |
|---|---|---|
| HTTP server | libhv, already in the image | BusyBox httpd, already in the image |
| Crypto | OpenSSL, already in the image | libtomcrypt, new |
| XML | hand written scanner | ezxml |
| SOAP stack | none | none |

No new dependency in the image, and the implementation was tested against real NVRs, including the fix for a truncated `GetCapabilities` response that Hikvision NVRs read as invalid XML.

**It is a Profile S implementation, not Profile T.** The SOAP envelope uses the `ver10` namespaces and the `trt` prefix, which is ONVIF Media 1, the specification behind Profile S. There is no `tr2` and no `ver20` anywhere in the code. Profile S is being deprecated, the last date for conformance submissions is 31 March 2027.

The consequence for the requirement: the camera is discoverable and streams, which is what the requirement asks for. It is not conformant, and it is not Profile T. Moving it to Media 2 is a separate project.

The work is the extraction. The code is compiled into `sscma-node`, the Node-RED node binary, and it has to become a standalone daemon. The vendor coupling is four symbols: `ma::Mutex`, `ma::Guard`, `ma_err_t` and `PROJECT_VERSION`.

The details, including what is missing for conformance, are in [onvif.md](./onvif.md).

## 7. No known CVE in the network facing packages

The image is reachable from the network. Dropbear, busybox and openssl have to be on versions without known vulnerabilities. **Status: open.** Buildroot 2021.05 is end of life, its upstream branch stopped in June 2021. The newer Buildroot in the same Sophgo repo has no CV181X support, so the fix is to bump the single package in the fork, not to move the tree. Plan step 4.

## 8. Everything is committed and pushed

Work happens on the `develop` branch of `grubFX/recamera-os-minimal`, in small commits that can be read on their own. **Status: in progress.**

## 9. Scope decisions

The scope of the minimal image is decided. These are the answers, with the reasoning behind each one.

**This section is the authority on the scope.** The plan steps carry the same decisions inline, and where the two differ, this section wins. The decisions are also at the top of [plan.md](./plan.md), with the reasoning behind each one in full.

| Question | Decision | Reason |
|---|---|---|
| OTA update | **yes** | The camera sits in a place where it is expensive to reach. A field update without a cable is worth the complexity. The mechanism is already there and it is a good one. |
| Gimbal and PTZ | **no** | A fixed camera is the target. The gimbal is a separate product variant with its own base board, so the hardware is not always there. PTZ in ONVIF is optional. |
| WiFi and HaLow | **no** | The target is the HQ PoE variant. Its core board, the `C1-2002`, has no wireless module. The network is Ethernet. |
| Battery | **no** | The HQ PoE draws its power over the Ethernet cable, 802.3af PoE Mode A. There is no battery to measure. |
| Sensor | **GC2053** | The HQ PoE product ships with the `S401 GC2053` sensor board. |
| Snapshot | **yes** | Many clients show a thumbnail in the device list. Without it the entry is blank and the camera looks broken. |

### OTA: yes, with one change

The mechanism is worth keeping. It has an A/B partition layout with a rollback:

```
external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/upgrade.sh
  latest    resolve the newest release and write the md5 file
  download  fetch the ota package
  start     write fip.bin, boot.emmc and rootfs_ext4.emmc, switch the partition
  rollback  switch back to the other rootfs
  recovery  set the factory reset flag
  clean     remove the downloaded files
```

The partitions are already in the layout, `rootfs` on `mmcblk0p3` and `rootfs_b` on `mmcblk0p4`, and the U-Boot environment carries `use_part_b`, `boot_cnt`, `boot_failed_limits` and `boot_rollback`. The build already produces the `ota.zip` package.

**What goes is `auto_download.sh`.** It runs in a loop, polls the GitHub release feed every 60 seconds, and installs whatever it finds. That is not an update mechanism, that is the camera updating itself from the internet with no way for the owner to know what it installs. The `upgrade.sh` script itself stays, it is the mechanism, and it is triggered by a person.

The decision is: the OTA path is kept and reachable, the automatic polling is removed. The trigger has to be something deliberate. Two candidates:

- A script the user runs over SSH.
- An HTTP endpoint, which needs an authenticated interface and brings in a web server that is not otherwise in the image.

The SSH route is the simpler one and it fits the minimal image. The plan step 5.2 decides this.

### Gimbal and PTZ: no

The gimbal is a separate product variant, not a feature of the camera:

```
OSHW-reCamera-Series/hardware/recamera-2002/products/gimbal/README.md
  Camera stack  C1-2002w + S101 OV5647
  Gimbal base   B401 CAN
  Motor interface  CAN, up to 1Mbps
  Motion        360 degree yaw, 180 degree pitch
```

The base board is the CAN base, and the motor protocol is a third-party supplier document. The vendor implementation of ONVIF has no PTZ support either, so PTZ would be four new ONVIF operations plus the CAN plumbing.

The consequence for the plan: the `gimbal` binary, the CAN base board support and the four PTZ operations are all out of scope. Plan step 7.9 is dropped.

### Sensor: GC2053

The target is the reCamera HQ PoE, and it ships with the `S401 GC2053` sensor board:

```
OSHW-reCamera-Series/hardware/recamera-2002/products/hq-poe/README.md
  Sensor            GC2053, 1920x1080 at 30fps
  Sensor board      S401 GC2053
```

The defconfig currently enables three sensors:

```
CONFIG_SENSOR_OV_OV5647=y        goes, that is the S101 of the Basic product
CONFIG_SENSOR_GCORE_GC2053=y      stays, this is the S101 of the HQ PoE
CONFIG_SENSOR_SMS_SC530AI_2L=y   goes, a third option
```

The ISP tuning binaries follow the sensor, they are copied to `/mnt/system/cfg/param` by `pack_cfg`. The plan keeps exactly the ones for the GC2053.

### WiFi and HaLow: no

The target is the HQ PoE, and its core board has no wireless module:

```
OSHW-reCamera-Series/hardware/recamera-2002/core/c1-2002/README.md
  C1-2002    No wireless module; exposes additional SDIO/UART signals to the base
  C1-2002w   Wi-Fi/Bluetooth module, onboard antenna, and I-PEX connector
```

Both radios go, the HaLow one and the Broadcom one, with their packages, their kernel modules and their device tree nodes.

What HaLow is, for the record: 802.11ah, the WiFi successor to 802.11ac, designed for long range and low power. It runs in the sub-GHz band, so the range is in kilometres rather than metres. It is the right radio for a camera that reports over a long link, and the wrong radio for a camera that hangs on a PoE switch.

The Ethernet driver is built into the kernel, not a module, so the network is unaffected:

```
external/build/boards/cv181x/sg2002_recamera_emmc/linux/cvitek_sg2002_recamera_emmc_defconfig
  CONFIG_STMMAC_ETH=y
  # CONFIG_DWMAC_GENERIC is not set
```

Plan step 3.3 has the list of everything that goes.

### Battery: no

The HQ PoE draws its power over the Ethernet cable, 802.3af PoE Mode A. There is no battery in the product.

The battery reading came from an ADC on I2C1, `adc@48` with `compatible = "ti,ads1015"` in the device tree. The node is deleted and `ti-ads1015.ko` is not loaded. The driver stays in the kernel, it is an upstream driver for the TI ADS1015 ADC and not vendor code, it is simply not used.

The reading also only ever went to the battery supervisor API, and the supervisor goes anyway.
