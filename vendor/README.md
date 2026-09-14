# Vendor middleware

The HYPERSECU/ePass2003 `libcastle_v2.1.0.0.dylib` file is intentionally not
stored in Git. For local builds, place an authorized copy in this directory.
For GitHub Actions builds, configure `EPASS_DRIVER_URL` and
`EPASS_DRIVER_SHA256` as repository secrets. Use the optional
`EPASS_DRIVER_TOKEN` secret when the URL requires bearer authentication.
