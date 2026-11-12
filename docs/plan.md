# Plan: minimal reCamera OS

Every step has a goal, a concrete change and a way to check the result. The check is always a build, never the camera. The submodule review in [submodule-review.md](./submodule-review.md) is the evidence for the decisions below.

## The target

The reCamera HQ PoE. The SG2002 with the plain `C1-2002` core board and the `B301 PoE` base board.

```
OSHW-reCamera-Series/hardware/recamera-2002/products/hq-poe/README.md
  SoC / memory      SG2002, 256MB
  Sensor            GC2053, 1920x1080 at 30fps
  Lens              Replaceable M12, default FOV about 90 degrees
  Base              B301 PoE
  Sensor board      S401 GC2053
  Network / power   100Mbps Ethernet, 802.3af PoE Mode A
  Expansion         UART, debug, and three GPIOs through the six-pin connector
```

That fixes the scope. The core board has no wireless module, so there is no WiFi and no HaLow. The camera is powered over the cable, so there is no battery. The product ships with the `S401 GC2053`, so that is the sensor.

## The scope decisions

These are decided. The steps below carry them inline with a `**Decision:**` marker.

| Question | Decision | Step |
|---|---|---|
| OTA update | yes, with the automatic polling removed | 5.2 |
| Gimbal | no | 7.11, dropped |
| PTZ | no, it comes with the gimbal | 7.11, dropped |
| Sensor | GC2053 | 3.9 |
| Snapshot | yes | 7.11 |
| WiFi | no | 3.3 |
| HaLow | no | 3.3 |
| Battery | no, the camera is powered over PoE | 3.3, 5.4 |
| ONVIF events | no, without the AI stack there is no motion detection | 7, not in scope |
| ONVIF profile | **T**, which means HTTPS and H.265 | 7 |
| SSH password authentication | no, key authentication only | 4.4 |

The Docker daemon does not matter, the build goes through CI. The ONVIF port is 8899, the vendor default, and it does not collide with anything. The crypto library for ONVIF is OpenSSL, which is already in the image.

Two questions are still open, they are at the end of this document.

## Baseline

Build the upstream image first. Everything after that is compared against it.

```bash
./docker_build.sh sg2002_recamera_emmc
```

Result: `output/sg2002_recamera_emmc/install/soc_sg2002_recamera_emmc/`

### Step 0.1: Baseline build

| | |
|---|---|
| Goal | Know that the upstream build works before changing anything. |
| Change | None. |
| Check | The build finishes and the zip files exist. |
| Risk | The build needs Docker and about 30 GB of disk. |

The build environment on this machine:

| | |
|---|---|
| Docker client | 29.7.2, installed. |
| Docker daemon | Not running. `/var/run/docker.sock` does not exist. |
| systemd | `offline`. `systemctl start docker` is not possible. |
| Rootless Docker | `dockerd-rootless.sh`, `rootlesskit` and `slirp4netns` are all present, and `XDG_RUNTIME_DIR` is set. |
| Disk | The workspace sits on an ext4 partition with 440 GB free. |
| Host toolchain | Incomplete. `dtc`, `squashfs-tools`, `flex`, `bison`, `mtools` and `libssl-dev` are missing, and the host has gcc 15 where the build expects gcc 11. |
| Conclusion | The build goes through CI, or in the devcontainer. |

### The build path is CI, not Docker

The GitHub workflow builds without Docker at all. It runs on `ubuntu-24.04`, installs the build dependencies with apt, and calls `make <target>` directly. The riscv64-musl toolchain and the ccache directory are cached between runs.

```
.github/workflows/main.yml
  runs-on: ubuntu-24.04
  run: make ${{ matrix.target }}
```

This was found while planning and it changes the setup. The workflow needs two changes to build the minimal target:

- A matrix entry for the new target.
- A trigger on `push` to `develop`, so a build runs on every commit instead of only on a tag.

The workflow currently only runs on a tag push or a manual dispatch, and it reads the CHANGELOG to decide what to build. For the minimal target the CHANGELOG entry has to exist under the target name, same as the vendor targets.

Two other things the CI gives for free:

- The Node.js build is the expensive part. The comment in the workflow says "V8/nodejs compile alone needs ~4.5h on a 4-core runner". The minimal image has no Node.js, so the build is much faster.
- The toolchain cache is keyed on `riscv64-musl-gcc-ubuntu-24.04-2026.10.21` and does not depend on the target, so the minimal build reuses it.

### The devcontainer is the local build path

The CI stays the reference, but a local build is now possible in the devcontainer. It needed three things that were not there:

| Missing | What it does | Where it comes from |
|---|---|---|
| The cvitec riscv64 musl toolchain | The cross compiler for the target | The `host-tools` submodule, cloned by the `postCreateCommand` |
| `xz-utils` | To unpack the toolchain | A package in the image |

The base image is **Debian 13 (trixie)**. The packages are cross-compiled, but the host tools that Buildroot builds itself are compiled against the host libc. util-linux 2.41.3 and fakeroot 1.37.2 need a current glibc: Debian 12 has glibc 2.36 and does not build them, Debian 13 has glibc 2.41.

```
$ docker run --rm buildpack-deps:trixie-curl ldd --version | head -1
ldd (Debian GLIBC 2.41-12+deb13u4) 2.41
```

NodeSource does not publish a trixie repository, so the container uses the distro `nodejs` package. That is not a problem for the build: the Node.js in the camera image is cross-compiled by `nodejs.mk` from source, and the npm that installs node-red is the `host-nodejs` package that Buildroot builds itself.

```
external/buildroot/package/nodejs/nodejs.mk
NPM = $(NODEJS_BIN_ENV) $(HOST_DIR)/bin/npm
```

### Step 0.2: Baseline inventory

Unpack the rootfs of the built image and list what is in it.

| | |
|---|---|
| Goal | A reference list of everything in the upstream image. |
| Change | None, just a script that lists the packages. |
| Check | The list is stored next to the build output. |
| Note | This list is the checklist for the trimming steps later. |

## Step 1: Understand what is actually needed

Before removing anything, find out which piece does what. The camera does not work through Node-RED or the supervisor, it works through the CVI pipeline: sensor, MIPI, VI, VPSS, encoder, RTSP.

### Step 1.1: Map the camera pipeline

| | |
|---|---|
| Goal | Know the chain from sensor to RTSP stream. |
| Change | Documentation only. |
| Check | The chain is written down with the file that implements each link. |
| Result | `osdrv/interdrv/cif` (MIPI RX), `snsr_i2c` (sensor), `vi`, `vpss`, `cvi_vc_drv` (encoder), `cvi_rtsp` (server). |

### Step 1.2: Find out what the blob does

The `reCamera` buildroot package downloads a zip and copies its install tree into the target. Before dropping it, check what is in it.

| | |
|---|---|
| Goal | Know whether the blob carries something the camera needs. |
| Change | Documentation only. |
| Check | The contents of the blob are listed. |
| Finding | The blob pulls from a `reCamera` branch of `sscma-example-sg200x` that no longer exists upstream. The package is already broken. The blob carries the web UI and the device manager, not the camera. |

## Step 2: A separate buildroot tree for the minimal image

The upstream build mixes the camera and the app stack in one external tree. The minimal image gets its own tree so the upstream build stays untouched and can still be produced for comparison.

### How the build is wired

This was traced through the build scripts, because it decides what the minimal tree has to look like.

```
Makefile                       the target list comes from external/configs/*_defconfig
external/build.sh              sets BR2_EXTERNAL, sources setenv.sh, calls defconfig
external/setenv.sh             copies the SDK, applies the patches, sources envsetup_soc.sh
build/envsetup_soc.sh          sets BR_DEFCONFIG and BR_OVERLAY_DIR
build/Makefile                 make -C buildroot-2021.05 <BR_DEFCONFIG>
```

Two things follow from this:

- `BR2_EXTERNAL` is a single directory, set in `external/build.sh`. A second external tree needs its own copy of that script, or a parameter.
- The buildroot defconfig is always `cvitek_CV181X_musl_riscv64_defconfig`. It is derived from the chip and the SDK version, not from the project:

```
build/envsetup_soc.sh:882
  export BR_DEFCONFIG=${BR_BOARD}_defconfig
```

So the package selection for the minimal image cannot live in a new buildroot defconfig file without changing that line. The practical way is to keep the buildroot defconfig and let the external tree override the packages.

### Where the external packages are enabled

The external packages are not listed in the buildroot defconfig. They are enabled by their own `Config.in` defaults:

```
external/br2-external/bt-init/Config.in       default y
external/br2-external/libhv/Config.in          default y
external/br2-external/morse_cli/Config.in      default y
external/br2-external/sscma-node/Config.in     default y
external/br2-external/sscma-supervisor/Config.in  default y
external/br2-external/reCamera/Config.in       default n
```

That is the mechanism. A package with `default y` is built unless the defconfig says otherwise, and the defconfig does not mention any of them.

For the minimal tree this is the lever. Every package that should not be in the image gets `default n`, and the ones that stay get `default y` without touching the buildroot defconfig.

| | |
|---|---|
| Note | `sscma-node` selects `mosquitto`, `libhv`, `alsa-lib` and `alsa-utils` in its `Config.in`. Dropping it drops those too, which is what Step 3 wants. |
| Note | `opencv4` has no `default` line, so it is off unless something selects it. |

### Step 2.1: New external tree

| | |
|---|---|
| Goal | A buildroot external tree with only the minimal image. |
| Change | New directory `external/br2-external-minimal/` with its own `Config.in`, `external.mk` and `external.desc`. |
| Check | Buildroot accepts `BR2_EXTERNAL` pointing at it. |
| Note | The name of the tree decides the name of the buildroot output directory. |

### Step 2.2: New defconfig

| | |
|---|---|
| Goal | A defconfig that describes the minimal image. |
| Change | New file `external/configs/sg2002_recamera_minimal_defconfig`, based on the upstream one. |
| Check | `make sg2002_recamera_minimal` picks up the new target. The Makefile derives the targets from the files in `external/configs/`. |

The defconfig starts as a copy of the upstream one. The trimming happens in the packages, not in the defconfig, because most of the removed parts are not buildroot packages at all.

The upstream defconfig is 32 lines and sets the project level: the chip, the board, the DDR config, the cross compiler, the sensor, the storage type and the kernel. None of that changes for the minimal image, it is the same camera.

```
CONFIG_CHIP_sg2002=y
CONFIG_BOARD_recamera_emmc=y
CONFIG_CROSS_COMPILE="riscv64-unknown-linux-musl-"
CONFIG_SENSOR_GCORE_GC2053=y
CONFIG_STORAGE_TYPE_emmc=y
```

The packages are in the buildroot defconfig, 572 lines with 115 enabled packages. That is the file the trimming touches, not the project defconfig.

| | |
|---|---|
| Note | The board directory `external/build/boards/cv181x/sg2002_recamera_emmc/` holds the DTS, the partition table, the U-Boot config, the kernel config and the rootfs overlay. The minimal target needs its own directory there, or it reuses the existing one with a different overlay. |
| Check | `external/build/boards/cv181x/` currently has `sg2002_recamera_emmc`, `sg2002_recamera_sd` and `sg2002_xiao_sd`. A minimal target needs a fourth. |

### Step 2.3: Build the unmodified minimal target

| | |
|---|---|
| Goal | Prove the new target builds before anything is removed. |
| Change | Only the new defconfig and the new external tree, with the same package list as upstream. |
| Check | The build succeeds and the image has the same content as the baseline. |
| Note | This step is the safety net for everything that follows. |

## Step 3: Remove the app layer

This is where the image actually gets small. The parts below are the app stack: the web UI, the AI features, the flow editor. None of them are needed for a camera.

### Step 3.1: Drop the packages that carry the app layer

| | |
|---|---|
| Goal | No web UI, no AI, no flow editor in the image. |
| Change | In the minimal external tree: remove `reCamera`, `sscma-supervisor`, `sscma-node`, `opencv4`, `opencv4-contrib`, `libhv`, `morse_cli`. Set `BR2_PACKAGE_SSCMA_SUPERVISOR`, `BR2_PACKAGE_SSCMA_NODE`, `BR2_PACKAGE_RECAMERA` to `n`. |
| Check | The build succeeds. The inventory shows no supervisor, no node-red, no opencv. |

The supervisor is the one that matters most: it installs its own rootfs and starts the broker. Removing it takes the web UI, the device manager and the mosquitto broker with it.

### Step 3.2: Remove the infrastructure that only the app layer used

| | |
|---|---|
| Goal | A smaller image and fewer listening ports. |
| Change | Turn off `mosquitto`, `avahi`, `dnsmasq`, `ttyd` (`node-red-dashboard` websocket), `bluez5_utils`, `bt-init`. |
| Check | The inventory shows no mosquitto, no avahi, no ttyd. The build log has no error about a missing dependency. |
| Note | Two packages in the Buildroot fork carry patches for packages a camera does not need: `freetype` and `zlog`. They go with the packages. `package/busybox/busybox.config` stays, it defines what the shell in the image can do. |

### Step 3.3: Drop the wireless stack completely

| | |
|---|---|
| Goal | No radio in the image. The camera is on Ethernet. |
| Change | Remove the wireless kernel modules, the wireless packages and the wireless device tree nodes. See the list below. |
| Check | The init script loads no radio module. The image has no `wpa_supplicant`, no `hostapd` and no `iw`. The device tree has no `mm610x_sdio` and no `wifi_pin`. |
| Note | **Decision: no WiFi, no HaLow.** The target is the HQ PoE variant, which is the plain `C1-2002` core board. That board has no wireless module at all, the PoE base board connects over Ethernet. |

The camera gets its network over Ethernet, and Ethernet is independent of the radio:

```
external/build/boards/cv181x/sg2002_recamera_emmc/linux/cvitek_sg2002_recamera_emmc_defconfig
  CONFIG_STMMAC_ETH=y
  # CONFIG_DWMAC_GENERIC is not set
```

The Ethernet driver is built into the kernel, not a module. Removing the radio touches nothing of it. The `ethernet0` node at `ethernet@4070000` is in the base device tree and stays.

#### What goes

| Thing | Where |
|---|---|
| `brcmfmac.ko`, `brcmutil.ko`, `cfg80211.ko` | the kernel modules, loaded by `loadsystemko.sh` |
| `dot11ah.ko`, `morse.ko`, `mac80211.ko`, `libarc4.ko` | the HaLow radio, same script |
| `ctr.ko`, `ccm.ko`, `gcm.ko`, `crc7.ko` | the crypto helpers of the HaLow radio |
| `wpa_supplicant`, `wpa_supplicant_s1g`, `hostapd` | the Buildroot packages |
| `iw`, `wireless_tools`, `wireless_regdb` | the Buildroot packages |
| `bt-init`, `bluez5_utils` | the Buildroot packages |
| `morse_cli` | the external package, it is a HaLow tool |
| `mm610x_sdio` | the device tree node in the board dts |
| `wifi_pin` | the device tree node, the power gpio of the radio |
| `brcmfmac` firmware | the kernel config and the wifi section of the dts |

For the record, HaLow is 802.11ah, the WiFi successor to 802.11ac that was designed for long range and low power. It runs in the sub-GHz band, so the range is in kilometres rather than metres. It is the right radio for a camera that reports over a long link, and the wrong radio for a camera that hangs on a PoE switch.

#### The device tree

The board device tree activates the HaLow radio explicitly. That has to go, because the radio is not on the board:

```
external/build/boards/cv181x/sg2002_recamera_emmc/dts_riscv/sg2002_recamera_emmc.dts
  &sd {
      mm610x_sdio: mm610x-sdio {
          compatible = "morse,mm610x";
          reg = <2>;
          reset-gpios = <&portc 12 GPIO_ACTIVE_HIGH>;
          status = "okay";
      };
  };

  / {
      wifi_pin {
          compatible = "cvitek,wifi-pin";
          poweron-gpio = <&porta 30 GPIO_ACTIVE_HIGH>;
      };
  };
```

Both nodes are deleted, and the `sd` node keeps its other properties.

#### The gpio sharing resolves itself

This was the part that looked risky while the wireless stack was still in scope. With the radio gone it is simple:

```
external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/ko/loadsystemko.sh
  [ ! -e /dev/morse_io ] && [ ! -e /dev/mmcblk1 ] && {
      # gimbal
      [ -x /usr/bin/gimbal ] && { ... }
      # PoE
      ...
  }
```

The condition was "no HaLow radio and no SD card", and on the PoE variant both are true. So the PoE pinmux block runs, which is what this variant needs.

#### The SD card

The SD card stays a normal SD card. The `mm610x_sdio` node was on the same controller, and removing it does not change the controller:

```
  &sd {
      no-1-8-v;
      max-frequency = <50000000>;
      /delete-property/ no-sdio;
      /delete-property/ cap-sd-highspeed;
      /delete-property/ sd-uhs-sdr104;
  };
```

#### What stays

| Thing | Why |
|---|---|
| `CONFIG_STMMAC_ETH=y` | The Ethernet driver, built into the kernel. This is the network. |
| `dhcpcd`, `dnsmasq` | The DHCP client and the DNS forwarder. The camera gets its address over Ethernet. |
| The PoE pinmux block in `loadsystemko.sh` | Sets up the Ethernet pins on the B301 base board. |
| `ethernet0` in the base dts | The Ethernet hardware node. |

The `wifi_pin` power gpio is gone, which means the radio never gets powered. On a board without a radio that is correct.

### Step 3.4: Keep one SSH server

| | |
|---|---|
| Goal | SSH, but only one implementation. |
| Change | The upstream build has both: the defconfig selects dropbear, and `external/buildroot/configs/cvitek_CV181X_musl_riscv64_defconfig` sets `BR2_PACKAGE_OPENSSH=y` with client, server and key utils. Drop one. Dropbear is the smaller one. |
| Check | The image has exactly one sshd. It starts at boot and accepts the key. |
| Note | The init script lives in `/etc/init.d/S50sshd`, which comes from the buildroot overlay, not from the board rootfs. |

### Step 3.5: Keep NTP

| | |
|---|---|
| Goal | The clock is right after a power cycle. |
| Change | Keep `ntp` and `ntpd`. The config is in the overlay at `etc/ntp.conf`. |
| Check | NTP is in the inventory and the init script starts it. |
| Note | `openssl` is a dependency of `wpa_supplicant_s1g`, so it stays even if nothing else needs TLS. |

### Step 3.6: Drop FreeRTOS

| | |
|---|---|
| Goal | One core, one OS. The RTOS on the second core has no user. |
| Change | In the defconfig: `CONFIG_ENABLE_FREERTOS=n`, `CONFIG_ENABLE_RTOS_DUMP_PRINT=n`. Remove `cv181x_rtos_cmdqu.ko` from the module list. |
| Check | The inventory has no FreeRTOS. The build log has no RTOS target. |
| Note | The FreeRTOS forks are two years behind upstream. Dropping them also removes the oldest code in the image. |
| Blocker | `rtos_cmdqu` is used by `rgn` (region) and `fast_image`, both part of the video pipeline. Before dropping it, check whether the RTOS core carries work the Linux side depends on. If it does, this step needs a different approach. |

### Step 3.7: Build live555 from source

| | |
|---|---|
| Goal | No prebuilt binaries in the image. |
| Change | Enable `BR2_PACKAGE_LIVE555` with `BR2_STATIC_LIBS=y` in the minimal external tree. Point the `cvi_rtsp` build at the result instead of the tarball. |
| Check | The image contains the four live555 static libraries and they were built from the Buildroot package, not copied from `oss/`. |
| Note | `cvi_rtsp/build.sh` only downloads the tarball when `LIVE555_DIR` is empty. Set it and the download never happens. |
| Detail | `cvi_rtsp/Makefile.inc` expects four static archives under `$(LIVE555_DIR)/lib/` and the headers in four separate include directories. The Buildroot layout has the headers in one directory, so `LIVE555_INC` has to be adjusted. |
| Risk | If the paths do not line up, the `cvi_rtsp` build fails with a missing header. That is a build failure, not a silent problem. |

#### What the live555 blob actually is

The blob was checked against the upstream source. The result is good news with one caveat.

```
oss/oss_release_tarball/musl_riscv64/live555.tar.gz
  include/    181 headers
  lib/        4 static archives, 4.9 MB
  bin/        45 example binaries
```

The headers were compared file by file against the `rgaufman/live555` Git mirror, which is an unofficial but faithful mirror of the official source.

```
live.2020.04.24   175 of 181 headers byte identical
                   6 differ, 4 of them only in the version string
```

The six differences are the version files. They say `2020.07.21` instead of `2020.04.24`, so the blob is one release newer than the commit that was compared. The remaining two are `liveMedia.hh`, which is an include list, and `ProxyServerMediaSession.hh`.

**The headers are unmodified upstream Live555 code.** There is no injected code in them.

The caveat is the archives:

```
lib/libUsageEnvironment.a
  UsageEnvironment.o
  HashTable.o
  strDup.o
```

They contain compiled objects, not source. And the objects carry the build signature of the vendor toolchain:

```
GCC: (Xuantie-900 linux-5.10.4 musl gcc Toolchain V2.6.1 B-20220906) 10.2.0
```

So the blob is Live555 2020.07.21, compiled by Sophgo with their cross compiler. The source is identifiable and matches upstream, but the compiled artifacts cannot be verified byte by byte against a reference build without reproducing the vendor toolchain.

This is exactly what the hard requirement forbids, so the step stays. The Buildroot package builds the same version from source with a checked hash.

| | |
|---|---|
| Note | The Buildroot package in the tree is version 2021.05.03, not the 2020.07.21 the blob holds. `live555.hash` has the sha256, so the download is verified. The version difference is one release and the API used by `cvi_rtsp` did not change. |
| Check | `strings` on the object files shows the Xuantie compiler only for the blob build. The Buildroot build shows the riscv64-musl toolchain. |
| Detail | The `cvi_rtsp` service uses `ServerMediaSubsession` 43 times, `UsageEnvironment` 34 times, `ServerMediaSession` 20 times, `RTSPServer` 9 times, `BasicUsageEnvironment` 3 times and `Medium` 2 times. All of it is the stable server API. |

#### The live555 tarball is no longer downloadable

The official site does not serve the tarballs any more:

```
http://www.live555.com/liveMedia/public/live.2020.05.21.tar.gz   404
http://www.live555.com/liveMedia/public/live.2021.05.03.tar.gz   404
http://www.live555.com/liveMedia/public/live.2025.10.13.tar.gz   404
```

The homepage loads, but the `public/` directory does not. The Buildroot package points at that URL with an `md5` and a `sha256`, so the build would fail with a download error.

The Git mirror works and is the way to fix this:

```
https://github.com/rgaufman/live555
  LGPL-3.0, 872 stars, not archived, last push 2026-07-29
  mirror of the official source, tracks the upstream releases
```

The package has to switch from a tarball download to a Git clone with a pinned tag. The upstream release tags are in the history as "Version bump to YYYY.MM.DD" commits, not as Git tags, so the pin has to be a commit SHA.

| | |
|---|---|
| Change | Replace `LIVE555_SITE` and `LIVE555_SOURCE` with `LIVE555_SITE_METHOD = git`, a pinned `LIVE555_GIT_TAG`, and drop the tarball hash in favour of a `BR2_GLOBAL_HASH` or no hash for a pinned commit. |
| Check | The download step of the package succeeds and produces the four archives. |
| Note | The mirror history was verified to contain the 2020.04.24 and 2021.x version bumps, so the versions the vendor used are reachable. |
| Alternative | Keep the tarball and mirror it somewhere reachable. That needs a place to host it, the Git mirror avoids that. |

### Step 3.8: Drop the TPU stack

| | |
|---|---|
| Goal | No AI accelerator in a camera image. |
| Change | Remove `cviruntime`, `cvikernel`, `cvimath`, `cvibuilder`, `cnpy`, `tdl_sdk`, `flatbuffers` from the build. Remove `cv181x_tpu.ko` from the module list. |
| Check | The inventory has no TPU libraries. The image is smaller. |
| Note | `ive` stays, it is the image processing engine and not the AI one. |

### Step 3.9: Keep the ISP tuning for one sensor

| | |
|---|---|
| Goal | The sensor still produces a correct image. |
| Change | Keep `isp_tuning` and `CONFIG_SENSOR_GCORE_GC2053`. Remove `CONFIG_SENSOR_OV_OV5647` and `CONFIG_SENSOR_SMS_SC530AI_2L`. The tuning binaries are copied to `/mnt/system/cfg/param` by `pack_cfg` in `external/setenv.sh`. |
| Check | The param directory in the image contains the tuning files for the GC2053 and nothing for the other two sensors. |
| Note | **Decision: GC2053.** The target is the HQ PoE, which ships with the `S401 GC2053` sensor board. The OV5647 is the `S101` of the Basic product, the SC530AI is a third option. Each sensor needs its own ISP tuning, and the ones that are not used are dead weight in the image. |
| Note | The sensor compatibility list in the hardware repository is a driver level snapshot. It lists every driver the SG2002 kernel configuration supports, which is more than the boards that exist. |

## Step 4: Check the packages that carry the attack surface

Buildroot 2021.05 is end of life, the upstream branch stopped in June 2021. The minimal image has three packages that matter for a network reachable device.

### Step 4.1: Check the versions

| | |
|---|---|
| Goal | Know which versions of dropbear, busybox and openssl are in the image. |
| Change | None, read the versions from the built image. |
| Check | The versions are written down next to the upstream advisories. |
| Note | Drop one of the two SSH servers first, that removes one of the three. |
| Note | openssl stays, `wpa_supplicant_s1g` needs it for WPA2 and WPA3. |

### Step 4.2: Bump what needs bumping

| | |
|---|---|
| Goal | No known CVE in the packages that a network can reach. |
| Change | If a version is too old, bump that one package in the Buildroot fork. A newer Buildroot is not an option, the `buildroot-2023.11` branch in the same repo has no CV181X support. |
| Check | The new version is in the image and the build still works. |

### Step 4.3: OpenSSH, and CVE-2026-123158

**This is not a routine bump. This image is affected by an actively exploited authentication bypass.**

The conditions in the advisory are all met:

| Condition | This image |
|---|---|
| OpenSSH before 10.6p2 | **8.6p1** |
| musl libc | yes, `BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y` |
| PAM disabled | yes, `BR2_PACKAGE_LINUX_PAM` is not set |

The consequence, from the CVE record:

> For some configurations of accounts, any password between 256 and 1024 characters succeeds.

Remote, unauthenticated, and in the CISA Known Exploited Vulnerabilities catalog since 9 November 2026.

| | |
|---|---|
| Goal | The SSH server is on a version without the authentication bypass. |
| Change | The `openssh` package in `external/buildroot/package/openssh/` goes from 8.6p1 to 10.6p2. The upstream Buildroot is already there, so the `.mk` file is taken from upstream master and adapted to Buildroot 2021.05. |
| Check | The image has `sshd -V` reporting 10.6p2, and the build log has no configure error. |
| Hash | `sha256 9ae44872090cf2f06b3cf9ff147e7f16f309671340763ed2f99248398ae29d5b  openssh-10.6p2.tar.gz` |
| Note | The tarball hash is verified against the SHA256 that the release notes publish in base64. |

The upstream Buildroot 10.6p2 package needs three things that Buildroot 2021.05 does not have, and they have to be adapted:

| Upstream dependency | Status in 2021.05 | What to do |
|---|---|---|
| `BR2_PACKAGE_SYSTEMD_SYSUSERS` | missing | Use the `OPENSSH_USERS` fallback that is already in the 2021.05 package |
| `BR2_TOOLCHAIN_HAS_GCC_BUG_110934` | missing | Drop the condition, the bug is a GCC 14 issue and this toolchain is GCC 10.2 |
| `BR2_PACKAGE_LIBSELINUX` | missing | Drop the condition, SELinux is not in this image |

The server binaries also changed. OpenSSH 10.0 split the authentication phase out of `sshd-session` into a separate `sshd-auth` binary:

```
# upstream buildroot, package/openssh/openssh.mk
$(INSTALL) -D -m 0755 $(@D)/sshd-auth $(TARGET_DIR)/usr/libexec/sshd-auth
```

That binary has to be installed too, otherwise the server does not start.

### Step 4.4: Turn off the password authentication

| | |
|---|---|
| Goal | The camera is not reachable with a password, only with a key. |
| Change | In `external/buildroot/board/cvitek/CV181X/overlay/etc/ssh/sshd_config`, set `PasswordAuthentication no` and `PermitEmptyPasswords no`. `PermitRootLogin` goes from `yes` to `no`. |
| Check | `ssh -o PreferredAuthentications=password` fails, and key authentication works. |
| Detail | The overlay shipped `PermitRootLogin yes` with the password lines commented out, which means the default was "yes" for both. Root itself was not reachable, the Buildroot config sets `BR2_TARGET_ENABLE_ROOT_LOGIN=n`, but the `recamera` user has no password. |
| Note | This is the mitigation that removes the attack surface, independent of the version. A camera on a PoE network that is reachable from the internet should not have password authentication on at all. |

## Step 5: Trim the boot overlay

The overlay sets up the writable root. Some of its parts belong to the app layer. Two places hold the init scripts:

- `external/buildroot/board/cvitek/CV181X/overlay/etc/init.d/` has `S70hardware`,
`S80dnsmasq`, `S92node-red`, `S98ttyd` and `S99user`
- `external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/` has the boot
scripts: `auto.sh`, `auto_download.sh`, `rootfs_overlay.sh`, `upgrade.sh` and the usb networking scripts The `S99user` script sources `/mnt/system/auto.sh`, which starts the vendor application. That is the hook to the app layer.

### Step 5.1: Keep the overlay, drop the app hooks

| | |
|---|---|
| Goal | The writable root still works, without the OTA and factory reset of the app image. |
| Change | Keep `rootfs_overlay.sh` and `ko/loadsystemko.sh`. Remove `upgrade.sh` and the OTA block in `rootfs_overlay.sh` if OTA is not wanted. |
| Check | The boot log shows the overlay mounted and the kernel modules loaded. |
| Note | The factory reset is a safety feature. Keeping it is cheap and saves a bricked camera. |

### Step 5.2: Keep the OTA path, remove the automatic polling

| | |
|---|---|
| Goal | The camera can be updated in the field, but it does not pull new firmware from the internet behind your back. |
| Change | Keep `upgrade.sh` and the `ota.zip` package. Remove `auto_download.sh` and the call to it. |
| Check | The script is not in the image. Nothing reaches out to github.com at boot. The `upgrade.sh` script is still there and can be run by hand. |
| Note | `S99user` sources `/mnt/system/auto.sh`, and `auto.sh` is what starts the vendor application and the auto update. The app start has to go, the OTA path stays. |

**Decision: OTA yes.** The camera is reachable over the network, and a field update without taking it apart is worth the complexity.

The mechanism is already good. It has an A/B partition layout with a rollback, and the build already produces the package:

```
external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/upgrade.sh
  latest    resolve the newest release and write the md5 file
  download  fetch the ota package
  start     write fip.bin, boot.emmc and rootfs_ext4.emmc, switch the partition
  rollback  switch back to the other rootfs
  recovery  set the factory reset flag
  clean     remove the downloaded files
```

The partitions are in the layout already, `rootfs` on `mmcblk0p3` and `rootfs_b` on `mmcblk0p4`, and the U-Boot environment carries `use_part_b`, `boot_cnt`, `boot_failed_limits` and `boot_rollback`.

**What goes is the trigger.** `auto_download.sh` runs an endless loop, polls the release feed every 60 seconds and installs whatever it finds:

```
external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/auto_download.sh
  while true; do
      ...
      sleep $DEFAULT_SLEEP
  done
```

That is not an update mechanism. That is the camera rewriting its own root filesystem from the internet with no way for the owner to know what it installs.

**How the update is triggered instead.** A person runs it, over SSH:

```
upgrade.sh latest                       # resolve the newest release
upgrade.sh download                     # fetch the package
upgrade.sh start                        # write it and switch the partition
upgrade.sh rollback                     # switch back if it did not boot
```

The SSH route fits the minimal image, it needs no web server. An HTTP endpoint would need an authenticated interface and a web server that is not otherwise in the image.

| | |
|---|---|
| Detail | The download URL points at `https://github.com/Seeed-Studio/reCamera-OS/releases/latest`. For the minimal image that has to point at the fork, or the camera would install the vendor image over the minimal one. |
| Detail | `wget` is called with `--no-check-certificate` in the script. The md5sum is verified against the file, but the transport is not. The script is a candidate for a certificate fix. |
| Check | The image has `upgrade.sh`, it has `curl` and `wget`, and the `ota.zip` package is in the build output. |

### Step 5.3: Clean up the init scripts

| | |
|---|---|
| Goal | Only the services the minimal image needs start at boot. |
| Change | Remove `S80dnsmasq`, `S92node-red`, `S98ttyd` from the buildroot overlay. `S50nginx` and `S91mdev` are already in `init.d/disabled/`. |
| Check | The boot log shows the expected services and nothing else. |

### Step 5.4: Clean up the module list

| | |
|---|---|
| Goal | Only the modules the camera needs are loaded. |
| Change | In `loadsystemko.sh`: remove the TPU module (`cv181x_tpu.ko`), the audio modules, the radio modules, the battery module and the gimbal init. |
| Check | The boot log lists the expected modules and no errors. |
| Note | The module list also shows the hardware, and with the wireless and the battery gone it is short. |

The lines that go:

```
insmod /mnt/system/ko/cfg80211.ko
insmod /mnt/system/ko/brcmutil.ko
insmod /mnt/system/ko/brcmfmac.ko

insmod /mnt/system/ko/ctr.ko
insmod /mnt/system/ko/ccm.ko
insmod /mnt/system/ko/gcm.ko
insmod /mnt/system/ko/crc7.ko

insmod /mnt/system/ko/dot11ah.ko
insmod /mnt/system/ko/libarc4.ko
insmod /mnt/system/ko/mac80211.ko

insmod /mnt/system/ko/ti-ads1015.ko
```

The `ctr`, `ccm`, `gcm` and `crc7` modules belong to the HaLow radio, they are the crypto helpers it needs.

The `init_sd_pin` function and the `sleep 1` after it go as well, they only set up the SDIO pins for the HaLow chip. The `morse.ko` load carries the `country=$COUNTRY` argument from `/etc/recamera.conf/halow_country`, and that file goes too.

The battery module goes because there is no battery. The PoE variant takes its power over the Ethernet cable, so the ADC on I2C1 has nothing to measure:

```
external/build/boards/cv181x/sg2002_recamera_emmc/dts_riscv/sg2002_recamera_emmc.dts
  &i2c1 {
      adc@48 {
          compatible = "ti,ads1015";
          reg = <0x48>;
          ...
      };
  };
```

The `adc@48` node is deleted with it. The `ti-ads1015` driver itself is an upstream kernel driver for the TI ADS1015 ADC, it is generic and not part of the vendor code, so it stays in the kernel. It is simply not loaded.

The reading also only ever went to the battery supervisor API, and the supervisor goes anyway.

What stays in the module list is the video pipeline and the Ethernet:

```
insmod /mnt/system/ko/cv181x_sys.ko
insmod /mnt/system/ko/cv181x_base.ko
insmod /mnt/system/ko/cv181x_rtos_cmdqu.ko
insmod /mnt/system/ko/cv181x_fast_image.ko
insmod /mnt/system/ko/cvi_mipi_rx.ko
insmod /mnt/system/ko/snsr_i2c.ko
insmod /mnt/system/ko/cv181x_vi.ko vi_log_lv=1
insmod /mnt/system/ko/cv181x_vpss.ko vpss_log_lv=1
insmod /mnt/system/ko/cv181x_dwa.ko
insmod /mnt/system/ko/cv181x_vo.ko vo_log_lv=1
insmod /mnt/system/ko/cv181x_rgn.ko
insmod /mnt/system/ko/cv181x_clock_cooling.ko
insmod /mnt/system/ko/cv181x_vcodec.ko
insmod /mnt/system/ko/cv181x_jpeg.ko
insmod /mnt/system/ko/cvi_vc_driver.ko MaxVencChnNum=9 MaxVdecChnNum=9
insmod /mnt/system/ko/cv181x_ive.ko
```

## Step 6: The camera comes up

This is the first step where the result is visible.

### Step 6.1: The RTSP server starts

| | |
|---|---|
| Goal | A stream that a player can open. |
| Change | An init script that starts the RTSP server with a config for the sensor and one stream. |
| Check | The process is running and the config file is in the image. |
| Note | `cvi_rtsp` is not a Buildroot package and it does not build a server binary. It builds two libraries, `libcvi_rtsp.so` and `libcvi_rtsp_service.so`. The server class is `CVI_RTSP`, it inherits from the Live555 `RTSPServer`. |
| Note | `cvi_rtsp/example/rtsp_server_video.cpp` is a complete standalone server application, already in the repo. It initializes the sensor, the VI, the VPSS and the encoder and then serves the stream. This is the base for the minimal image. |
| Note | The build goes through `build_cvi_rtsp` in `external/setenv.sh` and lands in `${SYSTEM_OUT_DIR}/usr`, which is `/mnt/system/usr` at runtime. |
| Note | `cvi_rtsp/build.sh` uses `LIVE555_DIR` when it is set and only downloads the tarball otherwise. Step 3.7 sets it. |

The example programs are not built by default. `cvi_rtsp/Makefile` only adds them when `BUILD_EXAMPLE=1`:

```make
ifeq ($(BUILD_EXAMPLE),1)
SUBDIR += example
endif
```

So the minimal image needs `BUILD_EXAMPLE=1`, or a new buildroot package that builds the server from `example/rtsp_server_video.cpp`.

### Step 6.2: A minimal config for the stream

| | |
|---|---|
| Goal | One H264 stream, no AI, no OSD clutter. |
| Change | A `cvi_rtsp` config with the sensor input and one encoder channel. The test configs in `cvi_rtsp/test/` show the format. |
| Check | The config parses and the stream endpoint is defined. |

### Step 6.3: Verify without the camera

| | |
|---|---|
| Goal | Catch the obvious mistakes without flashing. |
| Change | None. |
| Check | The init script passes `sh -n`. The config file is valid JSON. The binaries in the image are the ones the build produced. |

## Step 7: ONVIF Profile T

ONVIF is a direct goal of the image, not a later idea. The camera speaks RTSP already, ONVIF is the discovery layer on top.

**The target is Profile T.** That means HTTPS and H.265, and it means ONVIF Media 2. The vendor implementation in `Seeed-Studio/sscma-example-sg200x` is a Profile S device: `ver10` namespaces, `trt` prefix, plain `http://` service URL, plaintext password accepted. Profile S conformance submissions close on 31 March 2027.

Three implementations were compared on the source, not on the README:

| | Vendor implementation | `onvif_simple_server` | `onvif_srvd` |
|---|---|---|---|
| License | Apache-2.0 | GPL-3.0 | GPL-2.0 |
| Media service | Media 1 | **Media 1 and Media 2** | Media 1 |
| Imaging service | no | **yes** | no |
| Event service | no | **yes** | no |
| H.265 in the profile list | no | **yes, for Media 2** | no |
| HTTPS | no | via lighttpd | via gSOAP |
| Tested against real NVRs | **yes** | no | no |

`onvif_simple_server` is the only one of the three that has the Profile T services. `media2_service.c` uses the `ver20/media/wsdl` namespace, `imaging_service.c` and `events_service.c` exist, and the H.265 code path renders "H265" for Media 2 and "H264" for Media 1.

Its TLS gap is not a gap in the ONVIF code. It is a CGI program that runs behind a web server, and lighttpd 1.4.59 is already in the Buildroot tree with the OpenSSL option.

**The open question is the license.** GPL-3.0 for the image is a distribution decision for the maintainer. The alternative, porting the Media 2 service into the Apache-2.0 vendor code, is an independent implementation of the Media 2 operations, not a port of the existing ones.

The details, including the full comparison, the TLS setup and the ACME certificate options, are in [onvif.md](./onvif.md).

### Step 7.1: The decision

| | |
|---|---|
| Goal | One implementation is chosen, and the reason is written down. |
| Change | None, this is the decision step. |
| Check | The decision is in `docs/onvif.md` and in `docs/requirements.md`. |
| Note | The default recommendation is `onvif_simple_server` with lighttpd in front of it, because the Profile T services are the hard part and they already exist. The vendor code stays valuable as the field tested reference for the profile mapping. |

### Step 7.2: The package

| | |
|---|---|
| Goal | The ONVIF server builds and is in the image. |
| Change | A new package `external/br2-external-minimal/onvif_simple_server/` with the sources from `roleoroleo/onvif_simple_server`, GPL-3.0. The package selects `BR2_PACKAGE_LIGHTTPD` with `BR2_PACKAGE_LIGHTTPD_OPENSSL`, and `BR2_PACKAGE_CURL` for the certificate renewal. |
| Check | The package builds. The binary is in the image. |
| Dependencies | lighttpd with OpenSSL, curl, and one of libtomcrypt, mbedtls or wolfssl for the digest authentication. |
| Note | lighttpd is in the upstream Buildroot tree at `buildroot-2021.05/package/lighttpd/` and is not in the image yet. The option `BR2_PACKAGE_LIGHTTPD_OPENSSL` selects `BR2_PACKAGE_OPENSSL`. |

### Step 7.3: The configuration file

| | |
|---|---|
| Goal | The daemon knows the camera identity and the two streams. |
| Change | The `onvif_simple_server.json` with the model, manufacturer, firmware version, serial number, the RTSP port, the RTSP path, the ONVIF port and the credentials. |
| Check | The daemon starts with it and the SOAP endpoint answers. |
| Note | The serial number comes from the U-Boot environment, `fw_printenv -n sn`. `uboot-envtools` is already in the image because `libubootenv` is enabled. |

### Step 7.4: Two RTSP streams, one of them H.265

| | |
|---|---|
| Goal | The camera serves a main and a sub stream, with the names the ONVIF profiles point at. |
| Change | The `cvi_rtsp` JSON configuration gets two entries. The session names have to match the path in the ONVIF profiles. The main stream gets `"codec": "265"`. |
| Check | The JSON parses, and the paths in it match the ONVIF configuration. |
| Detail | The vendor stream node uses the session name `live` and derives the path as `/` plus the session name. So the ONVIF profile points at `rtsp://<ip>:554/live`. The `cvi_rtsp` configuration has to use the same name. This is the one place where the two sides have to agree. |
| Note | The chip has `VENC_MAX_CHN_NUM 16`, two channels are plenty. The service library itself supports `SERVICE_CTX_ENTITY_MAX_NUM 2` entities. |

### Step 7.5: The H.265 SDP

| | |
|---|---|
| Goal | A client can start the H.265 decoder from the SDP alone. |
| Change | The local `cvi_rtsp` patch `0001-emit-H264-sprop-parameter-sets-in-SDP.patch` is extended for H.265. It currently scans the Annex-B stream for SPS and PPS and only for `RTSP_VIDEO_H264`. H.265 needs VPS, SPS and PPS, and the parameter set format is different. |
| Check | The SDP of the H.265 stream carries the parameter sets, and a client decodes the stream without waiting for the first in-band frame. |
| Detail | The condition in the patch is `if (rtpSink != NULL && _codec == RTSP_VIDEO_H264)`. The H.265 variant has to look for the three NAL unit types and build the `sprop-vps`, `sprop-sps` and `sprop-pps` parameters. |
| Note | The encoder side is already there: `PT_H265` in `service/venc_helper.cpp:145`, `RTSP_VIDEO_H265` in `service/api.cpp:691` and `src/cvi_video_smss.hpp:54`, and `CVI_VENC_SetH265Vui` and `CVI_VENC_SetH265Trans` in the encoder driver. |

### Step 7.6: The TLS termination

| | |
|---|---|
| Goal | The ONVIF endpoint is reachable over HTTPS. |
| Change | A lighttpd configuration with `mod_openssl`, the certificate and the key, and a CGI handler that forwards to the ONVIF server on localhost over plain HTTP. |
| Check | `https://<ip>/onvif/device_service` answers, and `http://<ip>:8899/onvif/device_service` is not reachable from outside the device. |
| Note | The service URL in the discovery response becomes `https://`, and the WS-Discovery responder has to advertise the `https` scheme. |

### Step 7.7: The certificate

| | |
|---|---|
| Goal | The camera serves a certificate the client trusts, without a port open on the router. |
| Change | `acme.sh` with a DNS-01 challenge, a renewal hook and the reload of lighttpd. |
| Check | The certificate renews and lighttpd picks up the new one without a restart. |
| Detail | `acme.sh` is POSIX shell and needs `curl`, `openssl` and a POSIX shell, all three are in the image. It has 205 DNS providers, among them Cloudflare, AWS Route 53, Alibaba Cloud, DigitalOcean and Hetzner. `lego` is not an option, it is a Go binary and there is no riscv64 release. |
| Note | The provider API needs a credential. The certificate and the key go into the overlay filesystem, not into the image. HTTP-01 is the alternative but it needs a port 80 forward on the router, and BusyBox httpd is not enabled in this image anyway. |

### Step 7.8: The provider selection

| | |
|---|---|
| Goal | The user picks the DNS provider of their domain from a list, not from a hardcoded name. |
| Change | The script `acme-provider` in the overlay, with all 205 providers and an interactive `dialog` menu. The `dialog` package is enabled in the Buildroot config. |
| Check | `acme-provider menu` opens the list, `acme-provider set cf` stores the choice, and `acme-provider show` prints it back. |
| Detail | The codes are the file names in acme.sh's `dnsapi` directory. The credentials go into `/etc/acme.sh/provider.conf`, and `acme-provider creds <code>` prints the variables that the chosen provider reads. |
| Note | Cloudflare is the first test, because an API token with permission to edit the DNS zone is the simplest credential of all 205. |

### Step 7.9: The SOAP endpoint

| | |
|---|---|
| Goal | The ONVIF endpoint answers with the Media 2 namespaces. |
| Change | None, the daemon serves it. |
| Check | `https://<ip>/onvif/device_service` answers with a device description, and `GetProfiles` returns both streams with the `tr2` namespace. |
| Note | The port is the vendor default, 8899. It does not collide with anything in the image. |

### Step 7.10: Web services discovery

| | |
|---|---|
| Goal | A client finds the camera without knowing the address. |
| Change | None, the daemon already has the responder. It binds UDP 3702 and answers the probe. |
| Check | The process is running and listening. A client that scans finds the camera. |
| Note | Without this the camera only shows up when the address is entered by hand. The vendor port is 3702, the ONVIF standard default is 3700. Both are used in the field, the vendor one works with the NVRs that were tested. |

### Step 7.11: Snapshot

| | |
|---|---|
| Goal | A still image for the ONVIF snapshot URL. |
| Change | A CGI script that grabs one JPEG from the pipeline and writes it to stdout. The encoder supports `CVI_RTSP_VIDEO_JPEG`. |
| Check | The snapshot URL returns a JPEG. |
| Note | The vendor implementation has no snapshot operation. This is new work. |

**Decision: wanted.** Many clients show a thumbnail in the device list. Without it the entry is blank and the camera looks broken.

PTZ is **out of scope**. The gimbal is a separate product variant with its own base board, and the camera has no PTZ hardware. The PTZ service of `onvif_simple_server` stays unused, as does the `ver20/ptz/wsdl` namespace in `onvif_srvd`.

## Step 8: Flash and verify

### Step 8.1: The image

| | |
|---|---|
| Goal | A flashable artifact. |
| Change | None, the build produces it. |
| Check | The zip exists next to the build output. |

### Step 8.2: The first boot

| | |
|---|---|
| Goal | The camera comes up on the minimal image. |
| Change | None. |
| Check | Over the serial console: the overlay mounts, the modules load, the RTSP server starts. SSH works. |
| Note | The camera keeps its eMMC layout, so the userdata partition and the factory reset still work. |

## Order of work

| Step | What it does | Ends with |
|---|---|---|
| 0 | Baseline build and inventory | The upstream image builds, and a list of its contents |
| 1 | Understand the pipeline | The chain from sensor to RTSP written down |
| 2 | New buildroot tree and defconfig | The minimal target builds with the same content as the baseline |
| 3 | Remove the app layer | A much smaller image: no Node-RED, no broker, no web UI, no AI, no FreeRTOS, no radio, no battery, live555 from source |
| 4 | Check the network facing packages | The versions of dropbear, busybox and openssl are known and acceptable |
| 5 | Trim the boot overlay | No auto update, no app start, only the needed services |
| 6 | The camera comes up | The RTSP server starts with a config, two streams |
| 7 | ONVIF | The device service answers, a client sees two profiles |
| 8 | Flash and verify | The camera boots on the minimal image |

Steps 0 to 2 are the safety net. Nothing is removed before step 3. Every step ends in a build that has to succeed. Step 2.3 is the important one: the minimal target builds and has the same content as the baseline. After that, every change is a difference from a known good state.

The plan produces a camera with RTSP and ONVIF, on Ethernet, updated over the air when someone asks for it. Not a web UI, not a flow editor, not a broker, not a radio.

### The build runs in CI

Every step ends in a build, and the build runs in the GitHub workflow. It has to, because the local machine has no running Docker daemon and systemd is offline.

The workflow needs to be extended before the first build of the minimal target can happen:

| | |
|---|---|
| Change | Add `sg2002_recamera_minimal` to the matrix in `.github/workflows/main.yml`. |
| Change | Add a `push` trigger on `develop`, so a build runs on every commit and not only on a tag. |
| Check | A push to `develop` starts a run and the run produces the zip files. |
| Note | The workflow reads the CHANGELOG to decide what to build, and it looks for the target name under the version heading. A CHANGELOG entry with a `### sg2002_recamera_minimal` section is needed. |
| Note | The `output/sg2002_recamera_emmc/buildroot-2021.05/dl` cache path in the workflow is hardcoded to the emmc target. A second target needs its own cache path, or the download directory has to be shared. |

The toolchain cache does not depend on the target, so the minimal build reuses it.

## Open questions

The scope decisions are made. They are at the top of this document, in the section "The scope decisions". The steps above carry them inline with a `**Decision:**` marker.

Still open:

- Does the Linux side talk to the FreeRTOS core? `rtos_cmdqu` is used by the region and fast_image parts of the video pipeline. This has to be answered before step 3.6 can drop FreeRTOS.
- Is a kernel port to 6.4 or 7.x wanted later? It is not a step in this plan, it is its own project. The breakdown is in [kernel-upgrade.md](./kernel-upgrade.md).
- **Which ONVIF implementation wins?** `onvif_simple_server` is the cheaper path to Profile T, because it already has the Media 2, imaging and event services. It is GPL-3.0, which makes the whole image GPL-3.0. The alternative is an independent implementation of the Media 2 operations on top of the Apache-2.0 vendor code, which is more work but keeps the license. This is a distribution decision, it is not a technical obstacle.
- **Which DNS provider for the ACME certificate?** The DNS-01 challenge needs an API credential for the DNS provider of the domain. Cloudflare is the simplest case. The camera never has to be reachable from the internet for this.

The ones below are answered by the code and do not need a decision:

- **The Docker daemon.** The build goes through CI, it does not need Docker locally. The workflow builds without a container.
- **The ONVIF port.** 8899, the vendor default. It does not collide with anything in the image.
- **The crypto library for ONVIF.** OpenSSL, which is already in the image, plus one of libtomcrypt, mbedtls or wolfssl for the digest authentication. `onvif_simple_server` picks one at build time.
- **The ONVIF events.** Out of scope. Without the AI stack there is no motion detection, so there is nothing to report. The event service of `onvif_simple_server` is there but stays empty.
- **The TLS termination.** lighttpd, with `mod_openssl`. It is in the upstream Buildroot tree and the CGI interface of `onvif_simple_server` is the standard way to run it behind TLS.
- **The OpenSSH version.** 10.6p2, the version that fixes CVE-2026-123158. The upstream Buildroot is already there.
