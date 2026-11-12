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

The upstream `sg2002_recamera_emmc` build is Buildroot 2021.05 (Sophgo fork) plus a
set of external packages. Everything that ends up in the image comes from one of
these places.

### Vendor parts that have to stay

| Part | Source | Why it stays |
|---|---|---|
| Kernel | `linux_5.10` (Sophgo fork) | 5.10.4 with the CVI clock, dma, pinctrl, fbdev, sound and wifi/bt pin trees. The camera does not work without it. |
| Bootloader | `u-boot-2021.10`, `fsbl`, `opensbi` | Boot chain of the SoC. |
| SDK | `osdrv`, `cviruntime`, `cvibuilder`, `cvikernel`, `cvimath`, `ive`, `cvi_mpi` | The video pipeline, the ISP and the encoder. All source, no blobs. |
| RTSP | `cvi_rtsp` | The RTSP server. Source. |
| Init | `ramdisk` overlay | The overlayfs setup on the userdata partition. |

None of these are patches on top of upstream Linux. They are the vendor tree, and
they cannot be removed without losing the camera.

### Parts that go

| Part | What it is | Why it goes |
|---|---|---|
| `reCamera` package | Downloads a prebuilt `reCamera.zip` from `sscma-example-sg200x` and copies its install tree into the target | A binary blob of unknown content. This is the main thing to get rid of. |
| `sscma-supervisor` | The REST API on port 80, built with libhv | Only needed for the web UI and the device manager. It also ships its own rootfs and starts the broker. |
| `sscma-node` | Wraps the TPU inference, pulls in host-nodejs and node-red | Only needed for the AI features. |
| `node-red` + dashboard | The flow editor and dashboard | Not wanted in a minimal image. |
| `mosquitto` | Broker on 127.0.0.1 | Only used by the node-red and sscma stack. |
| `avahi`, `dnsmasq`, `ttyd` | mDNS, DNS and the web terminal | Not needed. |
| `bt-init`, `bluez5_utils` | Bluetooth init for the BCM chip | See below. |
| `opencv4`, `opencv4-contrib` | Only used by the sscma stack | Goes with it. |

### Bluetooth: a hardware question

The reCamera board carries a Morse mm610x HaLow chip and a BCM43012 for 2.4/5 GHz
WiFi. The `bt-init` package patches the BCM firmware at boot. Bluetooth is not
needed for the camera, so the package goes, unless the WiFi chip turns out to
need it.

## How the image is put together

The build is driven by `external/configs/sg2002_recamera_emmc_defconfig`. It picks
the chip, the board, the DDR config, the sensor and a set of packages.

The external packages live in `external/br2-external/`. The `Config.in` of each
package decides whether it is in the image, and the `.mk` describes how it is
built. The `external/br2-external/Config.in` lists the packages that Buildroot
knows about.

Two kinds of packages:

- `sscma-supervisor`, `sscma-node`, `bt-init`, `morse_cli`, `wpa_supplicant_s1g`
  build from the `sscma-example-sg200x` git repo
- `reCamera` unpacks a prebuilt zip

The init scripts come from two places: the packages copy their own rootfs into the
target, and `external/ramdisk/rootfs/overlay/` holds the boot overlay.

The overlay sets up the writable root: `/bin`, `/etc`, `/home`, `/lib`, `/opt`,
`/root`, `/sbin`, `/usr` and `/var` are mounted as overlayfs with the lower layer
in the read only rootfs and the upper layer in the userdata partition. That is
also where the factory reset and the OTA update live.

## Build

```bash
./docker_build.sh sg2002_recamera_minimal
```

Output lands in `output/sg2002_recamera_minimal/install/soc_sg2002_recamera_minimal/`.
