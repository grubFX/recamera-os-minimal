# Minimal reCamera OS

Goal: a small, understandable image for the Seeed reCamera HQ PoE (SG2002 / CV181X). Kept:

- Camera: sensor, ISP, video encoding, RTSP
- ONVIF, so the camera shows up in an NVR or VMS on its own
- SSH
- Ethernet, the camera is powered over PoE
- NTP

Removed:

- Node-RED, dashboard, the MQTT broker
- The sscma app layer (inference, supervisor, device manager)
- Avahi, ttyd, dnsmasq, Bluetooth
- The whole wireless stack, WiFi and HaLow
- The battery sensor, the camera has no battery
- The prebuilt `reCamera.zip` blob

## What the upstream image is made of

The upstream `sg2002_recamera_emmc` build is Buildroot 2021.05 (Sophgo fork) plus a set of external packages. Everything that ends up in the image comes from one of these places.

### Vendor parts that have to stay

| Part | Source | Why it stays |
|---|---|---|
| Kernel | `linux_5.10` (Sophgo fork) | Genuine upstream Linux 5.10.4 with three vendor commits on top. The camera drivers are not in the kernel at all, they live out of tree in `osdrv` and are written against the 5.10 API. See [submodule-review.md](./submodule-review.md). |
| Bootloader | `u-boot-2021.10`, `fsbl`, `opensbi` | Boot chain of the SoC. All three are upstream with a small vendor delta. |
| SDK | `osdrv`, `cvibuilder`, `cvikernel`, `cvimath`, `ive`, `cvi_mpi` | The video pipeline, the ISP and the encoder. All source, no blobs. |
| RTSP | `cvi_rtsp` | The RTSP server. Source. |
| Init | `ramdisk` overlay | The overlayfs setup on the userdata partition. |

None of these are patches on top of upstream Linux. They are the vendor tree, and they cannot be removed without losing the camera. The kernel is not old because nobody cares. The camera drivers in `osdrv` use `class_create(THIS_MODULE, name)`, which was removed in kernel 6.4, and the version guards in the sources stop at 5.10. A newer kernel exists for the SoC, but not for the camera. Upstream Linux 5.10 is still a maintained longterm release, the fork gets the weekly stable releases. The kernel is behind, not abandoned. What a port to 6.4 or 7.x would cost is in [kernel-upgrade.md](./kernel-upgrade.md).

### Parts that go

| Part | What it is | Why it goes |
|---|---|---|
| `reCamera` package | Downloads a prebuilt `reCamera.zip` from `sscma-example-sg200x` and copies its install tree into the target | A binary blob of unknown content. The source branch no longer exists upstream, the package is already broken. |
| `sscma-supervisor` | The REST API on port 80, built with libhv | Only needed for the web UI and the device manager. It also ships its own rootfs and starts the broker. |
| `sscma-node` | Wraps the TPU inference, pulls in host-nodejs and node-red | Only needed for the AI features. |
| `node-red` + dashboard | The flow editor and dashboard | Not wanted in a minimal image. |
| `mosquitto` | Broker on 127.0.0.1 | Only used by the node-red and sscma stack. |
| `avahi`, `dnsmasq`, `ttyd` | mDNS, DNS and the web terminal | Not needed. |
| `bt-init`, `bluez5_utils` | Bluetooth init for the BCM chip | The target has no radio at all, see below. |
| `wpa_supplicant`, `wpa_supplicant_s1g`, `hostapd` | The wireless supervisors | No radio in the image. |
| `iw`, `wireless_tools`, `wireless_regdb` | The wireless tools | No radio in the image. |
| `morse_cli` | The HaLow CLI | The HaLow chip is not on the board. |
| The wireless kernel modules | `brcmfmac.ko`, `dot11ah.ko`, `morse.ko` and their helpers | No radio in the image. |
| The battery driver | `ti-ads1015.ko` and the `adc@48` device tree node | The camera is powered over PoE, there is no battery. |
| `opencv4`, `opencv4-contrib` | Only used by the sscma stack | Goes with it. |
| FreeRTOS stack | `freertos`, `FreeRTOS-Kernel`, `Lab-Project-FreeRTOS-POSIX` | Runs on the second core, nothing uses it. The forks are two years behind upstream. |
| TPU stack | `cviruntime`, `cvikernel`, `cvimath`, `cvibuilder`, `cnpy`, `tdl_sdk`, `flatbuffers` | The AI accelerator SDK. A camera does not need it. |
| `live555.tar.gz` blob | Prebuilt live555 libraries | The headers are unmodified upstream, but the four archives are compiled objects built with the vendor toolchain and without source. Live555 is LGPL-3.0, build it from source. |

### What comes in that was not in the upstream image

| Part | What it is | Why it comes in |
|---|---|---|
| `onvif_simple_server` | The ONVIF server | The Profile T services. The vendor implementation is a Profile S device, Media 1 with plaintext password over plain HTTP. `onvif_simple_server` has the Media 2, imaging and event services already. It is GPL-3.0, which is the open question in [onvif.md](./onvif.md). |
| `lighttpd` with OpenSSL | The web server in front of the ONVIF CGI | Profile T requires HTTPS. lighttpd 1.4.59 is in the upstream Buildroot tree with the `BR2_PACKAGE_LIGHTTPD_OPENSSL` option, and the CGI interface of `onvif_simple_server` is the standard way to run it behind TLS. |
| `acme.sh` | The ACME client for the certificate | The camera gets a certificate it can renew on its own, without a port open on the router. POSIX shell, it needs `curl` and `openssl`, both already in the image. |
| `acme-provider` | The script that picks the DNS provider | The choice is in the overlay, with all 205 providers that `acme.sh` supports and an interactive `dialog` menu. The provider and its credentials go into `/etc/acme.sh/provider.conf`. |
| `dialog` | The menu library for the provider selection | It is in the upstream Buildroot tree, LGPL-2.1. |
| `openssh` 10.6p2 | The SSH server, bumped from 8.6p1 | CVE-2026-123158, the musl authentication bypass. This image has all three conditions: OpenSSH before 10.6p2, musl, and no PAM. See [requirements.md](./requirements.md). |

### The wireless stack: no radio at all

The target is the reCamera HQ PoE. Its core board, the `C1-2002`, has no wireless module:

```
OSHW-reCamera-Series/hardware/recamera-2002/core/c1-2002/README.md
  C1-2002    No wireless module; exposes additional SDIO/UART signals to the base
  C1-2002w   Wi-Fi/Bluetooth module, onboard antenna, and I-PEX connector
```

So both radios go, together with their packages, their kernel modules and their device tree nodes:

| Radio | Standard | Kernel modules | Packages |
|---|---|---|---|
| Morse mm610x | 802.11ah, HaLow, sub-GHz | `dot11ah.ko`, `morse.ko`, `mac80211.ko`, `libarc4.ko`, `ctr.ko`, `ccm.ko`, `gcm.ko`, `crc7.ko` | `wpa_supplicant_s1g`, `morse_cli` |
| Broadcom BCM43012 | 802.11ac, 2.4 and 5 GHz | `brcmfmac.ko`, `brcmutil.ko`, `cfg80211.ko` | `wpa_supplicant`, `hostapd`, `iw`, `wireless_tools` |

Bluetooth goes with it, `bt-init` and `bluez5_utils`.

The vendor kernel builds the wireless frame itself in, so the board defconfig has to turn the whole subtree off. The vendor tree defaults `CONFIG_WLAN`, `CONFIG_CFG80211`, `CONFIG_MAC80211` and every `CONFIG_WLAN_VENDOR_*` to `y`, so switching off only the radio chips is not enough, the frame comes back with them:

```
external/build/boards/cv181x/sg2002_recamera_emmc/linux/cvitek_sg2002_recamera_emmc_defconfig
  # CONFIG_WLAN is not set
  # CONFIG_CFG80211 is not set
  # CONFIG_MAC80211 is not set
  # CONFIG_RFKILL is not set
  # CONFIG_WLAN_VENDOR_REALTEK is not set
  ...
  # CONFIG_CVI_WIFI_PIN is not set
```

`CONFIG_CVI_WIFI_PIN` is the driver that hands out the GPIO of the wifi power and wakeup pin. Without a radio there is no pin to hand out.

The wifi userspace package goes with it. The vendor keeps it in a separate
package that the board defconfig switches on:

```
external/build/boards/cv181x/sg2002_recamera_emmc/sg2002_recamera_emmc_defconfig
  # CONFIG_TARGET_PACKAGE_WIFI is not set
```

It brings `wpa_supplicant`, `hostapd` and the matching configuration files
in `/etc`. The Bluetooth package and the vendor wifi chip packages are off
already.

The configuration files need a post-build script to get rid of them.
Buildroot copies the root filesystem overlay into the target on every
build and does not remove files from it, so the ones an earlier build
installed stay there forever:

```
external/buildroot/configs/cvitek_CV181X_musl_riscv64_defconfig
  BR2_ROOTFS_POST_BUILD_SCRIPT="board/cvitek/CV181X/post-build.sh"
  BR2_ROOTFS_POST_SCRIPT_ARGS="board/cvitek/CV181X/overlay"
```

What HaLow is, for the record: 802.11ah, the WiFi successor to 802.11ac, designed for long range and low power. It runs in the sub-GHz band, so the range is in kilometres rather than metres. It is the right radio for a camera that reports over a long link, and the wrong radio for a camera that hangs on a PoE switch.

The network is Ethernet, and the Ethernet driver is built into the kernel, not a module:

```
external/build/boards/cv181x/sg2002_recamera_emmc/linux/cvitek_sg2002_recamera_emmc_defconfig
  CONFIG_STMMAC_ETH=y
  # CONFIG_DWMAC_GENERIC is not set
```

So the camera keeps its network with a smaller image. The detail is in [requirements.md](./requirements.md), requirement 9, and in [plan.md](./plan.md), step 3.3.

### The battery: none

The HQ PoE draws its power over the Ethernet cable, 802.3af PoE Mode A. There is no battery in the product.

The battery reading came from an ADC on I2C1, the `adc@48` node with `compatible = "ti,ads1015"` in the device tree. The node is deleted and `ti-ads1015.ko` is not loaded. The driver stays in the kernel, it is an upstream driver for the TI ADS1015 ADC and not vendor code, it is simply not used.

### The auto update

`auto_download.sh` polls the GitHub release feed of `reCamera-OS` every 60 seconds and installs whatever it finds. `S99user` starts it through `/mnt/system/auto.sh`, the same script that starts the vendor application. Both go. A camera that installs new firmware from the internet on its own is not a normal Linux system, and it is also the path that pulls the prebuilt `reCamera.zip` content into the image.

**Decision: the OTA path stays, the automatic polling goes.** The `upgrade.sh` script itself is kept, it has an A/B partition layout with a rollback and the build already produces the `ota.zip` package. The update is triggered by a person over SSH, not by a loop in the background. The reason in one line: an update mechanism is worth having, a camera that rewrites its own root filesystem from the internet without telling anyone is not.

The detail that matters: the download URL in `upgrade.sh` points at the vendor release feed. For the minimal image it has to point at the fork, otherwise the camera installs the vendor image over the minimal one.

### The scope, decided

| Question | Decision |
|---|---|
| OTA update | yes, with the automatic polling removed |
| Gimbal and PTZ | no |
| Sensor | GC2053 |
| Snapshot | yes |
| WiFi and HaLow | no |
| Battery | no, the camera is powered over PoE |

The reasoning behind each one is in [requirements.md](./requirements.md), requirement 9, and in full in [plan.md](./plan.md).

## How the image is put together

The build is driven by `external/configs/sg2002_recamera_emmc_defconfig`. It picks the chip, the board, the DDR config, the sensor and a set of packages. The external packages live in `external/br2-external/`. The `Config.in` of each package decides whether it is in the image, and the `.mk` describes how it is built. The `external/br2-external/Config.in` lists the packages that Buildroot knows about. Two kinds of packages:

- `sscma-supervisor`, `sscma-node`, `bt-init`, `morse_cli`, `wpa_supplicant_s1g`
build from the `sscma-example-sg200x` git repo
- `reCamera` unpacks a prebuilt zip

### Which packages are in the image

This is the mechanism that decides it. The external packages are not listed in the buildroot defconfig, they are enabled by their own `Config.in` default:

| Package | Default | In the minimal image |
|---|---|---|
| `bt-init` | `default y` | no, no radio and no Bluetooth |
| `libhv` | `default y` | yes, the ONVIF daemon needs it |
| `libxcrypt-dev` | none | no |
| `morse_cli` | `default y` | no, the HaLow chip is not on the board |
| `opencv4` | none | no |
| `opencv4-contrib` | none | no |
| `reCamera` | `default n` | no |
| `sscma-node` | `default y` | no |
| `sscma-supervisor` | `default y` | no |
| `wpa_supplicant_s1g` | `default y` | no, the HaLow chip is not on the board |

So the trimming is done by flipping the `default` in the `Config.in` of the minimal external tree, not by editing the buildroot defconfig.

Two side effects to know about. `sscma-node` selects `mosquitto`, `libhv`, `alsa-lib` and `alsa-utils` in its `Config.in`, so dropping it drops those as well. And `libhv` has to stay even though `sscma-node` goes, because the ONVIF daemon uses it.

The Buildroot packages that go with the wireless decision are set in the buildroot defconfig, because they are normal Buildroot packages:

```
external/buildroot/configs/cvitek_CV181X_musl_riscv64_defconfig
  BR2_PACKAGE_WPA_SUPPLICANT=y            goes
  BR2_PACKAGE_HOSTAPD=y                   goes
  BR2_PACKAGE_IW=y                        goes
  BR2_PACKAGE_WIRELESS_TOOLS=y            goes
  BR2_PACKAGE_WIRELESS_REGDB=y            goes
  BR2_PACKAGE_BLUEZ5_UTILS=y              goes
```

The buildroot defconfig itself is `external/buildroot/configs/cvitek_CV181X_musl_riscv64_defconfig`, 572 lines with 115 enabled packages. It is derived from the chip and the SDK version, not from the project:

```
build/envsetup_soc.sh:882
  export BR_DEFCONFIG=${BR_BOARD}_defconfig
```

The init scripts come from two places: the packages copy their own rootfs into the target, and `external/ramdisk/rootfs/overlay/` holds the boot overlay. The overlay sets up the writable root: `/bin`, `/etc`, `/home`, `/lib`, `/opt`, `/root`, `/sbin`, `/usr` and `/var` are mounted as overlayfs with the lower layer in the read only rootfs and the upper layer in the userdata partition. That is also where the factory reset and the OTA update live.

## The kernel

The kernel is `sophgo/linux_5.10`. It is worth being precise about what that means, because the vendor tree is not the same thing as a kernel with unknown additions. The history of the `sg200x-dev` branch:

```
b1313fe517  2020-12-30  Greg Kroah-Hartman   Linux 5.10.4
b4ca5efcaf  2024-02-14  sophgo-forum-service linux porting cvitek asic chips.
72ef337123  2024-02-14  sophgo-forum-service [fea] Init sg200x-dev branch.
```

Everything below the first entry is upstream Linux by the upstream authors. Above it there are three Sophgo commits and then weekly stable releases. The porting commit adds the CV181X device trees and the clock, DMA, pinctrl and sound drivers. The changes to `arch/riscv/` are backports from upstream v5.12 and v5.15, verified by diffing against the upstream releases. The camera drivers are not in the kernel. They are in `osdrv/interdrv/` and get built as out of tree modules. That is also why the kernel stays at 5.10: the drivers use the two argument `class_create()`, which was removed in kernel 6.4, and the version guards in the sources stop at 5.10. A newer kernel exists for the SoC. `sophgo/linux-riscv` is at 6.18 and has the SG2002 support. But it has the clock, plic, sdhci and pinctrl, and no CVI video drivers. Mainline has the same. There is no newer kernel with this camera in it. The full evidence is in [submodule-review.md](./submodule-review.md).

## Build

The build goes through the GitHub workflow, not through Docker.

```
.github/workflows/main.yml
  runs-on: ubuntu-26.04
  run: make ${{ env.TARGET }}
```

The workflow installs the build dependencies with apt and calls `make` directly. The riscv64-musl toolchain and the ccache directory are cached between runs, so a rebuild only compiles what changed.

There is no matrix. The only target that exists is `sg2002_recamera_emmc`, and `sg2002_recamera_sd` was removed earlier. The SD board is `sg2002_xiao_sd` and is not built here.

The workflow runs on a push to `develop`, on a tag push and on a manual dispatch. A tag push also creates the GitHub release, with the matching section of `CHANGELOG.md` as the body.

The repository only allows actions that GitHub itself made. That rules out `softprops/action-gh-release`, so the release is made with the `gh` CLI, which is on the runner image.

> The runner is `ubuntu-26.04`. The Actions all run on `node24`, which is the
> Node.js version of that image.

Locally, the Docker daemon does not run on this machine and systemd is offline, so `docker_build.sh` does not work here. The workflow does.

Output lands in `output/sg2002_recamera_emmc/install/soc_sg2002_recamera_emmc/`.

### Host tools that the distributions do not ship

The build runs on two distributions: Debian 13 (trixie) in the devcontainer
and Ubuntu 26.04 (resolute) on the CI runner. Both dropped PCRE1 and keep
`sfdisk` in a separate package, so a few tools have to be brought in by hand.

| Tool | Why | Where it comes from |
|---|---|---|
| `make_ext4fs` | Packs the `data`, `system` and `rootfs` partitions | Prebuilt in `build/tools/common/prebuild/`. It needs `libpcre.so.3`, so `libpcre3` has to be installed. Debian 13 dropped PCRE1, the package is taken from the Debian pool by the devcontainer `Dockerfile`. Ubuntu has the same gap, the workflow takes the package from the Ubuntu pool. The pool package is the same on every release and only needs libc, so one URL works for both. |
| `resize2fs` | Shrinks the ext4 image to its minimum size | `e2fsprogs`, which is in the Debian archive. |
| `sfdisk` | Writes the partition table of the SD card images | The `fdisk` package, which is separate from `util-linux` on Debian 13. |
| `mkfs.vfat` | Formats the boot partition of the SD card images | `dosfstools`. |

The devcontainer `Dockerfile` installs all of them, so a fresh container
builds without manual steps. The workflow installs them with apt.

> The two SD card scripts report "ok" whatever happens. Without `sfdisk`
> and `mkfs.vfat` they printed "command not found" and carried on, and
> the recovery image and the sd_compat image came out as a file of
> nothing but zero bytes. The scripts check their exit codes now.

### Package versions that the board pins

Two packages in the Buildroot tree were updated because the newer versions
of their dependents need them:

| Package | Version | Why |
|---|---|---|
| `util-linux` | 2.36.2 | The Buildroot tree pins 2.36.2. It needs a patch for `<sys/pidfd.h>`, because the host glibc has the header and util-linux 2.36.2 does not know about it. The patch is in `external/buildroot/package/util-linux/`. |
| `libubootenv` | v0.3.8 | `swupdate` 2026.05.1 calls `libuboot_read_config_ext()`, `libuboot_get_namespace()` and `libuboot_namespace_from_dt()`. The pinned commit only had `libuboot_read_config()` and `libuboot_getname()`, so swupdate did not link. The overlay is in `external/buildroot/package/libubootenv/`. |

### The name of the root filesystem image

The root filesystem is called `rootfs_ext4.emmc` everywhere in the board
overlay: in the partition XML, in the two SD card scripts, in the
`sw-description` of the OTA update and in the `upgrade.sh` that runs on the
device. The build system however produced the image as `rootfs.emmc`.

The vendor renamed its images in commit `46c6a37` ("build: weekly rls
2025.12.17") and updated the partition XMLs that ship with it. The board
overlay predates that rename, so the two sides disagreed about the name of
the file and nothing reconciled them.

The mismatch failed silently, in three places at once:

| Consumer | What it does | Result |
|---|---|---|
| `raw2cimg.py` | Compares the file name it is called with against the partition name in the XML and packs only on a match | The root filesystem was left out of the flash image |
| `mk_package.py` | Skips every partition whose file is missing | The `upgrade.zip` contained no root filesystem |
| `gen_swu` in `external/build.sh` | Builds the `.swu` from the file list of the `sw-description` | The `.swu` was 2 KB and held only the description |

`external/build/patches/0002-build-name-the-root-filesystem-image-rootfs_ext4.patch`
renames the image in the build system, so that all six consumers agree on
one name.

> A symlink from `rootfs.emmc` to `rootfs_ext4.emmc` is not enough. The
> packers compare the file *name*, and `cpio` archives a symlink as a link
> instead of its contents, so the `.swu` would still be empty.

