# ONVIF

ONVIF is a direct goal of the minimal image, not a later idea.

The camera speaks RTSP already. ONVIF is the discovery and configuration
layer on top of it: a client asks the camera what it can do, gets a list of
profiles with stream URLs, and connects to them.

## The approach

Use `onvif_simple_server` as it is. Do not write an ONVIF implementation.

```
name:     roleoroleo/onvif_simple_server
license:  GPL-3.0
language: C
size:     889 KB
pushed:   2026-11-11
```

The description says it: "Light implementation of an onvif server intended for
use in resource-constrained devices". It implements Profile S and Profile T,
which is what a camera needs.

Why this one:

- **No gsoap, no libxml.** The XML handling is a wrapper around `ezxml` with
  a template based strategy. That is the difference between a server that
  fits and one that does not.
- **It runs as CGI.** It does not need its own HTTP server. BusyBox `httpd` is
  already in the image and can run it.
- **It is small.** Three binaries, the whole thing is under a megabyte of
  source.
- **It is active.** The last commit is from November 2026.

The alternative, `KoynovStas/onvif_srvd`, is a daemon in C++ with 349 stars.
It brings its own HTTP server and a heavier dependency tree. The upside would
be better conformance, the downside is a bigger image.

## How it fits together

```
                    ┌──────────────────────────────┐
   ONVIF client ───▶│ busybox httpd                │
   (NVR, VMS)       │  └─▶ onvif_simple_server (CGI)│
                    └──────────────┬───────────────┘
                                   │ answers with profiles
                                   │ and stream URLs
                    ┌──────────────▼───────────────┐
                    │ cvi_rtsp                     │
                    │  rtsp://<ip>:554/ch0_0.h264  │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │ sensor → VI → VPSS → VENC      │
                    └──────────────────────────────┘
```

The ONVIF server never touches the video pipeline. It only describes it.
The stream URL in the configuration points at the RTSP server.

## Configuration

The server reads one configuration file. The relevant part for the reCamera:

```
model=reCamera
manufacturer=Seeed Studio
firmware_ver=0.2.4
hardware_id=C1-2002
serial_num=100018917254200065
port=8080
scope=onvif://www.onvif.org/Profile/Streaming
scope=onvif://www.onvif.org/Profile/T
scope=onvif://www.onvif.org/hardware
scope=onvif://www.onvif.org/name

#Profile 0, main stream
name=Profile_0
width=1920
height=1080
url=rtsp://%s:554/ch0_0.h264
type=H264
framerate=30

#Profile 1, sub stream
name=Profile_1
width=640
height=360
url=rtsp://%s:554/ch0_1.h264
type=H264
framerate=15
```

`%s` is replaced with the address of the client, so the same configuration
works for clients from different networks.

## What the camera needs to provide

### Two streams

ONVIF expects a main and a sub stream. The chip has the capacity:

```
VENC_MAX_CHN_NUM   16
```

Two encoder channels are plenty.

### The RTSP paths

The configuration points at `rtsp://%s:554/ch0_0.h264` and `ch0_1.h264`. The
`cvi_rtsp` service takes a JSON file that defines the video sources. The
names of the sessions in that JSON have to match the paths in the ONVIF
configuration.

### PTZ, optional

The configuration has a PTZ section that calls out to scripts for the
position and the movement commands. The reCamera gimbal uses CAN, and the
`node-red-contrib-seeed-recamera` package had the CAN side.

PTZ is optional in ONVIF. A camera without a gimbal simply leaves the
section out. If the gimbal is wanted, the four scripts are small wrappers
around the CAN interface:

```
get_position
is_moving
move_left, move_right, move_up, move_down, move_in, move_out, move_stop
```

### Snapshot, optional

```
snapurl=http://%s/cgi-bin/snapshot.sh
```

A CGI script that writes one JPEG. The pipeline already produces JPEG, the
encoder supports `CVI_RTSP_VIDEO_JPEG`.

### Events, optional

The notify server reads event state from files:

```
input_file=/tmp/onvif_notify_server/motion_alarm
```

The sscma inference that was in the original image produced exactly that kind
of event. Without the AI stack there is no motion detection, so the events
section stays out.

## The three binaries

| Binary | Purpose | Needs |
|---|---|---|
| `onvif_simple_server` | The device, media and PTZ services, runs as CGI | HTTP server |
| `onvif_notify_server` | The event notify service | Its own port |
| `wsd_simple_server` | Web services discovery, so clients find the device | Its own port |

Web services discovery is what makes the camera show up automatically in a
client. It listens on UDP 3700 and answers with the ONVIF endpoint.

## Dependencies

All of them exist in Buildroot:

| Need | Buildroot package | Note |
|---|---|---|
| HTTP server | busybox `httpd` | Already in the image |
| Crypto | libtomcrypt | Or mbedtls or wolfssl, the Makefile picks |
| Compression | zlib | Already in the image |
| JSON | json-c | Already in the image |

Buildroot has no ONVIF package, so this needs a new one in the minimal
external tree. The upstream project has a plain Makefile, no autotools. A
Buildroot package is therefore short.

## OpenVINO and the other half

There is a second ONVIF piece, the SOAP API. It is what a client uses to
change settings: PTZ commands, image settings, stream configuration.

`onvif_simple_server` covers the discovery side with its templates, but the
SOAP actions that change state need real endpoints. The project has an
`extras` folder with an example for that.

For the minimal image the split is:

- The templates cover `GetProfiles`, `GetStreamUri`, `GetDeviceInformation`,
  `GetCapabilities` and the service list. That is what a client needs to
  find the camera and to play the stream.
- The SOAP actions for changing things are only needed if the camera has
  something to change. PTZ and the image settings qualify.

## Plan

1. New buildroot package for `onvif_simple_server`
2. Configuration file with the camera identity and the two profiles
3. Busybox httpd configured to run the CGI
4. The RTSP service configured with two sessions, named to match
5. A snapshot CGI script
6. PTZ, if the gimbal is in scope
7. The notify server, if events are in scope

Steps 1 to 4 are the base. A client finds the camera, sees two profiles and
plays the stream.
