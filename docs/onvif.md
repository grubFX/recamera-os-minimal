# ONVIF

ONVIF is a direct goal of the minimal image, not a later idea.

The camera speaks RTSP already. ONVIF is the discovery and configuration layer on top of it: a client asks the camera what it can do, gets a list of profiles with stream URLs, and connects to them.

This image targets **ONVIF Profile T**. Profile T is the profile that is not being retired, and it is the one that requires the two things this camera should have: HTTPS and H.265.

## What Profile T requires

The ONVIF profile page for Profile T lists the mandatory features:

> H.264 / H.265 video compression
> Imaging settings
> Motion alarm and tampering events
> Metadata streaming
> Bi-directional audio

> Mandatory features for devices also include onscreen display and metadata streaming, while mandatory features for clients also include PTZ control. Profile T also covers ONVIF specifications for HTTPS streaming, PTZ configuration, motion region configuration, digital inputs and relay outputs, and bidirectional audio for conformant devices and clients that support such features.

That maps onto the work in this image:

| Profile T requirement | Status in this image | What it takes |
|---|---|---|
| H.264 | available | The encoder is already there |
| H.265 | available in the hardware, not yet in the stream | The `cvi_rtsp` JSON config and the SDP patch |
| HTTPS | available in the libraries, not yet wired up | `libhv` has OpenSSL, the ONVIF server needs a TLS listener |
| Imaging settings | missing | The imaging service, and a way to apply the settings to the sensor |
| Events | missing | The event service |
| Metadata streaming | missing | The metadata stream, and an RTSP payload type for it |
| Onscreen display | missing | The OSD, and the hardware behind it |
| Bi-directional audio | conditional | The camera has a microphone, no speaker |
| PTZ | out of scope | The camera has no gimbal |

The profile also states that HTTPS streaming is part of the profile, and the Profile T specification makes TLS mandatory for the device and client services. That is not a nice to have, it is the reason Profile S is being retired.

## Profile S is being retired, and that is why this is Profile T

Profile S is deprecated. The ONVIF site says the last date for product conformance submissions is 31 March 2027. The Q&A from ONVIF spells out what that means:

> After March 31, 2027, it will not be possible for manufacturers to submit new products, or older products with new firmware/software versions, for Profile S conformance.

> As long as a device or client with a specific software or firmware version is registered as having Profile S conformance, it will remain conformant until the manufacturer decides to withdraw the Declaration of Conformance.

> The deprecation of Profile S has no effect on the operation of deployed Profile S-based systems.

So a Profile S device keeps working. What dies is the camera's own future: a new firmware release for this image cannot be submitted for Profile S conformance.

The reason for the deprecation is authentication, and that part matters directly:

> Profile S mandates the use of username token authentication. Due to the evolving nature of the cybersecurity threat landscape, the authentication method is no longer consistent with current cybersecurity recommendations.

The difference between the two profiles is therefore not a rename:

| | Profile S | Profile T |
|---|---|---|
| Media service | Media 1, `ver10` | Media 2, `ver20`, the `tr2` prefix |
| Authentication | Username token, plaintext or SHA1 digest | HTTP digest, and TLS |
| Transport | HTTP only | HTTPS is mandatory |
| Video | H.264 | H.264 and H.265 |
| Imaging | conditional | mandatory |
| Events | conditional | mandatory |
| Onscreen display | not covered | mandatory for the device |

## The vendor implementation is a Profile S device

The Seeed vendor stack that the original image is built on contains a complete ONVIF implementation, and it is in the public Apache-2.0 repository, not in a vendor blob.

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

```cpp
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:54
const char* namespaces[] = {
    "http://www.onvif.org/ver10/device/wsdl",
    "http://www.onvif.org/ver10/media/wsdl",
};
```

And the WS-Discovery responder advertises the same thing:

```cpp
// solutions/sscma-node/main/node/onvif/onvif_discovery.cpp:170
"<d:Types>dn:NetworkVideoTransmitter</d:Types>"
```

That type is the one Profile S devices answer with.

The vendor implementation also has exactly the two things ONVIF is retiring. Plain HTTP, no TLS:

```cpp
// solutions/sscma-node/main/node/onvif/onvif_service.cpp:190
return "http://" + ip + ":" + std::to_string(port) + "/onvif/device_service";
```

And the password is accepted as plaintext:

```cpp
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:304
if (password == p.password) {
    return true;  // PasswordText
}
```

Both are exactly what the ONVIF profile policy cannot fix, because a profile never changes once it is published. That is the whole reason Profile S is being retired instead of corrected.

### The version it reports

```cpp
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:63
<tds:Version><tds:Major>2</tds:Major><tds:Minor>60</tds:Minor></tds:Version>
```

Version 2.60 is the Media 1 era. A client that asks for a newer version gets the same answer.

### What is missing for Profile S conformance

The implementation is a working subset, not a conformant Profile S device. The gaps that matter for a client:

| Area | What is missing |
|---|---|
| Video encoder configuration | `GetVideoEncoderConfiguration` exists, `GetVideoEncoderConfigurations` does not |
| Video source configuration | `GetVideoSourceConfigurations` and `GetVideoSourceConfiguration` do not exist |
| The `VideoSourceConfiguration` in `GetProfiles` | Points at the hardcoded `video_src_0`, which is not a real source |
| Configuration change | Nothing. There is no `Set` operation for any configuration |
| Imaging | None |
| Events | None |
| PTZ | None |
| Audio | The RTSP side supports an audio track, the ONVIF side says nothing about it |

The profile list itself is the part that works best. `GetProfiles` returns a `VideoSourceConfiguration` and a `VideoEncoderConfiguration` per profile, with the right tokens, and `GetStreamUri` resolves them. That is the path an NVR takes: discover, list, connect.

What a client cannot do is change anything. For a camera that is fine, and it is what the vendor device does as well.

## The two open source candidates

Neither open source ONVIF server implements Media 2 either. That was checked on the source, not on the feature list in the README.

### roleoroleo/onvif_simple_server

```
stars:  95
license: GPL-3.0
pushed: 2026-11-11
```

This is the interesting one. It has the services that Profile T needs, and they are already written:

```
$ ls *service*.c
conf.c
device_service.c
deviceio_service.c
events_service.c
imaging_service.c
media2_service.c
media_service.c
ptz_service.c
```

`media2_service.c` is the Media 2 implementation, and it uses the right namespaces:

```
$ grep -ohE 'xmlns:(tr2|tt)="[^"]*"' media2_service_files/GetVideoEncoderConfigurations.xml
xmlns:tr2="http://www.onvif.org/ver20/media/wsdl"
xmlns:tt="http://www.onvif.org/ver10/schema"
```

It has the imaging service:

```
$ ls imaging_service_files/
GetImagingSettings.xml
GetMoveOptions.xml
GetOptions.xml
GetServiceCapabilities.xml
GetStatus.xml
```

And it has the event service, with the pull point subscription:

```
$ ls events_service_files/
CreatePullPointSubscription.xml
GetEventProperties_1.xml
GetEventProperties_2.xml
GetEventProperties_3.xml
GetServiceCapabilities.xml
PullMessages_1.xml
PullMessages_2.xml
PullMessages_3.xml
Renew.xml
SetSynchronizationPoint.xml
Subscribe.xml
```

It also handles H.265. The config parser accepts it:

```c
// conf.c:339
else if (strcasecmp(value, "H265") == 0)
    service_ctx.profiles[service_ctx.profiles_num - 1].type = H265;
```

And the media service renders it, but only for Media 2. This is the code that decides the encoding string:

```c
// utils.c:1605
} else if (codec == H265) {
    if (ver == 1) {
        snprintf(buffer, buffer_len, "H264");
    } else {
        snprintf(buffer, buffer_len, "H265");
    }
}
```

Media 1 answers "H264", Media 2 answers "H265". The `ver` parameter is the media version, so the same code path serves both.

But it has no TLS of its own. The TLS library is used for the digest authentication only:

```
$ grep -rniE "https|ssl_|tls_" --include=*.c --include=*.h .
./utils.c:956:    mbedtls_sha1_context ctx;
./utils.c:959:    mbedtls_sha1_init(&ctx);
./utils.c:998:    mbedtls_base64_decode(output, *output_size, &olen, input, input_size);
```

Those are the SHA1 and base64 calls of the digest authentication. There is no `SSL_CTX_new`, no `SSL_accept`, no certificate file anywhere in the source.

The reason is in the README. It is not a daemon, it is a CGI program:

> ### Create a working example with lighttpd
> - Run `/usr/local/bin/lighttpd -f /usr/local/etc/lighttpd.conf`

So the HTTPS question for this project is answered by the web server in front of it, and lighttpd does TLS.

### KoynovStas/onvif_srvd

```
stars:  349
license: GPL-2.0
pushed: 2025-01-08
```

This is a full daemon, built on gSOAP, with a WSDL-generated stub layer. It looks like the more mature project, but it is not a Profile T server:

```
$ for f in wsdl/*.wsdl wsdl/*.xsd; do ... done
wsdl/devicemgmt.wsdl -> targetNamespace="http://www.onvif.org/ver10/device/wsdl"
wsdl/media.wsdl     -> targetNamespace="http://www.onvif.org/ver10/media/wsdl"
wsdl/ptz.wsdl       -> targetNamespace="http://www.onvif.org/ver20/ptz/wsdl"
```

Media 1 for the media service. And Media 2 is nowhere in the tree:

```
$ grep -rl "ver20/media\|tr2:" .
(no output)
```

The `ver20/ptz/wsdl` namespace is a red herring. It is the PTZ namespace version, not the media version.

What it does have is a real TLS story, because gSOAP can do it:

```
# cmake/build_gsoap.cmake
set(GSOAP_SSL_C_LIBRARY   "${GSOAP_DIR}/libgsoapssl.a")
set(GSOAP_SSL_CXX_LIBRARY "${GSOAP_DIR}/libgsoapssl++.a")
```

The gSOAP build is a bundled tarball with a pinned version:

```
set(GSOAP_VERSION     2.8.92)
set(GSOAP_ARCHIVE_DIR "${CMAKE_SOURCE_DIR}/SDK")
set(GSOAP_PATCHES     soapcpp2_lex.l.patch)
```

That is a download of an archive at build time, which needs a version check against upstream. The PTZ namespace in the tree is also not something this camera needs, since it has no gimbal.

## The comparison

| | Vendor implementation | `onvif_simple_server` | `onvif_srvd` |
|---|---|---|---|
| License | Apache-2.0 | GPL-3.0 | GPL-2.0 |
| Media service | Media 1 | **Media 1 and Media 2** | Media 1 |
| Imaging service | no | **yes** | no |
| Event service | no | **yes** | no |
| H.265 in the profile list | no | **yes, for Media 2** | no |
| HTTPS | no | via lighttpd | via gSOAP |
| Tested against real NVRs | **yes** | no | no |
| HTTP server | own, libhv | CGI, needs one | own, gSOAP |
| Dependency tree | libhv, OpenSSL | libtomcrypt or mbedtls or wolfssl, zlib, json-c, ezxml | gSOAP, libtomcrypt, wsdl codegen |

**`onvif_simple_server` is the only one of the three that has the Profile T services.** That is the decisive difference, and it inverts the conclusion the vendor implementation had led to.

The license is the point against it. GPL-3.0 means the whole image would be GPL-3.0. The vendor implementation is Apache-2.0, and the rest of the vendor stack is a mix. Whether that matters depends on how the image is distributed, and it is a question for the maintainer, not a technical obstacle.

## The recommendation

Two ways to reach Profile T, and they are not equally expensive.

### Option 1: Extend the vendor implementation

Take the eight vendor files, lift them into their own binary as described below, and add the Profile T services on top.

The Media 1 to Media 2 move is the expensive part. The operation names change, the request and response types change, and the configuration model changes from a flat structure to the Media 2 tree with `VideoSourceConfiguration` and `VideoEncoderConfiguration` extensions. That is roughly the size of `media2_service.c` in `onvif_simple_server`, which is a thousand lines.

### Option 2: Take `onvif_simple_server` and add TLS

`onvif_simple_server` already has `media2_service.c`, `imaging_service.c`, `events_service.c` and `ptz_service.c`. The Profile T services exist, written and working.

What it does not have is HTTPS, and that is where the work is:

- The HTTPS termination is lighttpd's job, with `mod_openssl`. lighttpd 1.4.59 is in the Buildroot tree at `buildroot-2021.05/package/lighttpd/`, and the option is there:
  ```
  config BR2_PACKAGE_LIGHTTPD_OPENSSL
      bool "openssl support"
      select BR2_PACKAGE_OPENSSL
  ```
- The CGI interface stays on plain HTTP on localhost, and lighttpd forwards over TLS. That is the standard way to run a CGI application behind TLS, and it means the ONVIF server itself needs no TLS code.
- lighttpd needs to be enabled in the Buildroot config, it is not in the image now.

**Option 2 is the cheaper path to Profile T.** The services are the hard part and they are already written and tested by their author. The TLS is a configuration matter plus one new package.

The cost of Option 2 is the license. GPL-3.0 for the image.

### Option 3: Write the Media 2 service from the vendor code

A middle path. Keep the vendor code's structure, its Apache-2.0 header and its libhv HTTP server, and port the Media 2 service from `onvif_simple_server` into it, with the Apache-2.0 attribution. That is a reimplementation of an existing GPL file, which does not clear the license.

So Option 3 is not available as a shortcut. It is only available as an independent implementation of the Media 2 operations.

## What the vendor code is still good for

Even if the final answer is `onvif_simple_server`, the vendor code is worth reading, because it was tested against real NVRs. The CHANGELOG records the fix for the two problems that showed up in the field:

- a truncated `GetCapabilities` response that Hikvision NVRs read as invalid XML
- a missing `sprop-parameter-sets` in the SDP

Those are the kinds of problems that only show up against real hardware. `onvif_simple_server` is a clean implementation, but it is not a field tested one.

The vendor code is also the reference for how the camera's own pipeline is described in ONVIF terms: the RTSP session name, the path, the port, the resolution and the frame rate all come from the same place. That mapping has to be reproduced in whichever implementation wins.

## The plan

### Step 1: The RTSP session names

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

So the ONVIF profile points at `rtsp://<ip>:554/live`. The `cvi_rtsp` service configuration in the minimal image has to use the same session name. This is the one place where the two sides have to agree, and it is the same in all three implementations.

### Step 2: The device identity

The device identity comes from the same place the vendor gets it, the U-Boot environment:

```cpp
const std::string& serialNumber() {
    ...
    popen("fw_printenv -n sn 2>/dev/null", "r")
    ...
}
```

`fw_printenv` is in `uboot-envtools`, which is already in the image because `libubootenv` is enabled. The fallback is the hostname.

### Step 3: The H.265 stream

The hardware encoder supports H.265 completely. The `cvi_rtsp` service configuration selects the codec:

```json
"codec": "265"
```

The encoder side is in `cvi_rtsp`:

```
service/venc_helper.cpp:145   PT_H265
service/api.cpp:691            RTSP_VIDEO_H265
src/cvi_video_smss.hpp:54      RTSP_VIDEO_H265
```

The encoder driver has the H.265 specific calls:

```
osdrv/interdrv/cvi_vc_drv/cvi_vc_drv.c:508   CVI_VENC_SetH265Vui
osdrv/interdrv/cvi_vc_drv/cvi_vc_drv.c:616   CVI_VENC_SetH265Trans
```

The problem is the SDP. The local patch only handles H.264:

```
external/cvi_rtsp/patches/0001-emit-H264-sprop-parameter-sets-in-SDP.patch
```

It scans the Annex-B stream for SPS and PPS. H.265 needs VPS, SPS and PPS, and the parameter set format is different. The patch has to be extended for H.265, otherwise the client receives an SDP without the parameter sets and cannot start the decoder.

### Step 4: The TLS termination

For `onvif_simple_server`, lighttpd terminates TLS and forwards to the CGI on localhost over plain HTTP.

```
NVR ──HTTPS──▶ lighttpd :443
                  │ mod_openssl, self signed or ACME certificate
                  │ CGI over plain HTTP on 127.0.0.1
                  ▼
              onvif_simple_server
```

For the vendor implementation, `libhv` has the TLS support. The package is built with OpenSSL already:

```
external/br2-external/libhv/libhv.mk
LIBHV_DEPENDENCIES = openssl
LIBHV_CONFIGURE_CMDS
	(cd $(@D); $(TARGET_CONFIGURE_OPTS) ./configure --with-mqtt --with-openssl)
```

libhv exposes `hloop_new_ssl_server` and `hssl_new`, so the HTTPS listener is a config change rather than a code change. The service URL then becomes `https://` and the discovery responder has to advertise the `https` scheme.

### Step 5: The certificate

See the section below. The short version: a self signed certificate is enough for the ONVIF conformance, and ACME with a DNS-01 challenge is the way to get a certificate a client trusts without opening a port.

## The certificate strategy

There are three options, and they are not equally good for a camera that sits behind a router.

| | Self signed | ACME, HTTP-01 | ACME, DNS-01 |
|---|---|---|---|
| Client trusts it | only after a manual step | yes | yes |
| Needs an open port | no | **yes**, port 80 on the router | no |
| Works behind NAT | yes | no | yes |
| Works with a dynamic IP | yes | no | yes |
| Certificate lifetime | as long as you want | 90 days, renewed automatically | 90 days, renewed automatically |
| Extra dependency | none | a web server for the challenge | `curl`, `openssl`, a DNS API token |

**DNS-01 is the right one for this camera.** The point of the challenge type is which side has to be reachable:

- **HTTP-01** requires the ACME server to reach the camera over HTTP on port 80. That means a port forward on the router, or a public IP. A camera on a PoE network behind a consumer router has neither.
- **DNS-01** requires the ACME server to reach the DNS provider's API, and the camera to prove it can write a TXT record for the domain. No port has to be open anywhere, no public IP is needed, and a dynamic IP is fine, because the challenge is about the domain, not the address.

So the camera talks to the DNS API, writes the challenge record, and the ACME server checks it. The camera never has to be reachable from the internet.

### The client

`acme.sh` is the one that fits here. It is POSIX shell, and it needs exactly three things that are already in the image:

| Requirement | Status |
|---|---|
| `curl` | in the image, `BR2_PACKAGE_LIBCURL_CURL=y`, with OpenSSL |
| `openssl` | in the image, it is a dependency of libhv and of curl |
| POSIX shell | BusyBox `sh` |

`lego` is the other candidate and it does not work here. It is a Go binary and there is no riscv64 release. The releases are amd64, arm64 and armv5-7 only.

`acme.sh` has 206 DNS providers:

```
$ ls dnsapi/ | wc -l
206
```

Among them are the ones that matter for a camera that is likely to sit in a home or small office setup:

```
dns_cf.sh          Cloudflare
dns_aws.sh          AWS Route 53
dns_ali.sh          Alibaba Cloud
dns_dp.sh           DigitalOcean
dns_hetznercloud.sh Hetzner
```

The provider API needs a credential, and that is the one operational cost of this approach. A Cloudflare API token with permission to edit the DNS zone is the simplest case, and `acme.sh` reads it from the environment:

```sh
export CF_Token="..."
export CF_Account_ID="..."
```

### The HTTP-01 alternative, and why it is not the way

The image has no web server for the challenge. BusyBox httpd is not enabled:

```
# CONFIG_HTTPD is not set
```

That is in the `busybox.config` of the board. Adding it is possible, but HTTP-01 also needs the port 80 forward on the router, and it competes with the ONVIF server for the HTTP listener. DNS-01 avoids both problems.

### Where the certificate lives

The certificate and the key go into the overlay filesystem, and `acme.sh` installs a renewal hook that runs the reload of the web server. The files should not be in the image itself, because a certificate in a distributed image is a certificate everybody has.

```sh
# /etc/acme.sh/acme.sh --install --cron
```

The renewal runs from a cron job or from the init script, and the reload is a `SIGHUP` to lighttpd or a restart of the ONVIF daemon.

## The authentication

Profile T wants HTTP digest authentication, not the username token of Profile S.

The vendor implementation has the WS-UsernameToken:

```cpp
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:304
if (password == p.password) {
    return true;  // PasswordText
}
```

and the digest form of the username token:

```cpp
// solutions/sscma-node/main/node/onvif/onvif_soap.cpp:416
// Digest = B64ENCODE( SHA1( B64DECODE( Nonce ) + Date + Password ) )
```

`onvif_simple_server` has the same thing, plus the nonce handling with the size check:

```c
// onvif_simple_server.c:398
/* Reject oversized nonces before decode to guard the 128-byte buffer. */
if (strlen(security.nonce) > 172) {
    log_error("Nonce too large");
```

So the digest math is available on both sides. The difference for Profile T is that it has to be **HTTP** digest (`WWW-Authenticate: Digest`), which is a different header and a different hash from the WS-UsernameToken digest. lighttpd's `mod_auth` handles that at the server level, which is another point for the lighttpd setup.

## How the vendor code is coupled

For the case that the vendor code wins, the coupling is much thinner than it looks. These are the only vendor symbols the ONVIF code uses:

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

### The extraction, if the vendor code wins

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

`ma::Mutex` and `ma::Guard` become `std::mutex` and `std::lock_guard`. That is a two line change per file. `ma_err_t` becomes `int`, it is only used as the return value of `registerProfile` and the callers only check whether it is zero. `PROJECT_VERSION` becomes a string from the build configuration.

The port is separate from the RTSP port. The vendor default is 8899:

```
solutions/sscma-node/main/node/stream.cpp:14
    onvifPort_(8899)
```

8899 is fine, it does not collide with anything in the image.

## What this step does not do

- **No PTZ.** The camera has no gimbal. Both open source candidates have a PTZ service, and it stays unused.
- **No bi-directional audio.** The camera has a microphone but no speaker, so the audio back channel of Profile T does not apply.
- **No digital inputs or relay outputs.** The PoE variant has neither.
- **No configuration.** Nothing in the implementation changes a setting. The camera is configured through the ONVIF profile list and the RTSP stream, not through ONVIF.

## Where the code comes from

### The vendor implementation

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

### onvif_simple_server

```
https://github.com/roleoroleo/onvif_simple_server
```

The license is GPL-3.0. That is the open question in this document, and it is a question for the maintainer, not a technical obstacle.
