# Containers signing trust-root decision (issue #4)

Status: decision record. Cutoff 2026-11-14. The operator chose the trust root on
that date after reading `docs/research/2026-11-14-containers-signing-trust-root.md`.
This record changes no policy, generates no key, and touches no workflow.

## Decision

- **Trust root: a repository release key, named by `keyPath`.** The policy this
  repository ships will be `sigstoreSigned` with a `keyPath` to a public key
  this project owns. A host that trusts that key verifies the image it pulls.
- **Keyless is the migration, not the start.** Once `container-libs#625` lands
  the `buildSignerURI` matcher, the policy moves to `sigstoreSigned.fulcio` and
  names the workflow identity. Until then a keyless policy cannot work.

## Why the keyless path cannot be chosen now

The verifier accepts three Fulcio inputs and nothing else: `caPath` or
`caData`, `oidcIssuer`, and `subjectEmail` (`image/signature/policy_types.go:162`
through `:170`). It matches the certificate's `EmailAddresses` only
(`image/signature/fulcio_cert.go:168`), and the certificate this repository's
`publish` job receives carries the workflow as a URI SAN. There is no field to
name it with. Both quotes are in
`docs/research/2026-11-14-containers-signing-trust-root.md:20` through `:38`.

A repository key needs no upstream change, and `tests/test-signing.sh` already
proves the mechanism end to end with a fixture key and a throwaway registry,
including the rejection cases (`:83` of the same record).

## Custody answers

| Question | Answer |
| --- | --- |
| Who may sign a digest | The `publish` job only, gated on a `main` push. No person signs by hand, and no second workflow gets the secret. |
| Where the private key lives | Operator-held, offline, injected into the `publish` job as a repository secret when the policy ships. The public half is committed to this repository so hosts and reviewers can read it. |
| Rotation | Yearly, and immediately on suspected compromise. A new key ships in an image whose policy trusts both keys during the overlap. |
| Revocation | Drop the compromised key from the policy in a new image. Hosts on the old policy keep trusting it until they update, which is why the overlap window exists and why two keys are trusted during a rotation. |
| Do attestations share the digest key | Yes. One key signs the digest and the attestation, which keeps custody to one secret. |
| Online or offline signing | Online in CI. The private key is never on a workstation. |

## What this record does not do

- No keypair exists, and no secret was added to the repository.
- No `/etc/containers/policy.json` ships, so no host verifies a pulled digest
  today (`docs/known-gaps.md:18`).
- No image was verified against a shipped policy, and `tests/test-signing.sh`
  still tests a fixture key rather than the real one.
- Shipping an enforcing policy before its key is published would reject every
  pull on every host. That is why the decision lands first and the policy
  second.

## Follow-up work

Issue #4 keeps the remaining three items: generate the key and publish its
public half, write `overlay/etc/containers/policy.json` and the rotation note,
and extend `tests/test-signing.sh` with an accept and a reject against the
shipped policy. The roadmap's Task 3 carries the same three items.

## What would reverse this

`container-libs#625` merging, or `containers/image` gaining an email-address
field that a GitHub Actions certificate can satisfy. Either removes the key
custody cost, and the migration is then a policy change plus a test change.
