# Minimal reCamera OS

Goal: a small, understandable image for the Seeed reCamera (SG2002 / CV181X).
Kept:

- Camera: sensor, ISP, video encoding, RTSP
- SSH
- WiFi
- NTP

Removed:

- Node-RED, dashboard, the MQTT broker
- The sscma app layer (inference, supervisor, device manager)
- Avahi, ttyd, dnsmasq, Bluetooth
- The prebuilt `reCamera.zip` blob

Goal later: ONVIF.

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

None of these are patches on top of upstream Linux. They are the vendor tree, and they cannot be removed without losing the camera.
The kernel is not old because nobody cares. The camera drivers in `osdrv` use `class_create(THIS_MODULE, name)`, which was removed in kernel 6.4, and the version guards in the sources stop at 5.10. A newer kernel exists for the SoC, but not for the camera.
Upstream Linux 5.10 is still a maintained longterm release, the fork gets the weekly stable releases. The kernel is behind, not abandoned.
What a port to 6.4 or 7.x would cost is in [kernel-upgrade.md](./kernel-upgrade.md).

### Parts that go

| Part | What it is | Why it goes |
|---|---|---|
| `reCamera` package | Downloads a prebuilt `reCamera.zip` from `sscma-example-sg200x` and copies its install tree into the target | A binary blob of unknown content. The source branch no longer exists upstream, the package is already broken. |
| `sscma-supervisor` | The REST API on port 80, built with libhv | Only needed for the web UI and the device manager. It also ships its own rootfs and starts the broker. |
| `sscma-node` | Wraps the TPU inference, pulls in host-nodejs and node-red | Only needed for the AI features. |
| `node-red` + dashboard | The flow editor and dashboard | Not wanted in a minimal image. |
| `mosquitto` | Broker on 127.0.0.1 | Only used by the node-red and sscma stack. |
| `avahi`, `dnsmasq`, `ttyd` | mDNS, DNS and the web terminal | Not needed. |
| `bt-init`, `bluez5_utils` | Bluetooth init for the BCM chip | See below. |
| `opencv4`, `opencv4-contrib` | Only used by the sscma stack | Goes with it. |
| FreeRTOS stack | `freertos`, `FreeRTOS-Kernel`, `Lab-Project-FreeRTOS-POSIX` | Runs on the second core, nothing uses it. The forks are two years behind upstream. |
| TPU stack | `cviruntime`, `cvikernel`, `cvimath`, `cvibuilder`, `cnpy`, `tdl_sdk`, `flatbuffers` | The AI accelerator SDK. A camera does not need it. |
| `live555.tar.gz` blob | Prebuilt live555 binaries | Live555 is LGPL-3.0 and Buildroot has a package for it. Build from source. |

### Bluetooth: a hardware question

The reCamera board carries a Morse mm610x HaLow chip and a BCM43012 for 2.4/5 GHz WiFi. The `bt-init` package patches the BCM firmware at boot. Bluetooth is not needed for the camera, so the package goes, unless the WiFi chip turns out to need it.
Bluetooth is only on the `w` variant of the core board. The C1-2002w carries the WiFi/Bluetooth module, the C1-2002 does not.

### The auto update

`auto_download.sh` polls the GitHub release feed of `reCamera-OS` every 60 seconds and installs whatever it finds. `S99user` starts it through `/mnt/system/auto.sh`, the same script that starts the vendor application.
Both go. A camera that installs new firmware from the internet on its own is not a normal Linux system, and it is also the path that pulls the prebuilt `reCamera.zip` content into the image.

## How the image is put together

The build is driven by `external/configs/sg2002_recamera_emmc_defconfig`. It picks the chip, the board, the DDR config, the sensor and a set of packages.
The external packages live in `external/br2-external/`. The `Config.in` of each package decides whether it is in the image, and the `.mk` describes how it is built. The `external/br2-external/Config.in` lists the packages that Buildroot knows about.
Two kinds of packages:

- `sscma-supervisor`, `sscma-node`, `bt-init`, `morse_cli`, `wpa_supplicant_s1g`
build from the `sscma-example-sg200x` git repo
- `reCamera` unpacks a prebuilt zip

The init scripts come from two places: the packages copy their own rootfs into the target, and `external/ramdisk/rootfs/overlay/` holds the boot overlay.
The overlay sets up the writable root: `/bin`, `/etc`, `/home`, `/lib`, `/opt`, `/root`, `/sbin`, `/usr` and `/var` are mounted as overlayfs with the lower layer in the read only rootfs and the upper layer in the userdata partition. That is also where the factory reset and the OTA update live.

## The kernel

The kernel is `sophgo/linux_5.10`. It is worth being precise about what that means, because the vendor tree is not the same thing as a kernel with unknown additions.
The history of the `sg200x-dev` branch:

```
b1313fe517  2020-12-30  Greg Kroah-Hartman   Linux 5.10.4
b4ca5efcaf  2024-02-14  sophgo-forum-service linux porting cvitek asic chips.
72ef337123  2024-02-14  sophgo-forum-service [fea] Init sg200x-dev branch.
```

Everything below the first entry is upstream Linux by the upstream authors. Above it there are three Sophgo commits and then weekly stable releases.
The porting commit adds the CV181X device trees and the clock, DMA, pinctrl and sound drivers. The changes to `arch/riscv/` are backports from upstream v5.12 and v5.15, verified by diffing against the upstream releases.
The camera drivers are not in the kernel. They are in `osdrv/interdrv/` and get built as out of tree modules. That is also why the kernel stays at 5.10: the drivers use the two argument `class_create()`, which was removed in kernel 6.4, and the version guards in the sources stop at 5.10.
A newer kernel exists for the SoC. `sophgo/linux-riscv` is at 6.18 and has the SG2002 support. But it has the clock, plic, sdhci and pinctrl, and no CVI video drivers. Mainline has the same. There is no newer kernel with this camera in it.
The full evidence is in [submodule-review.md](./submodule-review.md).

## Build

```bash
./docker_build.sh sg2002_recamera_minimal
```

Output lands in `output/sg2002_recamera_minimal/install/soc_sg2002_recamera_minimal/`.
