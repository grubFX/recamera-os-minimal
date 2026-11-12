# Plan: minimal reCamera OS

Every step has a goal, a concrete change and a way to check the result. The check is always a build, never the camera. The submodule review in [submodule-review.md](./submodule-review.md) is the evidence for the decisions below.

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
| Conclusion | The build goes through CI. |

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
CONFIG_SENSOR_OV_OV5647=y
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

### Step 3.3: Keep the wireless stack that the camera needs

| | |
|---|---|
| Goal | WiFi works, without dragging in Bluetooth. |
| Change | Keep the WiFi kernel modules and the matching wpa_supplicant. Remove `bt-init` and `bluez5_utils`. |
| Check | The init script `loadsystemko.sh` loads the radio modules for the board the camera has, and the init script starts the matching supervisor. |
| Note | **Open.** Which radio the image keeps depends on the board. See below. |

Bluetooth is only on the `w` variant of the core board. The C1-2002w carries the WiFi/Bluetooth module, the C1-2002 does not. The `bt-init` package patches the BCM firmware at boot, which is the part that goes.

#### The two radios

The image carries drivers for two radios, they are not two settings for the same radio:

| Radio | Standard | Driver | Kernel module | Supervisor |
|---|---|---|---|---|
| Morse mm610x | 802.11ah, the HaLow band, sub-GHz, kilometres of range | vendor tree in `external/linux/drivers/fgh100m/` | `dot11ah.ko`, `morse.ko` | `wpa_supplicant_s1g` |
| Broadcom BCM43012 | 802.11ac, 2.4 and 5 GHz | upstream `brcmfmac` | `brcmfmac.ko` | `wpa_supplicant` |

Which one is in the image depends on the core board:

```
OSHW-reCamera-Series/hardware/recamera-2002/core/c1-2002/README.md
  C1-2002    No wireless module; exposes additional SDIO/UART signals to the base
  C1-2002w   Wi-Fi/Bluetooth module, onboard antenna, and I-PEX connector
```

The plain `C1-2002` has no radio of its own. The base board can supply one over the exposed SDIO or UART signals. The `C1-2002w` has the module onboard.

The gpio sharing makes this a decision with a side effect:

```
external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/ko/loadsystemko.sh
  [ ! -e /dev/morse_io ] && [ ! -e /dev/mmcblk1 ] && {
      # gimbal
      [ -x /usr/bin/gimbal ] && { ... }
      # PoE
      ...
  }
```

The HaLow radio and the SD card share GPIOs. When the HaLow radio is present the script skips the gimbal init and the PoE pinmux. So dropping one radio can change what the other one can do.

Three options, and the plan takes one of them:

| Option | What stays | When it is the right one |
|---|---|---|
| BCM only | `brcmfmac.ko`, `wpa_supplicant` | The camera is on normal WiFi, or it is on Ethernet. The HaLow radio is not needed. |
| HaLow only | `dot11ah.ko`, `morse.ko`, `wpa_supplicant_s1g` | The camera reports over a long link, the point of the HaLow radio. |
| Both | everything | The board has both and both are wanted. The most drivers, the most surface. |

The BCM only option is the default for the minimal image, because a normal WiFi is what a laptop or a phone can join. HaLow needs a special concentrator on the other side, and that is not something a normal network has.

**Open:** the board of the target camera has to be confirmed before this step runs. The hardware repository says the standard Basic product is the `2002w` and the HQ PoE product is the plain `C1-2002`.

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
| Change | Keep `isp_tuning` and `CONFIG_SENSOR_OV_OV5647`. Remove `CONFIG_SENSOR_GCORE_GC2053` and `CONFIG_SENSOR_SMS_SC530AI_2L`. The tuning binaries are copied to `/mnt/system/cfg/param` by `pack_cfg` in `external/setenv.sh`. |
| Check | The param directory in the image contains the tuning files for the OV5647 and nothing for the other two sensors. |
| Note | **Decision: OV5647.** That is the sensor the standard product ships with, on the S101 sensor board. The GC2053 is the HQ PoE variant, the SC530AI is a third option. Each sensor needs its own ISP tuning, and the ones that are not used are dead weight in the image. |

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
| Change | In `loadsystemko.sh`: remove the TPU module (`cv181x_tpu.ko`), the audio modules and the gimbal init if not wanted. Remove the `morse.ko` and `dot11ah.ko` lines if HaLow goes. |
| Check | The boot log lists the expected modules and no errors. |
| Note | The module list also shows the hardware: `ti-ads1015.ko` for the battery on I2C1, `morse.ko` for the HaLow chip, `brcmfmac.ko` for the BCM43012 WiFi. |

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

## Step 7: ONVIF

ONVIF is a direct goal of the image, not a later idea. The camera speaks RTSP already, ONVIF is the discovery layer on top.

The approach is not to write an ONVIF implementation. The vendor stack already has one, in the public Apache-2.0 repository, 1267 lines across 8 files, and it was tested against real NVRs. It is compiled into `sscma-node`, the Node-RED node binary, so it has to be lifted out into its own daemon.

The details are in [onvif.md](./onvif.md).

### Step 7.1: Extract the module

| | |
|---|---|
| Goal | The ONVIF code exists as a standalone package, not inside the Node-RED node. |
| Change | Copy the eight files from `solutions/sscma-node/main/node/onvif/` into a new package `external/br2-external-minimal/onvifd/`. Add a `main.cpp` that reads the configuration, registers the profiles and keeps the service running. |
| Check | The package builds. The binary is in the image. |
| Source | `https://github.com/Seeed-Studio/sscma-example-sg200x`, the `onvif/` directory, Apache-2.0. The license header stays on every file. |
| Note | The code is copied, not written. The Apache-2.0 license requires the notice to be kept and allows reuse in a proprietary image. |

### Step 7.2: Drop the vendor dependencies

| | |
|---|---|
| Goal | The extracted code does not need the Node-RED framework. |
| Change | `ma::Mutex` and `ma::Guard` become `std::mutex` and `std::lock_guard`. `ma_err_t` becomes `int`. `PROJECT_VERSION` becomes a string from the build configuration. |
| Check | The package builds without the `SSCMA-Micro` submodule. No `core/ma_debug.h` include is left. |
| Detail | `ma_debug.h` is only used for the `MA_LOG*` macros. They map to `ma_printf`. The replacement is a logging macro that writes to stderr, or the BusyBox syslog. |
| Note | This is the whole vendor coupling. The rest is libhv, OpenSSL and POSIX sockets. |

### Step 7.3: The buildroot package

| | |
|---|---|
| Goal | `onvifd` builds and is in the image. |
| Change | The new package selects `BR2_PACKAGE_LIBHV` and `BR2_PACKAGE_OPENSSL`. libhv is already in the upstream external tree, so the minimal tree gets the same package definition. |
| Check | The binary is in the image. The build log has no missing dependency. |
| Dependencies | libhv and OpenSSL. Both are already in the image. Nothing new. |
| Note | `libhv` in `external/br2-external/libhv/` is version v1.3.3, from `ithewei/libhv`, and it depends on openssl. It also enables MQTT, which the minimal image does not need, but the flag is in the configure line of the existing package. |

### Step 7.4: The configuration file

| | |
|---|---|
| Goal | The daemon knows the camera identity and the two streams. |
| Change | A configuration file with the model, manufacturer, firmware version, serial number, the RTSP port, the RTSP path, the ONVIF port and the credentials. |
| Check | The daemon starts with it and the SOAP endpoint answers. |
| Note | The serial number comes from the U-Boot environment, `fw_printenv -n sn`. `uboot-envtools` is already in the image because `libubootenv` is enabled. The vendor code already does this, the extracted code keeps that function. |

### Step 7.5: Two RTSP streams

| | |
|---|---|
| Goal | The camera serves a main and a sub stream, with the names the ONVIF profiles point at. |
| Change | The `cvi_rtsp` JSON configuration gets two entries. The session names have to match the path in the ONVIF profiles. |
| Check | The JSON parses, and the paths in it match the ONVIF configuration. |
| Detail | The vendor stream node uses the session name `live` and derives the path as `/` plus the session name. So the ONVIF profile points at `rtsp://<ip>:554/live`. The `cvi_rtsp` configuration has to use the same name. This is the one place where the two sides have to agree. |
| Note | The chip has `VENC_MAX_CHN_NUM 16`, two channels are plenty. The service library itself supports `SERVICE_CTX_ENTITY_MAX_NUM 2` entities. |

### Step 7.6: The SOAP endpoint

| | |
|---|---|
| Goal | The ONVIF endpoint answers. |
| Change | None, the daemon serves it on the libhv HTTP server. |
| Check | `http://<ip>:8899/onvif/device_service` answers with a device description, and `GetProfiles` returns both streams. |
| Note | The port is the vendor default, 8899. It does not collide with anything in the image. |

### Step 7.7: Web services discovery

| | |
|---|---|
| Goal | A client finds the camera without knowing the address. |
| Change | None, the daemon already has the responder. It binds UDP 3702 and answers the probe. |
| Check | The process is running and listening. A client that scans finds the camera. |
| Note | Without this the camera only shows up when the address is entered by hand. The vendor port is 3702, the ONVIF standard default is 3700. Both are used in the field, the vendor one works with the NVRs that were tested. |

### Step 7.8: Snapshot

| | |
|---|---|
| Goal | A still image for the ONVIF snapshot URL. |
| Change | A CGI script that grabs one JPEG from the pipeline and writes it to stdout. The encoder supports `CVI_RTSP_VIDEO_JPEG`. |
| Check | The snapshot URL returns a JPEG. |
| Note | The vendor implementation has no snapshot operation. This is new work. |

**Decision: wanted.** Many clients show a thumbnail in the device list. Without it the entry is blank and the camera looks broken.

PTZ is **out of scope**. The gimbal is a separate product variant with its own base board, and the vendor implementation of ONVIF has no PTZ support anyway. The four PTZ operations and the CAN plumbing are not part of this image.

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
| 3 | Remove the app layer | A much smaller image: no Node-RED, no broker, no web UI, no AI, no FreeRTOS, live555 from source |
| 4 | Check the network facing packages | The versions of dropbear, busybox and openssl are known and acceptable |
| 5 | Trim the boot overlay | No auto update, no app start, only the needed services |
| 6 | The camera comes up | The RTSP server starts with a config, two streams |
| 7 | ONVIF | The device service answers, a client sees two profiles |
| 8 | Flash and verify | The camera boots on the minimal image |

Steps 0 to 2 are the safety net. Nothing is removed before step 3. Every step ends in a build that has to succeed. Step 2.3 is the important one: the minimal target builds and has the same content as the baseline. After that, every change is a difference from a known good state.

The plan produces a camera with RTSP and ONVIF. Not a web UI, not a flow editor, not a broker.

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

- HaLow, normal WiFi, or both? The `morse.ko` and `dot11ah.ko` modules are for
the 802.11ah radio, `brcmfmac.ko` for the BCM43012.
- Is the battery wanted? The `ads1015` on I2C1 feeds the battery supervisor API.
- Which sensor to target: OV5647, GC2053 or SC530AI? The defconfig enables all
three.
- Does the Linux side talk to the FreeRTOS core? `rtos_cmdqu` is used by the
region and fast_image parts of the video pipeline.
- Is a kernel port to 6.4 or 7.x wanted later? It is not a step in this plan,
it is its own project. The breakdown is in [kernel-upgrade.md](./kernel-upgrade.md).

The ones below are answered by the code and do not need a decision:

- **The Docker daemon.** The build goes through CI, it does not need Docker locally. The workflow builds without a container.
- **The ONVIF port.** 8899, the vendor default. It does not collide with anything in the image.
- **The crypto library for ONVIF.** There is no choice to make. The vendor implementation uses OpenSSL for SHA1, and OpenSSL is already in the image. No libtomcrypt, no mbedtls, no wolfssl.

Still open, and they are additions on top of the extracted module:

- Is the snapshot wanted? Many clients show a thumbnail in the device list, it needs a CGI script that grabs one JPEG.
- Is PTZ wanted? It needs the CAN interface of the gimbal and four small scripts, plus four ONVIF operations that do not exist yet.
- Are ONVIF events wanted? Without the AI stack there is no motion detection, so there is nothing to report.
