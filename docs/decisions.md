# Decisions

The scope decisions for the minimal image, and the reasoning behind each one.

This file is the authority on the scope. The plan steps carry the same decisions inline, and where they differ, this file wins. Requirement 9 in [requirements.md](./requirements.md) says the same thing.

## Decided

| Question | Decision | Plan step |
|---|---|---|
| OTA update | yes, with the automatic polling removed | 5.2 |
| Gimbal | no | 7.9, dropped |
| PTZ | no, it comes with the gimbal | 7.9, dropped |
| Sensor | OV5647 | 3.9 |
| Snapshot | yes | 7.8 |
| ONVIF events | no, without the AI stack there is no motion detection | 7, not in scope |
| Docker daemon | not a decision, the build goes through CI | 0 |
| ONVIF port | 8899, the vendor default | 7.6 |
| Crypto library for ONVIF | OpenSSL, which is already in the image | 7.3 |

## Still open

| Question | What it depends on | Default |
|---|---|---|
| HaLow, normal WiFi, or both? | The core board of the target camera. The plain `C1-2002` has no radio of its own, the `C1-2002w` has the WiFi/Bluetooth module onboard. | BCM only |
| Is the battery wanted? | The `ads1015` on I2C1 feeds the battery supervisor API. The supervisor goes, so the reading goes with it. | no |
| Does the Linux side talk to the FreeRTOS core? | `rtos_cmdqu` is used by the region and fast_image parts of the video pipeline. This has to be answered before FreeRTOS can go. | the core stays until it is answered |

A kernel port to 6.4 or 7.x is not a step in this plan, it is its own project. The breakdown is in [kernel-upgrade.md](./kernel-upgrade.md).

## Why OTA is yes but the automatic polling goes

The mechanism is worth keeping. It has an A/B partition layout with a rollback, and the build already produces the `ota.zip` package:

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

What goes is the trigger. `auto_download.sh` runs an endless loop, polls the release feed every 60 seconds and installs whatever it finds:

```
external/ramdisk/rootfs/overlay/cv181x_musl_riscv64/system/auto_download.sh
  while true; do
      ...
      sleep $DEFAULT_SLEEP
  done
```

That is not an update mechanism. That is the camera rewriting its own root filesystem from the internet with no way for the owner to know what it installs.

The update is triggered by a person over SSH instead:

```
upgrade.sh latest                       # resolve the newest release
upgrade.sh download                     # fetch the package
upgrade.sh start                        # write it and switch the partition
upgrade.sh rollback                     # switch back if it did not boot
```

The SSH route fits the minimal image, it needs no web server. An HTTP endpoint would need an authenticated interface and a web server that is not otherwise in the image.

Two details that matter:

- The download URL points at `https://github.com/Seeed-Studio/reCamera-OS/releases/latest`. For the minimal image that has to point at the fork, or the camera installs the vendor image over the minimal one.
- `wget` is called with `--no-check-certificate` in the script. The md5sum is verified against the file, but the transport is not. The script is a candidate for a certificate fix.

## Why the gimbal and PTZ are no

The gimbal is a separate product variant, not a feature of the camera:

```
OSHW-reCamera-Series/hardware/recamera-2002/products/gimbal/README.md
  Camera stack  C1-2002w + S101 OV5647
  Gimbal base   B401 CAN
  Motor interface  CAN, up to 1Mbps
  Motion        360 degree yaw, 180 degree pitch
```

The base board is the CAN base, and the motor protocol is a third-party supplier document. The vendor implementation of ONVIF has no PTZ support either, so PTZ would be four new ONVIF operations plus the CAN plumbing.

The consequence: the `gimbal` binary, the CAN base board support and the four PTZ operations are all out of scope.

## Why OV5647

The standard product ships with the S101 OV5647 sensor board. The `SENSOR_COMPATIBILITY.md` in the hardware repository lists the drivers the SG2002 kernel configuration supports, and the defconfig currently enables three:

```
CONFIG_SENSOR_OV_OV5647=y
CONFIG_SENSOR_GCORE_GC2053=y
CONFIG_SENSOR_SMS_SC530AI_2L=y
```

Only the OV5647 stays as the target. The other two are for the GC2053 variant of the HQ PoE product and for the SC530AI.

The ISP tuning binaries follow the sensor, they are copied to `/mnt/system/cfg/param` by `pack_cfg`. The plan keeps exactly the ones for the target sensor, the rest is dead weight in the image.

## Why the snapshot is yes

Many clients show a thumbnail in the device list. Without it the entry is blank and the camera looks broken.

The vendor implementation of ONVIF has no snapshot operation, so this is new work: a CGI script that grabs one JPEG from the pipeline and writes it to stdout. The encoder supports `CVI_RTSP_VIDEO_JPEG`.

## What HaLow is and why it is a hardware question

HaLow is 802.11ah, the WiFi successor to 802.11ac that was designed for long range and low power. It runs in the sub-GHz band, so the range is in kilometres rather than metres. That is the point of it: a camera that reports over a long link without asking for much power.

The image carries drivers for two different radios. They are not two settings for the same radio:

| Radio | Standard | Driver | Kernel modules | Supervisor |
|---|---|---|---|---|
| Morse mm610x | 802.11ah, the HaLow band, sub-GHz | vendor tree in `external/linux/drivers/fgh100m/` | `dot11ah.ko`, `morse.ko` | `wpa_supplicant_s1g` |
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

Three options:

| Option | What stays | When it is the right one |
|---|---|---|
| BCM only | `brcmfmac.ko`, `wpa_supplicant` | The camera is on normal WiFi, or it is on Ethernet. The default for the minimal image. |
| HaLow only | `dot11ah.ko`, `morse.ko`, `wpa_supplicant_s1g` | The camera reports over a long link, that is the point of the HaLow radio. |
| Both | everything | The board has both and both are wanted. The most drivers, the most surface. |

The BCM only option is the default, because a normal WiFi is what a laptop or a phone can join. HaLow needs a special concentrator on the other side, and that is not something a normal network has.
