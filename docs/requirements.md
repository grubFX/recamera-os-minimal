# Requirements

Hard requirements for the minimal reCamera OS. These are not preferences.

## 1. The kernel has to be real upstream Linux

The kernel source has to trace back to genuine upstream Linux source code. No proprietary code, no closed blobs, nothing that only pretends to be Linux.
**Status: met.** The kernel is `sophgo/linux_5.10`, whose history starts at `b1313fe517` "Linux 5.10.4" by Greg Kroah-Hartman and continues with upstream authors. Above that there are exactly three Sophgo commits, then weekly stable releases.
The vendor additions are in one commit (`b4ca5efcaf` "linux porting cvitek asic chips"), which adds the CV181X device trees and drivers. The modifications to `arch/riscv/` are backports from upstream v5.12/v5.15, verified by diffing against the upstream releases.
The kernel is also not abandoned. Upstream Linux 5.10 is a longterm release and still gets fixes, the last one `3a323bc2` "Linux 5.10.274" from 2026-11-06. The fork mirrors that with the weekly stable releases.
The evidence is in [submodule-review.md](./submodule-review.md), the cost of a newer kernel in [kernel-upgrade.md](./kernel-upgrade.md).

## 2. No prebuilt binaries in the image

Every binary in the image has to be built from source that is in the repo or that comes from a verifiable upstream release with a checked hash.
**Status: not met yet.** Two blobs to remove:

- `oss/oss_release_tarball/musl_riscv64/live555.tar.gz` contains only compiled
binaries. Live555 is LGPL-3.0 and available as a Buildroot package with a verified hash. Build it from source instead.
- `oss/oss_release_tarball/*/opencv_aisdk.tar.gz` contains only libraries.
Goes with the TPU stack.
The `reCamera.zip` blob is already dead, its source branch no longer exists upstream.

## 3. No hidden code in the forks

The forks of upstream software must be small enough to audit, and the delta must be documented.
**Status: met.**

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

## 4. Normal Linux, no weird patches

The result has to be a normal Linux system. No patched binaries, no initializer that only works on this one device, no hidden state.
**Status: open.** The boot overlay sets up an overlayfs over nine directories on the userdata partition. That is a design decision of the vendor image. It also carries the factory reset and the OTA update, which are worth keeping for a camera that can be bricked by a bad flash.
One thing does not fit the description of a normal Linux system and goes: `auto_download.sh` polls the GitHub release feed of `reCamera-OS` every 60 seconds and installs whatever it finds.
The decision per piece is in [plan.md](./plan.md).

## 5. The camera has to work

Camera, RTSP, SSH, WiFi, NTP. ONVIF afterwards.
**Status: open.** This is what the plan is for.

## 6. No known CVE in the network facing packages

The image is reachable from the network. Dropbear, busybox and openssl have to be on versions without known vulnerabilities.
**Status: open.** Buildroot 2021.05 is end of life, its upstream branch stopped in June 2021. The newer Buildroot in the same Sophgo repo has no CV181X support, so the fix is to bump the single package in the fork, not to move the tree.
Plan step 4.

## 7. Everything is committed and pushed

Work happens on the `develop` branch of `grubFX/recamera-os-minimal`, in small commits that can be read on their own.
**Status: in progress.**
