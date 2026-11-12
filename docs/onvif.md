# ONVIF

ONVIF is a direct goal of the minimal image, not a later idea.

The camera speaks RTSP already. ONVIF is the discovery and configuration layer on top of it: a client asks the camera what it can do, gets a list of profiles with stream URLs, and connects to them.

## The vendor already implements ONVIF

This changes the plan. The Seeed vendor stack that the original image is built on contains a complete ONVIF implementation, and it is in the public Apache-2.0 repository, not in a vendor blob.

```
repository:  Seeed-Studio/sscma-example-sg200x
path:        solutions/sscma-node/main/node/onvif/
license:     Apache-2.0
size:        1267 lines across 8 files
```

| File | Lines | Purpose |
|---|---|---|
| `onvif_soap.cpp` | 452 | The SOAP request dispatcher and the XML responses |
| `onvif_utils.cpp` | 250 | XML text extraction, base64, SHA1, device identity |
| `onvif_service.cpp` | 195 | The process wide service, profile registry, HTTP server |
| `onvif_discovery.cpp` | 192 | The WS-Discovery responder on UDP 3702 |
| `onvif_utils.h` | 54 | Declarations |
| `onvif_service.h` | 72 | The `Service` singleton and the `Profile` struct |
| `onvif_discovery.h` | 35 | The discovery responder |
| `onvif_soap.h` | 17 | The SOAP layer |

The CHANGELOG entry for 0.2.5 records it as a shipped feature: "ONVIF support: the device can be added as an ONVIF camera on NVR/VMS platforms (WS-Discovery + SOAP Device/Media service, stream node ONVIF checkbox and port in Node-RED)".

### What it implements

The dispatcher in `onvif_soap.cpp` handles these actions:

```
GetProfiles
GetStreamUri
GetCapabilities
GetDeviceInformation
GetServices
GetSystemDateAndTime
GetVideoEncoderConfiguration
GetGuaranteedNumberOfVideoEncoderInstances
GetHostname
GetUsers
GetEndpointReference
```

That is the full set an NVR needs to discover the camera, read the profile list and connect to the stream.

### Which profile it follows

**It follows Profile S, not Profile T.** The namespaces in the SOAP envelope decide it:

```cpp
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:25
"xmlns:tds=\"http://www.onvif.org/ver10/device/wsdl\" "
"xmlns:tt=\"http://www.onvif.org/ver10/schema\" "
"xmlns:trt=\"http://www.onvif.org/ver10/media/wsdl\">";
```

`ver10/media/wsdl` with the `trt` prefix is ONVIF **Media 1**, which is the specification behind **Profile S**. Profile T is built on ONVIF Media 2, which uses the `ver20` namespaces and the `tr2` prefix. There is not a single `tr2` or `ver20` in the code:

```
$ grep -ohE 'tr2:|tt2:|ver20' *.cpp | sort | uniq -c
(no output)
```

The service list confirms it:

```
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:54
const char* namespaces[] = {
    "http://www.onvif.org/ver10/device/wsdl",
    "http://www.onvif.org/ver10/media/wsdl",
};
```

And the WS-Discovery responder advertises the same thing:

```
// solutions/sscma-node/main/node/onvif/onvif_discovery.cpp:170
"<d:Types>dn:NetworkVideoTransmitter</d:Types>"
```

That type is the one Profile S devices answer with.

**Profile S is being deprecated.** The ONVIF site says the last date for product conformance submissions is 31 March 2027. That does not affect the code, but it affects the plan, because a camera that is meant to live for years should not be built on a profile that is being retired.

### What is missing for Profile S conformance

The implementation is a working subset, not a conformant Profile S device. The gaps that matter for a client:

| Area | What is missing |
|---|---|
| Video encoder configuration | `GetVideoEncoderConfiguration` exists, `GetVideoEncoderConfigurations` does not |
| Video source configuration | `GetVideoSourceConfigurations` and `GetVideoSourceConfiguration` do not exist |
| The `VideoSourceConfiguration` in `GetProfiles` | Points at the hardcoded `video_src_0`, which is not a real source |
| Configuration change | Nothing. There is no `Set` operation for any configuration |
| Imaging | None. Profile S covers it as conditional |
| Events | None. Conditional in Profile S |
| PTZ | None. Conditional in Profile S |
| Audio | The RTSP side supports an audio track, the ONVIF side says nothing about it |

The profile list itself is the part that works best. `GetProfiles` returns a `VideoSourceConfiguration` and a `VideoEncoderConfiguration` per profile, with the right tokens, and `GetStreamUri` resolves them. That is the path an NVR takes: discover, list, connect.

What a client cannot do is change anything. For a camera that is fine, and it is what the vendor device does as well.

### The version it reports

```
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:63
<tds:Version><tds:Major>2</tds:Major><tds:Minor>60</tds:Minor></tds:Version>
```

Version 2.60 is the Media 1 era. A client that asks for a newer version gets the same answer. That is what the vendor ships, and it works with the NVRs that were tested.

### Profile T, if it is wanted

Profile T is the one that is not deprecated, and it is the one most new NVRs default to. It is a bigger job:

| | Profile S, what the code does | Profile T |
|---|---|---|
| Media service | Media 1, `ver10` | Media 2, `ver20`, the `tr2` prefix |
| Imaging | none | `GetImagingSettings`, `SetImagingSettings`, and the whole imaging configuration tree |
| Events | none | The event service, `ver10/events/wsdl` |
| Metadata | none | `GetMetadataConfigurations`, and the metadata stream over RTSP |
| ONscreen display | none | Mandatory for the device in Profile T |
| HTTPS | no | Mandatory in Profile T |
| H.265 | no | Mandatory in Profile T |

Moving the media service from Media 1 to Media 2 is not a namespace swap. The operation names change, the request and response types change, and the configuration model changes from a flat structure to the Media 2 tree with `VideoSourceConfiguration` and `VideoEncoderConfiguration` extensions.

That is a separate project. The honest position is: the vendor implementation is a Profile S device, it works with the NVRs it was tested against, and it is what the minimal image gets.

### Authentication

`checkAuth` in `onvif_soap.cpp` implements the WS-UsernameToken. The password is accepted as plaintext or as `Base64(SHA1(Nonce + Created + password))`, which is the digest form ONVIF clients send. Credentials are compared against the registered profiles.

### Why this beats a new implementation

The alternative was `roleoroleo/onvif_simple_server`, a C implementation for constrained devices that runs as CGI under BusyBox httpd. It is a good project, but there are three reasons to prefer what the vendor wrote:

- **No new dependency tree.** The vendor version needs `libhv` and OpenSSL. `libhv` is already a Buildroot package in `external/br2-external/libhv`, and it is already in the image because `sscma-node` selects it. `onvif_simple_server` would need libtomcrypt, or mbedtls, or wolfssl.
- **No SOAP stack to get wrong.** The vendor version builds its XML responses with string concatenation and extracts values with a small hand written scanner. `onvif_simple_server` wraps `ezxml`. Both are minimal, neither pulls in a general purpose XML library.
- **It already works on this hardware.** The vendor version was tested against real NVRs. The CHANGELOG records the fix for the two problems that showed up in the field: a truncated `GetCapabilities` response that Hikvision NVRs read as invalid XML, and a missing `sprop-parameter-sets` in the SDP.

The one thing `onvif_simple_server` does better is that it runs as CGI under BusyBox httpd and needs no HTTP server of its own. The vendor version brings its own libhv HTTP server. That is a small cost, and libhv is already there.

### The problem: it is inside the Node-RED node

The implementation is not a standalone daemon. It is compiled into `sscma-node`, the vendor's Node-RED node binary, and it is started from the `stream` node:

```
solutions/sscma-node/main/node/stream.cpp:130
    if (onvif_) {
        onvif::Profile profile;
        ...
        err = onvif::Service::instance().registerProfile(profile, onvifPort_);
```

The `onvif::Service` is a process wide singleton. The first stream node with ONVIF enabled starts the SOAP server and the WS-Discovery responder, every registration adds a media profile, and the last unregistration shuts everything down.

In the minimal image there is no Node-RED and no `sscma-node`. So the implementation has to be lifted out into its own binary. The good news is that the code itself is nearly free of vendor dependencies.

## How the code is coupled

The coupling is much thinner than it looks. These are the only vendor symbols the ONVIF code uses:

```
ma::Guard          the mutex guard in Service::registerProfile
ma::Mutex          the mutex in Service
ma_err_t           the return type of registerProfile
PROJECT_VERSION    the firmware version string
```

`ma::Mutex` and `ma::Guard` come from `porting/ma_osal.h`, which is part of the `SSCMA-Micro` submodule. `PROJECT_VERSION` comes from a generated `version.h`.

Everything else is standard: libhv for HTTP, OpenSSL for SHA1, and the POSIX sockets API for the discovery responder.

There is **no reference to the video pipeline at all**. No `CVI_`, no `VPSS`, no `VENC`, no `MPI`. The ONVIF service never touches the sensor, the encoder or the RTSP server. It only describes them.

The profiles carry the information the client needs:

```cpp
struct Profile {
    std::string token;   // RTSP session name, unique per RTSP port
    std::string rtspPath;  // e.g. "/live"
    int rtspPort   = 554;
    std::string username;
    std::string password;
    int width  = 1920;
    int height = 1080;
    int fps    = 30;
};
```

And `GetStreamUri` turns them into a URL:

```
rtsp://<client-ip>:<rtspPort><rtspPath>
```

The client IP is taken from the SOAP request, so the URL is correct for every client.

## The plan

Lift the ONVIF implementation out of the Node-RED node into a small standalone daemon that lives in the minimal image.

```
                    ┌──────────────────────────────┐
   ONVIF client ───▶│ onvifd (new daemon)          │
   (NVR, VMS)       │  ├─ SOAP over HTTP (libhv)    │
                    │  └─ WS-Discovery (UDP 3702)   │
                    └──────────────┬───────────────┘
                                   │ describes
                    ┌──────────────▼───────────────┐
                    │ cvi_rtsp                     │
                    │  rtsp://<ip>:554/live         │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │ sensor → VI → VPSS → VENC      │
                    └──────────────────────────────┘
```

### Step A: Extract the module

Move the eight files into a new Buildroot package in the minimal external tree. Keep them in the `ma::node::onvif` namespace or rename it, either way the code is unchanged.

```
external/br2-external-minimal/onvifd/
├── Config.in
├── onvifd.mk
├── onvif_service.cpp
├── onvif_service.h
├── onvif_soap.cpp
├── onvif_soap.h
├── onvif_utils.cpp
├── onvif_utils.h
├── onvif_discovery.cpp
├── onvif_discovery.h
└── main.cpp
```

`main.cpp` is new and small. It reads the configuration, registers the profiles, and starts the service:

```cpp
int main(int argc, char** argv) {
    Config cfg = loadConfig(argv[1]);
    onvif::Service::instance().registerProfile(cfg.main, cfg.port);
    onvif::Service::instance().registerProfile(cfg.sub,  cfg.port);
    onvif::Service::instance().wait();
}
```

### Step B: Replace the two vendor symbols

`ma::Mutex` and `ma::Guard` become `std::mutex` and `std::lock_guard`. The mutex in `Service` is `mutable Mutex mutex_` and the guard is used in `registerProfile` and `unregisterProfile`. That is a two line change per file.

`ma_err_t` becomes `int`. It is only used as the return value of `registerProfile`, and the callers only check whether it is zero.

`PROJECT_VERSION` becomes a string from the build configuration.

### Step C: The configuration file

The device identity comes from the same place the vendor gets it, the U-Boot environment:

```cpp
const std::string& serialNumber() {
    ...
    popen("fw_printenv -n sn 2>/dev/null", "r")
    ...
}
```

`fw_printenv` is in `uboot-envtools`, which is already in the image because `libubootenv` is enabled. The fallback is the hostname.

### Step D: The RTSP session names

The vendor stream node names its session from the Node-RED configuration:

```
solutions/sscma-node/main/node/stream.cpp:70
    session_ = "live";
```

and derives the path from it:

```
solutions/sscma-node/main/node/stream.cpp:133
    profile.rtspPath = "/" + session_;
```

So the ONVIF profile points at `rtsp://<ip>:554/live`. The `cvi_rtsp` service configuration in the minimal image has to use the same session name. This is the one place where the two sides have to agree.

### Step E: The port

The vendor default is 8899:

```
solutions/sscma-node/main/node/stream.cpp:14
    onvifPort_(8899)
```

The ONVIF service port is separate from the RTSP port. 8899 is fine, it does not collide with anything in the image.

## What this step does not do

- **No PTZ.** The vendor implementation has no PTZ support. A camera with a gimbal would need the four ONVIF PTZ operations added. The gimbal talks CAN, and the CAN side was in `node-red-contrib-seeed-recamera`.
- **No snapshot.** There is no snapshot operation in the vendor implementation. Many clients show a blank thumbnail without it.
- **No events.** There is no event service. Without the AI stack there is nothing to report anyway.
- **No configuration.** Nothing in the implementation changes a setting. The camera is configured through the ONVIF profile list and the RTSP stream, not through ONVIF.
- **No Profile T.** The implementation is a Profile S device, and Profile S is being deprecated. See the profile section above.

These are the same gaps that `onvif_simple_server` would have. They are additive work on top of the extracted module, not a reason to choose a different implementation.

### The Profile S question, stated plainly

The decision to use the vendor implementation means the image ships a **Profile S** device. That has three consequences:

| Consequence | What it means |
|---|---|
| It works | The vendor version was tested against real NVRs, and the field bugs are fixed. Hikvision and Dahua NVRs are the ones that were tested. |
| It is not conformant | A conformant device needs the full operation set of the profile. This is a working subset. |
| It is on a retiring profile | Profile S conformance submissions close on 31 March 2027. |

Whether that is the right trade depends on what the camera is for. For a camera that shows up in an NVR and streams, it is the right trade, because the alternative is writing an ONVIF implementation from scratch, which is a much bigger job than adding Profile T to an existing one.

If a new NVR is the target and it only speaks Profile T, then the work is different: the media service moves to Media 2, the imaging service and the event service get added, and the whole configuration model changes. That is its own project, the same way a kernel port is.

## Where the code comes from

The files are copied from the public repository, with the Apache-2.0 license header kept:

```
https://github.com/Seeed-Studio/sscma-example-sg200x
  solutions/sscma-node/main/node/onvif/
```

The upstream commit that introduced the feature is `4926df7`, "feat(node): make RTSP audio track opt-in for NVR compatibility", which is the same commit that added the ONVIF files. The implementation was developed against real NVRs and the fixes for the truncated `GetCapabilities` response and the missing SDP parameters are in it.

The fork of `sscma-example-sg200x` that the build uses is the Git variant, not the `reCamera.zip` blob:

```
external/br2-external/sscma-node/sscma-node.mk:8
SSCMA_NODE_SITE = https://github.com/Seeed-Studio/sscma-example-sg200x
SSCMA_NODE_SITE_METHOD = git
SSCMA_NODE_LICENSE = Apache-2.0
```

The blob variant is in `external/br2-external/reCamera/` and is disabled (`default n`). It points at a branch that no longer exists upstream, so it cannot be built. The Git variant is the one to use.
