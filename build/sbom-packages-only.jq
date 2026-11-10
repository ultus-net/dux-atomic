# The attested SBOM keeps packages only.
#
# Rekor's public instance answers 502 above a request-body limit, and the
# RPM-owned file inventory pushed this image's DSSE envelope to about 86 MB.
# Run 42810574149 measured 64181348 bytes with the files and 6657784 without.
# Drop the files, then drop every relationship that pointed at one, so the
# document keeps no dangling reference.
(.files // [] | map({(.SPDXID): true}) | add // {}) as $files
| .files = []
| .relationships = ((.relationships // []) | map(select($files[.relatedSpdxElement] | not)))
