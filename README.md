# JSignPDF All-in-One for macOS

This repository builds an Apple Silicon JSignPDF application containing:

- the official upstream JSignPDF application and bundled Java runtime;
- the HYPERSECU/ePass2003 PKCS#11 library;
- isolated, automatically generated PKCS#11 configuration; and
- a launch-time updater backed by this repository's GitHub Releases.

No system Java installation is used. On first launch macOS may still request
permission to access the USB token or ask the user to approve an unsigned app.

## Build locally

```sh
./scripts/build_bundle.sh
```

The release-ready ZIP and checksum are written to `dist/`. To rebuild from a
specific upstream tag, pass it as the first argument:

```sh
./scripts/build_bundle.sh JSignPdf_3_1_0
```

For an offline/reproducibility test, point the script at an already downloaded
official archive:

```sh
UPSTREAM_ARCHIVE=/path/to/jsignpdf-3.1.0-macos-aarch64.zip \
  ./scripts/build_bundle.sh JSignPdf_3_1_0
```

## Automated releases

The `Build upstream bundle` workflow runs daily and can also be dispatched
manually. It verifies the upstream release asset's SHA-256 digest, builds the
bundle, and creates `v<upstream-version>` only when that release does not exist.

Configure these repository secrets before running it:

- `EPASS_DRIVER_URL`: a private HTTPS URL returning the raw
  `libcastle_v2.1.0.0.dylib` file;
- `EPASS_DRIVER_SHA256`: the expected SHA-256 of that file; and
- `EPASS_DRIVER_TOKEN` (optional): a bearer token when the private URL requires
  authentication.

Keeping the middleware behind repository secrets lets the workflow produce the
complete bundle without publishing the proprietary binary in Git history.

## Third-party notice

JSignPDF is downloaded from its upstream release and retains its upstream
licensing. The downloaded `libcastle_v2.1.0.0.dylib` is vendor middleware for
the HYPERSECU/ePass2003 token and is not covered by this repository's
source-code terms. Anyone publishing or redistributing releases must ensure
they have the right to redistribute that vendor binary.
