# The attested SBOM keeps packages only.
#
# Rekor's public instance answers 502 above a request-body limit, and the
# file inventory pushed this image's DSSE envelope to about 86 MB. Run
# 42810574149 measured 64181348 bytes with the files and 6508304 without.
# Drop the files, drop every relationship that pointed at one, and drop the
# package verification codes that covered them, so nothing still claims they
# were analyzed.
(.files // [] | map({(.SPDXID): true}) | add // {}) as $files
| .files = []
| .relationships = ((.relationships // []) | map(select($files[.relatedSpdxElement] | not)))
| .packages = ((.packages // []) | map(del(.packageVerificationCode) | .filesAnalyzed = false))
