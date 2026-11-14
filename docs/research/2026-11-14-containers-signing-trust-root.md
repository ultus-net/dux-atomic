# Containers signing trust root (issue #4)

Status: research only. Cutoff 2026-11-14. This record collects the verified
behaviour of the host-side verifier, what this repository already signs, and the
trust-root choices the operator can make. It does not choose a policy, generate
a key, or ship a policy file.

Finding: the container libraries Podman and Skopeo use accept only a CA and two
Fulcio identity fields, `oidcIssuer` and `subjectEmail`, and they match the
subject against the certificate's `EmailAddresses` only. This repository signs
keyless and its certificate carries the workflow as a URI SAN, so no
`sigstoreSigned` policy can name it today.

## What the host verifier can check

`signature/policy_types.go` defines the Fulcio inputs as `CAPath` or `CAData`,
`OIDCIssuer`, and `SubjectEmail`, and nothing else:

```
163: // CAPath a path to a file containing accepted CA root certificates, in PEM format. Exactly one of CAPath and CAData must be specified.
164: CAPath string `json:"caPath,omitempty"`
167: // OIDCIssuer specifies the expected OIDC issuer, recorded by Fulcio into the generated certificates.
168: OIDCIssuer string `json:"oidcIssuer,omitempty"`
169: // SubjectEmail specifies the expected email address of the authenticated OIDC identity, recorded by Fulcio into the generated certificates.
170: SubjectEmail string `json:"subjectEmail,omitempty"`
```

`signature/fulcio_cert.go` matches a Fulcio certificate by checking the
certificate's `EmailAddresses` against the configured `subjectEmail`, and
rejects when the address is absent. A certificate that carries only a URI SAN
has no `EmailAddresses` entry to match, so the workflow identity cannot be named
by that field. Both files were read from `containers/image` `main` on
2026-11-14.

The whole digest-signing path is `sigstoreSigned`: either a public key from
`keyPath` or `keyData`, or the Fulcio and Rekor path above. A repository key
therefore needs no upstream change, and a keyless identity needs one.

## What this repository signs

The `publish` job runs `cosign sign --yes "$IMAGE@$digest"` with no `--key`, so
the signature comes from the runner's OIDC identity through Fulcio
(`.github/workflows/ci.yml:327`). The `verify` job pins two values when it checks
the digest and the attestation (`:412`-`:413` and `:430`-`:431`):

- `--certificate-identity "https://github.com/ultus-net/dux-atomic/.github/workflows/ci.yml@refs/heads/main"`
- `--certificate-oidc-issuer https://token.actions.githubusercontent.com`

Those are the identity and issuer a host policy would have to name. The identity
is a URI SAN, which is the field the verifier cannot read.

## The options

| Option | Policy content | Who holds it | Proves | Cannot prove | Cost |
| --- | --- | --- | --- | --- | --- |
| Repository release key | `sigstoreSigned` with a `keyPath` to the repository public key, plus a `registries.d` entry where needed | The operator, in CI secrets or offline | The holder of that private key signed this digest | Which workflow run signed, and nothing beyond that key | A custody plan, a rotation plan, a host rollout of the public key, and a revocation story |
| Keyless with a narrower matcher | `sigstoreSigned.fulcio` naming `buildSignerURI` once `container-libs#625` merges | Fulcio, per workflow run | The OIDC issuer authenticated that workflow, and the builder URI matches the policy | Operator control beyond the workflow identity; a compromised runner token can still sign | No key custody, and a dependency on upstream merges for the matcher and the bundle format |
| No shipped policy | Nothing | Nobody | Nothing at pull time | Any provenance, so a forged image is accepted | Zero now, and the risk stays recorded in `docs/known-gaps.md` |
| A vendor key | `sigstoreSigned` with the vendor public key and their `registries.d` endpoints | The vendor | The vendor signed the image | That this repository built it | Low, and it answers a different question than ours |

`tests/test-signing.sh` already exercises the first option end to end with a
fixture key and a throwaway registry, including the rejection cases. `#625` is
open and titled "image: Add buildSignerURI for Fulcio workflow identity
verification". `container-libs#388` is open and titled "Support Sigstore bundle
format", and it carries both the bundle-format gap and the URI-against-email
mismatch.

## Custody questions the operator answers

- Who may sign an official digest: a person, a gated pipeline, or both?
- Where does the private key live, and who can reach it: CI secrets, an HSM, or an offline signer?
- How is the key rotated, and how do hosts learn the new root without a gap?
- What is the revocation path, and who can invoke it in an emergency?
- Do attestations share the digest key, or use a separate one?
- Is signing online in CI, or offline on an operator machine?

## Recommendation, not a decision

Recommendation, not a decision: ship a repository release key named by `keyPath`,
with the public key published for hosts and a written rotation and revocation
plan. It is the only option that works with the libraries as they are, and
`tests/test-signing.sh` proves the mechanism. Migrating to keyless with
`buildSignerURI` becomes an upgrade once `#625` merges.

The operator chooses. This record generates no key and ships no policy.

## What this record does not prove

- No policy file exists in this image, so no host verifies a pulled digest.
- No keypair was generated, and no key material was added to CI.
- No image was verified against a shipped policy.
- The bundle-format claim rests on `#388`, not on a local reproduction.

## Sources

| Source | URL | Fetched | Used as |
| --- | --- | --- | --- |
| `containers/image` `signature/policy_types.go` | https://raw.githubusercontent.com/containers/image/main/signature/policy_types.go | 2026-11-14 | Quoted, the Fulcio fields |
| `containers/image` `signature/fulcio_cert.go` | https://raw.githubusercontent.com/containers/image/main/signature/fulcio_cert.go | 2026-11-14 | Quoted, the `EmailAddresses` match |
| `container-libs` issue #388 | https://github.com/podman-container-tools/container-libs/issues/388 | 2026-11-14 | Paraphrased, bundle format and SAN mismatch |
| `container-libs` pull #625 | https://github.com/podman-container-tools/container-libs/pull/625 | 2026-11-14 | Quoted, title and the `buildSignerURI` matcher |
| `.github/workflows/ci.yml` | this repository, `:327`, `:412`-`:413`, `:430`-`:431` | 2026-11-14 | Quoted, the sign and verify commands |
| `tests/test-signing.sh` | this repository | 2026-11-14 | Paraphrased, the fixture-key accept and reject |
| Red Hat registry signing article | https://access.redhat.com/articles/3116561 | 2026-11-14 | Paraphrased, the vendor-key option |
