# JSignPDF All-in-One

This repository builds self-contained JSignPDF applications for macOS,
Windows, and Linux containing:

- the official upstream JSignPDF application and bundled Java runtime;
- the HYPERSECU/ePass2003 PKCS#11 library;
- isolated, automatically generated PKCS#11 configuration; and
- a launch-time updater backed by this repository's GitHub Releases.

No system Java installation is used. On first launch macOS may still request
permission to access the USB token or ask the user to approve an unsigned app.

The generated platforms are macOS Apple Silicon, Windows x64, and Linux x64.

## Build locally

```sh
./scripts/build_bundle.sh
```

On Linux run `./scripts/build_linux.sh`. On Windows run
`powershell -File scripts/build_windows.ps1`.

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

The `Build upstream bundles` workflow runs after relevant pushes, daily, and on
manual dispatch. It verifies the upstream release assets' SHA-256 digests,
builds all three bundles, and creates or refreshes `v<upstream-version>`.

No repository secrets are required. Middleware is downloaded from pinned public
URLs and verified before being included. The macOS source is eMudhra's public
`ePass2003_MAC_iOS.zip`; the Windows source is Hypersecu's current public
HYP2003 middleware. The Linux module is a checksum-pinned archival copy and
should be replaced if the vendor publishes a current Linux package.

OpenSC supports standard Feitian ePass2003 tokens and is a good open-source
alternative when the token appears through CCID/PCSC. It is not the default here
because some HYP2003/eMudhra variants—including the device used to validate this
bundle—do not expose a reader or slot to OpenSC, while the vendor module works.

## Third-party notice

JSignPDF is downloaded from its upstream release and retains its upstream
licensing. The downloaded `libcastle_v2.1.0.0.dylib` is vendor middleware for
the HYPERSECU/ePass2003 token and is not covered by this repository's
source-code terms. Anyone publishing or redistributing releases must ensure
they have the right to redistribute that vendor binary.
