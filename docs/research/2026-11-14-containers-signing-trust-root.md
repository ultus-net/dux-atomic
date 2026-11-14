# Containers signing trust-root options (2026-11-14, issue #4)

Status: research only. This record collects verified behaviour, the repository's existing assertions, and a concise comparison of trust-root choices. It does not choose a policy, generate keys, or ship a policy file.

Lead verdict: the host-side verifier used by Podman/Skopeo (containers/image via container-libs) currently accepts only a CA and two Fulcio identity fields (`oidcIssuer` and `subjectEmail`) and matches the subject against certificate EmailAddresses only; our CI signs keyless and asserts a workflow URI (a URI SAN) that that verifier does not match today. The practical operator choices are: ship a repository release key (keyPath), adopt keyless once upstream matchers and bundle support land, trust a vendor key, or leave the status quo.

1) What the shipped mechanism can verify (precise fields and matcher behaviour)

- Policy schema: the in-tree `sigstoreSigned` policy type exposes Fulcio configuration fields that are accepted when a policy requirement uses Fulcio. The source defines `CAPath` / `CAData`, `OIDCIssuer`, and `SubjectEmail` as the Fulcio inputs. (Quoted)

  Source: https://github.com/containers/image/blob/main/signature/policy_types.go#L138-L176 (raw: https://raw.githubusercontent.com/containers/image/main/signature/policy_types.go) — fetched 2026-11-14. (Quoted: shows `CAPath`/`CAData`, `OIDCIssuer`, `SubjectEmail`.)

- Verifier behaviour: the Fulcio verifier extracts the recorded OIDC issuer from certificate extensions and then requires that the configured subject email appears in the certificate's EmailAddresses SAN. If the email is missing the verifier rejects. The verifier does not match URI SANs today; the code contains a FIXME about matching more subject types. (Quoted)

  Source: https://github.com/containers/image/blob/main/signature/fulcio_cert.go#L120-L190 (raw: https://raw.githubusercontent.com/containers/image/main/signature/fulcio_cert.go) — fetched 2026-11-14. (Quoted: `slices.Contains(untrustedCertificate.EmailAddresses, f.subjectEmail)` and surrounding logic.)

- Attachment discovery: containers/image discovers cosign legacy `.sig` attachments from the registry when `use-sigstore-attachments: true` is set in a registries.d entry. The `sigstoreSigned` path relies on either local public keys (keyPath/keyData) or the Fulcio+Rekor path above. (Paraphrased — see containers/image docs and upstream issue discussion below.)

2) What this repository signs (from CI and docs)

- How CI signs: the `publish` job runs `cosign sign` with no `--key` argument (keyless), so it uses the runner's OIDC identity via Fulcio to produce a short-lived certificate. (`.github/workflows/ci.yml` sign step runs `cosign sign --yes "$IMAGE@$digest"`.) (Quoted from this repo's workflow, fetched 2026-11-14.)

- What CI asserts when verifying: the `verify` job calls `cosign verify` and `cosign verify-attestation` pinned to a certificate identity that is the workflow URI and to the Actions OIDC issuer. Example (quoted from the workflow):

  - `--certificate-identity "https://github.com/ultus-net/dux-atomic/.github/workflows/ci.yml@refs/heads/main"`
  - `--certificate-oidc-issuer https://token.actions.githubusercontent.com`

  Source: `.github/workflows/ci.yml` lines 410-416 and 428-433 in this tree (fetched 2026-11-14). (Quoted)

- Consequence: CI produces a Fulcio certificate whose SAN records the workflow as a URI (the identity the publish job asserts). The in-tree verifier accepts only an email-based subject match today, so that workflow URI cannot be matched by a `sigstoreSigned.fulcio.subjectEmail` policy entry. (Paraphrased; see upstream issue #388 and PR #625 below.)

3) Options (one row per option)

Below are the operator options, with what the host policy file would contain, who holds the identity, what a successful verify proves, what it cannot prove, and the operational cost.

- Option 1 — Repository release keypair (keyPath)

  - Policy JSON: `sigstoreSigned` or `signedBy` referencing a public key via `keyPath` (or `signedBy` with `keyType: "X509Certificates"` / `keyPath`). Example fixture: tests/test-signing.sh writes a policy whose `keyPath` is the fixture public key. (Quoted: tests/test-signing.sh lines 91-107.)
  - Identity named: repository public key file at `/etc/pki/.../repo.pub`.
  - Who holds private key: operator/CI (secrets) or HSM under operator control.
  - Proves: cryptographic binding that the operator-held private key signed the digest.
  - Cannot prove: which workflow run produced the signature (only that the key was used). A compromised private key allows arbitrary forgery.
  - Operational cost: medium. Requires secure private key storage, rotation plan, host rollout of public key, and a revocation/rotation story.

- Option 2 — Keyless with narrower matcher (buildSignerURI) once upstream support lands

  - Policy JSON: `sigstoreSigned` with `fulcio: { caPath:..., oidcIssuer:..., buildSignerURI: "https://.../workflow@ref" }, rekorPublicKeyPath: ...` (PR #625 example).
  - Identity named: Fulcio-issued BuildSignerURI OID value (exact workflow URI string).
  - Who holds private key: no repository private key; Fulcio issues ephemeral certs after the OIDC provider authenticates the workflow.
  - Proves: the OIDC issuer authenticated the workflow identity and Fulcio recorded the BuildSignerURI OID that matches the policy; Rekor inclusion can be required to bind the event. This ties signing to the workflow invocation, not a long-lived key.
  - Cannot prove: operator control beyond the workflow-run identity semantics; if CI runner tokens or workflow privileges are compromised they can sign.
  - Operational cost: low custody cost, but depends on upstream merging of a `buildSignerURI` matcher and Sigstore bundle format support in the host libraries. If upstream does not land it, the operator can run a verification plugin or out-of-tree wrapper, with additional maintenance cost.

- Option 3 — Ship no policy (status quo)

  - Policy JSON: nothing for this repository; hosts accept images per default.
  - Identity named: none.
  - Who holds private key: n/a.
  - Proves: nothing at host pull-time.
  - Cannot prove: any cryptographic provenance. Hosts cannot reject forged or unauthenticated images.
  - Operational cost: zero immediate cost; security risk remains. (See `docs/known-gaps.md`.)

- Option 4 — Trust a vendor / upstream published signing key (example: Red Hat)

  - Policy JSON: `signedBy` with `keyPath` pointing at vendor public key and registries.d pointing at vendor sigstore endpoints (Red Hat examples exist).
  - Identity named: vendor public GPG/X.509 key.
  - Who holds private key: vendor.
  - Proves: the image was published/signed by vendor production signing key (useful for consuming vendor images).
  - Cannot prove: that our repository built the image.
  - Operational cost: low–moderate (configure hosts with vendor key and registries.d entries). See Red Hat doc cited below.

Notes and evidence pointers for the options:
- Option 1 is exercised by tests/test-signing.sh, which generates a keypair and demonstrates acceptance and rejection with a `keyPath` policy (see tests/test-signing.sh lines ~80–112 and case checks). (Quoted)
- Option 2 is the subject of podman-container-tools PR #625 (buildSignerURI) which proposes an explicit BuildSignerURI matcher and example policy JSON; the container-libs issue #388 records both the bundle-format gap and the SAN vs email mismatch. (Sources cited below.)
- Option 3 is the current state recorded in `docs/known-gaps.md`. (Quoted)
- Option 4 is illustrated in vendor documentation such as Red Hat's article describing how to add their public key and registries.d sigstore endpoints. (Source cited below.)

4) Custody questions the operator must answer

- Who is authorised to sign an official repository digest? A human role, a gated pipeline, or both? How are those actors identified?
- Where does the private key live (CI secrets, HSM, offline signer)? Who has access?
- How is the private key rotated? How are hosts updated atomically or safely to trust the new root? What's the revocation story for the old key?
- Are attestations (SBOM, SLSA/provenance) signed with the same identity as the digest, or a separate attestation key? (Separate keys reduce blast radius.)
- What is the recovery plan if the signing key is lost or leaked? Who can authorize emergency rotation and how are hosts re-provisioned?
- Is signing performed online in CI (fast, needs secrets or keyless OIDC) or offline by an air-gapped operator (slower, smaller blast radius)?

5) Recommendation, not a decision

Recommendation, not a decision: initially ship a repository-managed release key referenced by `keyPath` and publish the public key for hosts to consume, together with a documented rotation and emergency revocation plan. Evidence: the host libraries in common container runtimes accept `keyPath` today and `tests/test-signing.sh` already proves this path locally. This yields deterministic, operator-owned trust immediately while leaving migration to keyless + `buildSignerURI` (Option 2) as an upgrade path when upstream matchers and bundle-format verification land in container-libs / containers/image.

This is a recommendation only. The operator must choose: this record does not perform the key generation, rotation policy, or the policy rollout.

6) What this record does not prove

- No policy file was written or installed on behalf of the operator.
- No keypair was generated by this work, and no key material was added to CI.
- No host was configured to verify images with a shipped policy. No image was verified by such a policy.

---

Sources (fetched 2026-11-14)

- containers/image `signature/policy_types.go` — raw source; defines `prSigstoreSigned` and `prSigstoreSignedFulcio` fields (CAPath/CAData, OIDCIssuer, SubjectEmail). https://raw.githubusercontent.com/containers/image/main/signature/policy_types.go (fetched 2026-11-14). (Quoted)

- containers/image `signature/fulcio_cert.go` — raw source; verifier checks EmailAddresses SAN only and rejects when required email not present. https://raw.githubusercontent.com/containers/image/main/signature/fulcio_cert.go (fetched 2026-11-14). (Quoted)

- podman-container-tools/container-libs issue #388 — "Support Sigstore bundle format" (discusses cosign v3 bundle format, SAN vs email matching, and test reports). https://github.com/podman-container-tools/container-libs/issues/388 (fetched 2026-11-14). (Paraphrased)

- podman-container-tools/container-libs PR #625 — `buildSignerURI` matcher proposal and example policy JSON. https://github.com/podman-container-tools/container-libs/pull/625 (fetched 2026-11-14). (Paraphrased / example quoted in the PR)

- This repository: `.github/workflows/ci.yml` (sign and verify steps) and `tests/test-signing.sh` (fixture key acceptance). (this worktree, fetched 2026-11-14). (Quoted)

- Red Hat: "Verifying image signing for Red Hat Container Registry" — example of vendor key approach and registries.d usage. https://access.redhat.com/articles/3116561 (fetched 2026-11-14). (Paraphrased / example quoted)
