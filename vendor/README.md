# Vendor middleware

No middleware binary is stored in Git. The platform build scripts download
checksum-pinned public packages when they run. macOS and Windows use public
vendor/eMudhra downloads. The Linux build uses a pinned public archival copy
because no current vendor-hosted Linux package is available.
