# Plan: minimal reCamera OS

Every step has a goal, a concrete change and a way to check the result.
The check is always a build, never the camera.

The submodule review in [submodule-review.md](./submodule-review.md) is the
evidence for the decisions below.

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
| Docker | Installed, but the daemon does not run and there is no sudo. |
| Disk | The workspace sits on an ext4 partition with 440 GB free. |
| Host toolchain | Incomplete. `dtc`, `squashfs-tools`, `flex`, `bison`, `mtools` and `libssl-dev` are missing, and the host has gcc 15 where the build expects gcc 11. |
| Conclusion | The Docker build is the way. The container image carries the right toolchain. It needs a running daemon. |

Two ways to get there: start the Docker daemon as a user, or run the build
directly on the host after installing the missing packages.


### Step 0.2: Baseline inventory

Unpack the rootfs of the built image and list what is in it.

| | |
|---|---|
| Goal | A reference list of everything in the upstream image. |
| Change | None, just a script that lists the packages. |
| Check | The list is stored next to the build output. |
| Note | This list is the checklist for the trimming steps later. |


## Step 1: Understand what is actually needed

Before removing anything, find out which piece does what. The camera does not
work through Node-RED or the supervisor, it works through the CVI pipeline:
sensor, MIPI, VI, VPSS, encoder, RTSP.

### Step 1.1: Map the camera pipeline

| | |
|---|---|
| Goal | Know the chain from sensor to RTSP stream. |
| Change | Documentation only. |
| Check | The chain is written down with the file that implements each link. |
| Result | `osdrv/interdrv/cif` (MIPI RX), `snsr_i2c` (sensor), `vi`, `vpss`, `cvi_vc_drv` (encoder), `cvi_rtsp` (server). |

### Step 1.2: Find out what the blob does

The `reCamera` buildroot package downloads a zip and copies its install tree
into the target. Before dropping it, check what is in it.

| | |
|---|---|
| Goal | Know whether the blob carries something the camera needs. |
| Change | Documentation only. |
| Check | The contents of the blob are listed. |
| Finding | The blob pulls from a `reCamera` branch of `sscma-example-sg200x` that no longer exists upstream. The package is already broken. The blob carries the web UI and the device manager, not the camera. |

## Step 2: A separate buildroot tree for the minimal image

The upstream build mixes the camera and the app stack in one external tree.
The minimal image gets its own tree so the upstream build stays untouched and
can still be produced for comparison.

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

The defconfig starts as a copy of the upstream one. The trimming happens in
the packages, not in the defconfig, because most of the removed parts are not
buildroot packages at all.

### Step 2.3: Build the unmodified minimal target

| | |
|---|---|
| Goal | Prove the new target builds before anything is removed. |
| Change | Only the new defconfig and the new external tree, with the same package list as upstream. |
| Check | The build succeeds and the image has the same content as the baseline. |
| Note | This step is the safety net for everything that follows. |

## Step 3: Remove the app layer

This is where the image actually gets small. The parts below are the app stack:
the web UI, the AI features, the flow editor. None of them are needed for a
camera.

### Step 3.1: Drop the packages that carry the app layer

| | |
|---|---|
| Goal | No web UI, no AI, no flow editor in the image. |
| Change | In the minimal external tree: remove `reCamera`, `sscma-supervisor`, `sscma-node`, `opencv4`, `opencv4-contrib`, `libhv`, `morse_cli`. Set `BR2_PACKAGE_SSCMA_SUPERVISOR`, `BR2_PACKAGE_SSCMA_NODE`, `BR2_PACKAGE_RECAMERA` to `n`. |
| Check | The build succeeds. The inventory shows no supervisor, no node-red, no opencv. |

The supervisor is the one that matters most: it installs its own rootfs and
starts the broker. Removing it takes the web UI, the device manager and the
mosquitto broker with it.

### Step 3.2: Remove the infrastructure that only the app layer used

| | |
|---|---|
| Goal | A smaller image and fewer listening ports. |
| Change | Turn off `mosquitto`, `avahi`, `dnsmasq`, `ttyd` (`node-red-dashboard` websocket), `bluez5_utils`, `bt-init`. |
| Check | The inventory shows no mosquitto, no avahi, no ttyd. The build log has no error about a missing dependency. |

### Step 3.3: Keep the wireless stack that the camera needs

| | |
|---|---|
| Goal | WiFi works, without dragging in Bluetooth. |
| Change | Keep `wpa_supplicant_s1g` and the WiFi kernel modules. Remove `bt-init` and `bluez5_utils`. |
| Check | The init script `loadsystemko.sh` no longer loads `dot11ah.ko` and `morse.ko`, but still loads `brcmfmac.ko` for the BCM43012 WiFi. |
| Note | The HaLow chip (`morse.ko`, `dot11ah.ko`) is a separate 802.11ah radio. It is not the normal WiFi. Decide later whether the minimal image wants HaLow, normal WiFi or both. |

Bluetooth is only on the `w` variant of the core board. The C1-2002w carries
the WiFi/Bluetooth module, the C1-2002 does not. The `bt-init` package patches
the BCM firmware at boot, which is the part that goes.

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
| Note | `cvi_rtsp/build.sh` only downloads the tarball when `LIVE555_DIR` is empty. Set it and the download never happens. The Buildroot package is version 2025.10.13, LGPL-3.0, with a checked hash. |
| Detail | `cvi_rtsp/Makefile.inc` expects four static archives under `$(LIVE555_DIR)/lib/` and the headers in four separate include directories. The Buildroot layout has the headers in one directory, so `LIVE555_INC` has to be adjusted. |
| Risk | If the paths do not line up, the `cvi_rtsp` build fails with a missing header. That is a build failure, not a silent problem. |


### Step 3.8: Drop the TPU stack

| | |
|---|---|
| Goal | No AI accelerator in a camera image. |
| Change | Remove `cviruntime`, `cvikernel`, `cvimath`, `cvibuilder`, `cnpy`, `tdl_sdk`, `flatbuffers` from the build. Remove `cv181x_tpu.ko` from the module list. |
| Check | The inventory has no TPU libraries. The image is smaller. |
| Note | `ive` stays, it is the image processing engine and not the AI one. |

### Step 3.9: Keep the ISP tuning

| | |
|---|---|
| Goal | The sensor still produces a correct image. |
| Change | Keep `isp_tuning` and the `CONFIG_SENSOR_*` options. The tuning binaries are copied to `/mnt/system/cfg/param` by `pack_cfg` in `external/setenv.sh`. |
| Check | The param directory in the image contains the tuning files for the configured sensor. |

## Step 4: Check the packages that carry the attack surface

Buildroot 2021.05 is end of life, the upstream branch stopped in June 2021. The
minimal image has three packages that matter for a network reachable device.

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

The overlay sets up the writable root. Some of its parts belong to the app layer.

Two places hold the init scripts:

- `external/buildroot/board/cvitek/CV181X/overlay/etc/init.d/` has `S70hardware`,
  `S80dnsmasq`, `S92node-red`, `S98ttyd` and `S99user`
- `external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/` has the boot
  scripts: `auto.sh`, `auto_download.sh`, `rootfs_overlay.sh`, `upgrade.sh` and
  the usb networking scripts

The `S99user` script sources `/mnt/system/auto.sh`, which starts the vendor
application. That is the hook to the app layer.

### Step 5.1: Keep the overlay, drop the app hooks

| | |
|---|---|
| Goal | The writable root still works, without the OTA and factory reset of the app image. |
| Change | Keep `rootfs_overlay.sh` and `ko/loadsystemko.sh`. Remove `upgrade.sh` and the OTA block in `rootfs_overlay.sh` if OTA is not wanted. |
| Check | The boot log shows the overlay mounted and the kernel modules loaded. |
| Note | The factory reset is a safety feature. Keeping it is cheap and saves a bricked camera. |

### Step 5.2: Remove the auto update

| | |
|---|---|
| Goal | The camera does not pull new firmware from the internet behind your back. |
| Change | Remove `auto_download.sh` and the call to it. It polls the GitHub release feed every 60 seconds and installs whatever it finds. |
| Check | The script is not in the image. Nothing reaches out to github.com at boot. |
| Note | `S99user` sources `/mnt/system/auto.sh`, and `auto.sh` is what starts the vendor application. Both the auto update and the app start have to go for the image to be self contained. |


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

The example programs are not built by default. `cvi_rtsp/Makefile` only adds them
when `BUILD_EXAMPLE=1`:

```make
ifeq ($(BUILD_EXAMPLE),1)
SUBDIR += example
endif
```

So the minimal image needs `BUILD_EXAMPLE=1`, or a new buildroot package that
builds the server from `example/rtsp_server_video.cpp`.




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

ONVIF is new code on top of the working camera. It is a separate step because it
depends on the pipeline from step 5 being right.

### Step 7.1: Pick the approach

| | |
|---|---|
| Goal | A decision, not code. |
| Options | A: use an existing ONVIF server, for example `onvif-server` or `gsoap` based ones. B: write a small ONVIF service that maps the ONVIF calls onto the CVI API. |
| Check | The choice is written down with the reason. |
| Note | Option A is much less work but pulls in dependencies. Option B gives a small image but is a lot of code. ONVIF needs SOAP, which is why `libhv` may stay after all. |

### Step 7.2: Build the service

| | |
|---|---|
| Goal | `GetProfiles`, `GetStreamUri` and the RTSP describe work. |
| Change | The service as a new package in the minimal external tree. |
| Check | It starts at boot and answers on the ONVIF port. |

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
| 6 | The camera comes up | The RTSP server starts with a config |
| 7 | ONVIF | The ONVIF service answers |
| 8 | Flash and verify | The camera boots on the minimal image |

Steps 0 to 2 are the safety net. Nothing is removed before step 3. Every step
ends in a build that has to succeed.

Step 2.3 is the important one: the minimal target builds and has the same
content as the baseline. After that, every change is a difference from a known
good state.


## Open questions

- HaLow, normal WiFi, or both? The `morse.ko` and `dot11ah.ko` modules are for
  the 802.11ah radio, `brcmfmac.ko` for the BCM43012.
- Is the OTA update wanted? It needs the `upgrade.sh` in the overlay.
- Is the gimbal wanted? The CAN bus and the `gimbal` binary.
- Is the battery wanted? The `ads1015` on I2C1 feeds the battery supervisor API.
- Which sensor to target: OV5647, GC2053 or SC530AI? The defconfig enables all
  three.
- ONVIF: existing server or own implementation?
- Does the Linux side talk to the FreeRTOS core? `rtos_cmdqu` is used by the
  region and fast_image parts of the video pipeline.
- Can the Docker daemon be started on this machine? The build needs it, and
  there is no sudo.


