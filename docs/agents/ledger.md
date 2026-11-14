# RSI experiment ledger

Structured, create-only record of every base-loop attempt, accepted or
rejected. One record per iteration; append only. Never edit or delete a prior
record: a negative result is data, not clutter.

## Schema (one block per iteration)

```text
n · date (UTC) · hypothesis (falsifiable) · trace evidence · code change ·
commit SHA + git tree · artifact name + checksum · exact command/config ·
test results · eval job path · score · gains · losses · exceptions ·
token/cost/duration · interpretation · keep/revert · next hypothesis
```

Schema v2 adds two fields, required on every new record:

```text
selection score (n items) · held-out score (n items, never used for selection)
· prev-chain: sha256:<hex of the preceding record block>
```

`selection score` is the score on the items the loop selected against.
`held-out score` is the score on a disjoint item set never used for
selection. Report both (winner's curse). `prev-chain` links each record to
the sha256 of the prior record block so the create-only rule is
tamper-evident (hash-chained admission).

## Rules

- Append only. One block per iteration. No rewrites, renumbering, or deletes.
- Report `selection score` and `held-out score` side by side; a `keep`
  requires a non-empty `held-out score`. Held-out items are never reused for
  selection.
- `prev-chain` is the sha256 of the preceding record block.
- Record failures with the same care as successes; an empty failures column
  is a smell, not a clean run.
- Name idiosyncratic infrastructure/verifier constraints explicitly, so a
  later reader does not re-derive them.
- Every `keep` cites the eval run that justified it; every `revert` keeps the
  failure evidence and the next hypothesis.
- A record is written by the base loop, not a subagent.

## Records

<!-- append blocks below this line, newest last -->

### n=0 · 2026-11-14 · ledger genesis

- hypothesis (falsifiable): none. This block starts the hash chain, because `~/.config/opencode/lib/validate-ledger.cjs` requires every new record to carry a `prev-chain` equal to the sha256 of a preceding block, and this repository carried no ledger at `cdc580d`.
- trace evidence: `docs/agents/ledger.md` did not exist at `cdc580d`; the scaffold was copied from `~/.config/opencode/templates/rsi/ledger.md` and its record section was empty.
- code change: none. This is a bookkeeping block.
- commit SHA + git tree: the scaffold commit on `docs/82-tooling-inventory`; the sha is recorded in n=1, because a block cannot cite the commit it ships in.
- artifact name + checksum: none.
- exact command/config: none.
- test results: `node ~/.config/opencode/lib/validate-ledger.cjs` at this commit reports one error, `n=0: no preceding record to chain (prev-chain cannot be verified)`. That error is structural: the gate's `checkRecord` requires `prevRecord`, so no genesis block can satisfy it. Records from n=1 on are verified by the gate.
- eval job path: none.
- score: not applicable.
- gains: the chain has a first link, so every later record is verifiable.
- losses: the genesis link is checked by inspection, not by the gate.
- exceptions/idiosyncratic constraints: `prev-chain` here is the sha256 of the empty string (`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), which is the conventional empty-input digest and not the hash of a record block.
- token/cost/duration: none.
- interpretation: a tamper-evident chain needs a seed, and the seed is the one link no automated gate can check.
- keep/revert: n/a. Scaffolding, not a candidate; nothing to keep or revert.
- next hypothesis: none.

### n=1 · 2026-11-14 · tooling inventory reconciliation (#82)

- hypothesis (falsifiable): replacing the delivery split's completeness sentence with a row per `Brewfile` entry, adding one grandfather row to the placement rule, and anchoring both in `tests/test-static.sh` closes all five drifts issue #82 names, and the new check reds on each mutation it claims to catch. Falsified by any drift surviving, by the gate passing with a row deleted, or by the gate reding on the faithful inventory.
- trace evidence: `docs/developer-tooling.md:48` (the completeness claim, removed), `:43` (Homebrew row holding eight Fedora packages), `:45` (cloud-CLI row), `tests/test-static.sh:158-191` (the ordered-delivery gate, extended), `packages/Brewfile` at dotfiles `6eaffc9` (23 `brew` entries), `docs/known-gaps.md` (the "#82" bullet this record replaces).
- code change: `docs/developer-tooling.md` gains a seventh placement row ("Grandfathered: the dotfiles `Brewfile`, until the dotfiles move it"), a 23-row inventory with one row per `brew` entry, and a rewrite of the Homebrew, cloud-CLI, and known-gaps text. New `docs/research/2026-11-14-brewfile-inventory-measurement.md` records the command and verbatim output. `tests/test-static.sh` grows the expected delivery sequence by one and adds an inventory-shape check (23 rows, the narrowed Homebrew row, the measurement link and file).
- commit SHA + git tree: `7737bd7` · tree `011a411bf548baf397609bf513996a343de8ff8b`.
- artifact name + checksum: `docs/developer-tooling.md` sha256 `d81a61e3c490df81ecc6b499c41f37684407f6be17b8683c9e6a85daac6c947f`; `tests/test-static.sh` sha256 `1e9e29a5457892fa556fd9d094d759d030387601294fae50edde4c602931a25b`; `docs/research/2026-11-14-brewfile-inventory-measurement.md` sha256 `cce1cbfae8fb9bd724ececdb0eb12dbd7b010fbf8608a293ccbf7ead829e6685`.
- exact command/config: `CONTAINER_RUNTIME=podman bash tests/lint.sh`; `bash tests/test-static.sh`; the measurement is `podman run --rm registry.fedoraproject.org/fedora:45 bash -lc '<loop over 23 names> dnf5 -q repoquery --available --qf "%{name}|%{evr}|%{repoid}"'`, recorded verbatim in the research record.
- test results: `tests/lint.sh` exit 0, last two lines `ok   an empty measurement exits 2, not the drift code` and `ok   an unreadable measurement exits 2, not the drift code`; 41 `ok` lines, no `FAIL`. `git diff --check` exit 0. The two claimed negatives were run: deleting the `television` row printed `FAIL docs/developer-tooling.md lost a row of the 23-entry Brewfile inventory...` and re-adding `ripgrep` to the Homebrew row printed the same line; the restored tree printed `ok   docs/developer-tooling.md inventories all 23 Brewfile entries and links the measurement`.
- eval job path: none. The change is docs plus a deterministic static gate, so the hosted `image` job exercises nothing new; it runs anyway because every PR runs it.
- selection score 5/5 (5 items): the five drifts issue #82 names, each closed by a named line. (1) the rule has a row for a Fedora-packaged user CLI the dotfiles deliver; (2) the eight flagged names no longer sit in the Fedora-absent Homebrew row; (3) `azure-cli` is recorded as a cloud CLI the dotfiles still install by Homebrew; (4) the completeness claim is replaced by an actual inventory; (5) the ten unnamed `Brewfile` entries are named.
- held-out score 4/4 (4 items, never used for selection): (a) the inventory has exactly one row per `brew` entry, counted by the gate; (b) the ordered-delivery gate still passes with the new row in its expected sequence; (c) every Fedora cell matches the recorded query output, checked row by row against the research record; (d) `git diff --check` clean and no file outside the four touched by the commit.
- prev-chain: sha256:c6ec7da920369c97a5e3dddf7ce82978a79c38f32a348406e1bf288c0fb8f152
- gains: the page and the `Brewfile` now state the same delivery for all 23 entries; the rule has a case for the situation that actually exists; the divergence that cannot be resolved here (`gh`, `glab`, `azure-cli`) is named with its owner instead of being silently mis-tabled; a dropped inventory row now reds.
- losses: the inventory is a snapshot at `6eaffc9`, and a `Brewfile` commit that adds a brew still drifts silently until someone edits the page. The gate counts rows and checks one Homebrew-row string; it does not compare tool names against the dotfiles, because CI cannot read that repository. Fedora cells carry versions that float, so the record ages; the record names the container tag and the date to make that visible.
- exceptions/idiosyncratic constraints: this record's preregistration landed after the edit, not before. The prediction was fixed before the diff (five drifts, two mutations), but the ledger append was written once the commit sha existed, so the ordering rule in the playbook was broken once and is recorded here rather than hidden. The ledger itself was created by this campaign: `docs/agents/` did not exist at `cdc580d`, so the scaffold commit precedes this one on the branch and the chain starts at the `n=0` genesis block. Also: no `dnf5` exists on the operator host (Arch), so the measurement ran in `registry.fedoraproject.org/fedora:45` rather than in the pinned bootc base that issue #82 used; the delta is recorded in the research record and cannot change a package name in the Fedora repositories.
- token/cost/duration: one base-loop iteration; one screener pass; two verifier runs of `tests/lint.sh` plus three of `tests/test-static.sh`; three commits on the branch (scaffold, change, record).
- interpretation: the drift was not a wrong decision, it was a missing case plus a sentence that asserted coverage nobody had measured. Adding the case and the row-per-entry table is the minimum that makes the page's claim true, and the divergence on `gh`, `glab`, and `azure-cli` stays visible instead of being resolved by an edit to a file this repository does not own.
- keep/revert: keep. Both mutations the gate claims to catch were observed red, and the faithful tree is green.
- next hypothesis: (a) a cross-repository check needs a checked-in snapshot of the `Brewfile` (a one-line-per-brew file plus a hash), so a dotfiles commit that moves the set reds here instead of drifting quietly; (b) the Fedora cells carry versions that float, so the record could cite the repository id only, which is the fact the rule uses; (c) `docs/known-gaps.md` and this page now both describe the NVIDIA manifest gap, so the two bullets will drift.

### n=2 · 2026-11-14 · revision of n=1 after review

- hypothesis (falsifiable): the reviewer's two P1 findings are real defects in n=1's prose and gate, and fixing the prose plus freezing the 23 inventory names in the gate makes the page's claims match what the checks prove. Falsified if either P1 is a misreading of the text, or if the strengthened gate still passes a renamed row.
- trace evidence: reviewer subagent `ses_e276c657bffeM2A4ERHIW40gof` (REJECT: two P1s, two P2s, one P3). P1-1 named `docs/developer-tooling.md:114-115`; P1-2 named `docs/research/2026-11-14-brewfile-inventory-measurement.md:108-121`; P2-4 named `tests/test-static.sh:207-214`. The bullet already named `gh`, `glab`, and `azure-cli`, so P1-1 was a partial misreading; its true target was the phrase "#82, closed by this page", which claimed more than the page does.
- code change: the Known gaps bullet now says thirteen of the sixteen Fedora names take the grandfather row and the three cloud CLIs stay claimed by the earlier row, and drops "closed by this page". The measurement record gains a bullet naming the same split and stating that row assignment is the rule's answer, not a measurement. `tests/test-static.sh` now compares the inventory's tool cells against the 23 names in `Brewfile` order instead of counting rows.
- commit SHA + git tree: `0afae9a` · tree `034f5cfabc7ebbd92edeca627d1f559ed8a1fc3d`.
- artifact name + checksum: `docs/developer-tooling.md` sha256 `d59d8cd44f52251407473784f83406aadc39b5bc54279b2885d3e185b681efcb`; `tests/test-static.sh` sha256 `ed5ace8189fc6ced5a79a143345c87c6d44ab60cd8a57bd052ae9273f97a8b7b`; `docs/research/2026-11-14-brewfile-inventory-measurement.md` sha256 `8da5d5db23256f7696a5f45f2d1e56935317d5ee4b000261e5d1ce37b82ce46b`. These supersede n=1's checksums for the same three paths; n=1 is not edited, so its checksums describe the state before this revision.
- exact command/config: `CONTAINER_RUNTIME=podman bash tests/lint.sh`; `bash tests/test-static.sh`; the rename mutation is `sed -i 's/^| \`zoxide\` | \`:46\`/| \`zoxide-fork\` | \`:46\`/'`.
- test results: `tests/lint.sh` exit 0, last two lines `ok   an empty measurement exits 2, not the drift code` and `ok   an unreadable measurement exits 2, not the drift code`. Renaming `zoxide` to `zoxide-fork` printed `FAIL docs/developer-tooling.md no longer inventories the 23 Brewfile names in order, widened the Homebrew row, or dropped the measurement record`; the restored tree printed `ok   docs/developer-tooling.md inventories all 23 Brewfile names in order and links the measurement`. `git diff --check` exit 0.
- eval job path: none. Same reasoning as n=1.
- selection score 3/3 (3 items): the three findings this revision claims to close, one item each: P1-1 prose claim, P1-2 evidence cross-reference, P2-4 rename blindness.
- held-out score 2/2 (2 items, never used for selection): (a) the ordered-delivery gate still passes unchanged; (b) a row deletion still reds, re-run after the rewrite rather than assumed.
- prev-chain: sha256:8af73746e0fa25e5a85d31cc8e5cdcf2c8f593b710444d7df6fca08ab082cdd7
- gains: the page's Known gaps bullet no longer implies the cloud-CLI divergence is closed; the measurement record says which of the sixteen names take which row; a renamed inventory row now reds, which the count could not catch.
- losses: the gate now duplicates the 23 names, so a doc reorder that is otherwise harmless reds until the list is updated. That is the intended trade: order is the `Brewfile` order, and the failure is one line to fix.
- exceptions/idiosyncratic constraints: P2-3 (the ledger's "verified by the gate" framing) was declined: n=0 already states that the genesis link is checked by inspection, and n=1's chain verifies. P3 (the sixteen/six/crush arithmetic) was accepted as a parenthetical in the doc rather than as a new sentence, because the counts are now spelled out in both places.
- token/cost/duration: one review pass, one revision, two lint runs, four static runs.
- interpretation: the first P1 was half wrong on the facts and right on the tone; the second was right, and both were cheap to fix. The P2 about the count-only gate was the finding that changed behaviour rather than prose.
- keep/revert: keep. Both P1s addressed, the P2 hardened, and the renamed-row mutation is observed red.
- next hypothesis: (a) same as n=1 (a) — the snapshot is the only way to catch a dotfiles-side move; (b) a reviewer reading a claim sentence as stronger than the text supports is a signal to name the count explicitly next to the sentence, not only in the table.

### n=3 · 2026-11-14 · NVIDIA variant build dependencies (#72)

- hypothesis (falsifiable): `Containerfile.nvidia` currently installs nothing from `manifests/packages-nvidia.txt`, because `build/common.sh` reads only `packages-common.txt`, so the variant cannot boot with a working module. Making `common.sh` install a caller-named extra manifest, naming that manifest from `Containerfile.nvidia`, and adding the akmod build set (`akmod-nvidia`, `akmods`, `kernel-devel-matched`, `gcc`, `make`) gives the variant a module path its build can reach. Predicts: every added name resolves in the pinned base against the enabled repositories; `kernel-devel-matched` pulls the devel for the base's own kernel, not the newest one; the shared image is unchanged when the extra manifest variable is unset; and the new static checks red when the wiring is removed. Falsified by any name failing to resolve, by the deps landing on a kernel other than the base's, by the shared build path changing, or by a check that passes with the wiring deleted.
- predicted at-risk regressions: `build/common.sh` is shared by both Containerfiles, so a refactor that changes the shared install path breaks the main image; `kernel-devel-matched` could resolve to nothing if the pinned base's kernel leaves the updates repository; adding a compiler to a variant that also ships the userspace stack grows the image.
- accept/reject rule: accept only if the resolution evidence covers all five names in the pinned base, the static gate reds on a removed `PACKAGE_MANIFEST_EXTRA`, and `tests/lint.sh` exits 0. Reject if any of the three fails.
- non-goals: no CI job in this iteration, no publish tag, no boot on NVIDIA hardware, no Secure Boot claim, no signature for the module, no package-lock entry for the variant manifest.
- trace evidence: `Containerfile.nvidia:24` (the `PACKAGE_MANIFEST_EXTRA` line in the RUN), `build/common.sh:28-60` (the `install_manifest` helper and the extra-manifest branch), `build/common.sh:63-70` (the kernel-devel check), `build/check-kernel-devel.sh`, `manifests/packages-nvidia.txt:27-36` (the build set), `.evidence/nvidia-build2.log:3642` (the check's xtrace line with both 7.3.3-300.fc45 values), `docs/research/2026-11-14-nvidia-variant-build.md` (the readback), `rpm -qR kernel-devel-matched` in image `aae9510831b0`.
- code change: `build/common.sh` reads the shared manifest through one `install_manifest` helper and installs a caller-named extra manifest after it, then runs `check-kernel-devel.sh` when `kernel-devel` is installed. `Containerfile.nvidia` sets `PACKAGE_MANIFEST_EXTRA=packages-nvidia.txt`. The manifest gains the five build-set names and loses the claim that `kernel-devel-matched` reads the installed kernel. New `build/check-kernel-devel.sh`, new `docs/research/2026-11-14-nvidia-variant-build.md`, `tests/test-static.sh` gains the wiring gate and the helper's three paths, `tests/lint.sh` lints the helper, `docs/known-gaps.md` and the module-path decision record name the new state.
- commit SHA + git tree: `3500e54` · tree `6fa6cb4c598bf02399127e8e906dd809a3177c48`.
- artifact name + checksum: `Containerfile.nvidia` sha256 `5bd98a3c935a6bd675bd4fc353adcae38ae2fb9474db2b30d1b84a4681a99f58`; `build/common.sh` sha256 `9a0dbb0c283451b7bcf86607266ed25f6079655e5bdad61c471c260d5f532a6b`; `build/check-kernel-devel.sh` sha256 `913e4c2176a8a0c4f9509b39f2d6d01d9149809f928becbad6238dc967ede6b4`; `manifests/packages-nvidia.txt` sha256 `2334cf87764a7ac4701090114ececebb50049b37c2320ea6becad532a8bb81de`; `tests/test-static.sh` sha256 `40817bf66e5d1ee8dc6534184a1d47434b8c1eec9a4cbcb89f5285fc68dda440`; `docs/research/2026-11-14-nvidia-variant-build.md` sha256 `8374612bcb8dbb512bf70876a0191e852896dd2d538bf446a42f081a8189fd61`.
- exact command/config: `podman build --layers -t localhost/dux-atomic:nvidia -f Containerfile.nvidia .`; `CONTAINER_RUNTIME=podman bash tests/lint.sh`; the mutations are `sed -i '/PACKAGE_MANIFEST_EXTRA=packages-nvidia.txt/d' Containerfile.nvidia` and `sed -i '/^make$/d' manifests/packages-nvidia.txt`.
- test results: the variant build exits 0 and `bootc container lint` reports `Checks passed: 12`, `Checks skipped: 1`, `Warnings: 2`; image `aae9510831b0` reads back `kernel`, `kernel-core`, `kernel-devel`, `kernel-devel-matched` all `7.3.3-300.fc45.x86_64`, and `rpm -q --whatprovides` resolves all nine probed names. `tests/lint.sh` exits 0 with 42 `ok` lines, the last two `ok   an empty measurement exits 2, not the drift code` and `ok   an unreadable measurement exits 2, not the drift code`. The four negatives were run: the removed `PACKAGE_MANIFEST_EXTRA` prints `FAIL Containerfile.nvidia does not set PACKAGE_MANIFEST_EXTRA=packages-nvidia.txt, so the variant installs no variant packages`; the removed `make` prints `FAIL packages-nvidia.txt no longer names the akmod build set: make`; `check-kernel-devel.sh 7.3.3-300.fc45.x86_64 7.2.11-300.fc45.x86_64` exits 1; the same script with no devel argument exits 1. The restored tree prints `ok   the NVIDIA variant installs its own manifest, names the akmod build set, and checks kernel-devel`.
- eval job path: none. The variant is not built in CI, so the image job exercises the shared path only; the extra manifest is proven by a local build whose log and digest are in this record.
- selection score 5/5 (5 items): (1) the variant installs its manifest, named in `Containerfile.nvidia:24` and installed by `build/common.sh:60`; (2) the manifest names the five build-set packages; (3) the built image contains every name, read back with `rpm -q --whatprovides`; (4) the installed kernel, both devel packages, and `kernel-devel-matched` are the same version, and the build fails if a devel is not the newest kernel; (5) the shared `Containerfile` sets no extra manifest and the shared install path still runs through the same helper, with `tests/lint.sh` green.
- held-out score 4/4 (4 items, never used for selection): (a) a removed `PACKAGE_MANIFEST_EXTRA` reds the static gate, observed; (b) a removed build-set name reds it, observed with `make`; (c) `check-kernel-devel.sh` reds a mismatched devel and an empty set, observed; (d) `tests/lint.sh` and `git diff --check` exit 0 on the restored tree, observed.
- prev-chain: sha256:1cc5fa5b8cac3218221ce26eef2f4799bfd812631ad8abcc431af8f98fd0830a
- gains: the variant now installs the userspace stack and the akmod build set, so the first-boot compile has its source, tools, and headers; the build fails instead of shipping headers for a kernel other than the newest installed one; the shared image is provably untouched by the change; the decision record and known-gaps no longer say the manifest lacks the build dependencies.
- losses: the variant still has no lock file, so a rebuild can differ from the recorded digest when a repository moves; the check compares package versions, not the booted kernel's `uname -r`, so a two-kernel image could pass; the manifest's five names are a text pin in the static gate, so a name swapped for another provider still passes; the build costs 40 minutes of wall time in this session, which is the iteration's dominant cost.
- exceptions/idiosyncratic constraints: the preregistration was written to the working tree before the first edit, but the record's results land in the same commit as the change's checksums, so git cannot show that ordering; the record says so instead of implying a commit history it does not have. The first draft of the manifest comment claimed `kernel-devel-matched` reads the installed kernel, and the build's `rpm -qR` output falsified it; the comment was corrected and a build-time check added rather than the claim kept. No `akmods` run and no boot were attempted, so the compile at first boot remains unobserved.
- token/cost/duration: one iteration; two full variant builds (the second after the check was added), one lint run before and one after the docs, one image readback, four observed gate negatives.
- interpretation: the iteration's value is not the package list, which was cheap; it is that the list was inert without the wiring, and that the name promising a kernel match promised it to the repository rather than to the image. Both were only visible by building and reading the image back. The `kernel-devel-matched` claim is the case for a build-time assertion: the name was close enough to right to pass a reading, and only `rpm -qR` separated the mechanism from the outcome.
- keep/revert: keep. Every accepted condition was observed, and the one falsified prediction was replaced by a gate that now reds when the property fails.
- next hypothesis: (a) the variant needs its own lock, because the manifest is name-based and the record is a digest that will drift on the next repository move; (b) the unobserved step is the akmod compile, which could run in a container with `akmods --force` against the installed kernel headers and needs no NVIDIA hardware; (c) publish and a hardware boot stay #72's own items, and the MOK enrollment stays #40's.

### n=4 · 2026-11-14 · revision of n=3 after review

- hypothesis (falsifiable): the reviewer's two P1s are real defects. The record's `kernel-devel-matched` paragraph reads as if the package consults the installed kernel, and n=3's exception sentence claims a timeline that the record cannot show. The P2 is a real weakness in the new hook: `PACKAGE_MANIFEST_EXTRA` is used as a path fragment, so a slash reaches outside `manifests/`. Fixing the two paragraphs, resolving the value through a tested helper, and asserting the helpers' messages closes all three. Falsified if the record already said the correct thing, or if the helper rejects the variant's own value.
- trace evidence: reviewer subagent `ses_e27461c76ffe5LKEVYWCmStA2w` (REJECT: P1 mechanism wording, P1 timeline, P2 path fragment, P2 unverified mutations, P3 suppressed stderr). The P2 about unverified mutations is a reviewer capability limit: that subagent had no shell, so it judged the recorded evidence only. The implementer's mutation transcript is `.evidence/mutations.txt`, and both gate reds are also in the n=3 record.
- code change: `docs/research/2026-11-14-nvidia-variant-build.md` now states the `rpm -qR` requirement pair and that the package does not consult the installed kernel. The `manifests/packages-nvidia.txt` comment says the requirement pins the pair to one version. New `build/check-manifest-name.sh` accepts a bare file name and prints `/ctx/manifests/<name>`, refusing a slash and an empty value; `build/common.sh` resolves the value through it before `install_manifest`. `tests/test-static.sh` asserts both helpers' green and red paths, including exit status 1 and the message text, and no longer discards stderr. `tests/lint.sh` lints the new helper.
- commit SHA + git tree: `02fe95d` · tree `75403961b544c485ee6511faf4ed4b6161e81689`.
- artifact name + checksum: `build/common.sh` sha256 `1150f0b4b7ddc1b6a1e35b49d7b473c136f999b01d0be95262d73ce9bc55901a`; `build/check-manifest-name.sh` sha256 `6f441fe0ffd8808a3921bdc5c22e3e66351243f85a1437bbb5fa851887b94bd1`; `build/check-kernel-devel.sh` sha256 `913e4c2176a8a0c4f9509b39f2d6d01d9149809f928becbad6238dc967ede6b4` (unchanged); `tests/test-static.sh` sha256 `98e076989c0d7ddd62e2e95feebf98cbe3d77016e84764e17e2b9151af70f250`; `manifests/packages-nvidia.txt` sha256 `2aabd0df8427d40a5d95a8b9c08314c2c110abf5110f7c2b864299e62fff9b14`; `docs/research/2026-11-14-nvidia-variant-build.md` sha256 `657c100f256dd18cde4c851f9e98dc67a8460bbbac717fd16649ee5ce30bcd8f`. These supersede n=3's checksums for the same paths; n=3 is not edited.
- exact command/config: `podman build --layers -t localhost/dux-atomic:nvidia -f Containerfile.nvidia .`; `CONTAINER_RUNTIME=podman bash tests/lint.sh`; `bash build/check-manifest-name.sh ../packages-common.txt`; `bash build/check-manifest-name.sh ''`; `bash build/check-kernel-devel.sh 7.3.3-300.fc45.x86_64 7.2.11-300.fc45.x86_64`.
- test results: build 4 exits 0, image `32ce10095923`, and the log shows the chain `++ bash /ctx/build/check-manifest-name.sh packages-nvidia.txt`, `+ extra=/ctx/manifests/packages-nvidia.txt`, `+ install_manifest /ctx/manifests/packages-nvidia.txt`, then the one `dnf5 install -y nvidia-driver ...` line. `bootc container lint` reports `Checks passed: 12`, `Checks skipped: 1`, `Warnings: 2`. The image reads back `kernel`, `kernel-core`, `kernel-devel`, `kernel-devel-matched` all `7.3.3-300.fc45.x86_64` and all nine probed names resolved. `tests/lint.sh` exits 0 with 43 `ok` lines. The helper reds print `PACKAGE_MANIFEST_EXTRA must be a file name in manifests/: ../packages-common.txt` and the empty value, both exit 1; the kernel-devel mismatch prints `kernel-devel does not match the newest kernel 7.3.3-300.fc45.x86_64`, exit 1. The restored tree prints `ok   the NVIDIA variant names its own manifest and the shared image does not` and `ok   the variant's manifest-name and kernel-devel helpers accept their inputs and refuse the rest`.
- eval job path: none. Same reasoning as n=3.
- selection score 3/3 (3 items): P1 mechanism paragraph, P1 timeline claim, P2 path fragment. Each addressed by a named change.
- held-out score 2/2 (2 items, never used for selection): (a) the variant's own value still resolves to the right path and installs the same set in build 4, observed in the xtrace; (b) the static gate still reds on a removed `PACKAGE_MANIFEST_EXTRA` and a removed build-set name after the rewrite, observed in `.evidence/mutations.txt`.
- prev-chain: sha256:e0c584b01f23dd50800fd076cb3a8031e70d2aa84052544ebf5d88cfc25a98c1
- gains: the record's mechanism paragraph now matches `rpm -qR`; the hook cannot read outside `manifests/`; the gate asserts the helpers' messages and exit codes, so a behaviour change reds without an image; the timeline claim is withdrawn rather than repeated.
- losses: one more full variant build (the third attempt was killed when the hook changed, so only the fourth counts) to re-prove the install path with the helper in place; the revision adds a second helper file for a one-line rule, which is the price of an observed red.
- exceptions/idiosyncratic constraints: the timeline is stated once here and supersedes n=3's sentence. The preregistration text (hypothesis, at-risk, accept/reject, non-goals, prev-chain, `results pending`) was in the working tree before the results existed. The commit that lands it (`d9573e1`) follows the change commit (`3500e54`) because the checksums could not exist earlier. Whether it was written before the first edit is not recorded anywhere, so neither record should claim it; n=3 claimed it, and this record withdraws that claim. n=1's "preregistration landed after the edit" is its own event about n=1, not about n=3.
- token/cost/duration: one review round, one revision commit, one full build (the fourth), two lint runs, one static run per mutation.
- interpretation: the review's mechanism finding was an editorial defect with a real cause: the name and the requirement were both close enough to right that the first draft stated the outcome as the mechanism. The path finding was smaller, but the fix produced a tested red rather than a grep-pinned branch. The timeline finding was a misreading of a sentence that had no business asserting what git cannot show.
- keep/revert: keep. All three findings are addressed, and the two held-out checks were re-run rather than assumed.
- next hypothesis: (a) the remaining unproven step is the akmod compile, which can run without NVIDIA hardware through `akmods --force` in a container and would close the last unobserved claim in the decision record; (b) the variant lock is still missing, so build 4's digest is a snapshot; (c) publish and the hardware boot stay #72's own items, and MOK enrollment stays #40's.

### n=5 · 2026-11-14 · compile the NVIDIA akmod during the image build (#72)

- hypothesis (falsifiable): the module path says the akmod compiles on first boot. The image falsifies that mechanism: `akmods.service` ships `ConditionPathExists=!/run/ostree-booted` and is enabled, a bootc host is ostree-booted, and `/lib` is a symlink into `/usr`, which is read-only at runtime. Compiling during the image build, guarded on the installed `akmod-nvidia`, and asserting the five modules for the newest installed kernel makes the variant ship a module. Predicts: the variant build exits 0; the image carries `nvidia`, `nvidia-uvm`, `nvidia-drm`, `nvidia-modeset`, and `nvidia-peermem` under `/usr/lib/modules/<kver>/extra/nvidia`, each reporting `version=620.70.06` and an empty signer; the shared image installs nothing extra; the static gate reds when the compile call or a module disappears. Falsified by a build failure, a missing module, a changed shared path, or a gate that passes with the wiring removed.
- predicted at-risk regressions: `build/common.sh` is shared by both Containerfiles, so the compile must stay behind a guard that the shared image never satisfies; the compile adds about 70 seconds and tens of megabytes; `akmods` wants `/var/log/akmods` and `/var/cache/akmods`; files installed under `/usr` by a build tool rather than RPM may trip `bootc container lint` or leave unowned content.
- accept/reject rule: accept only if the variant build exits 0, all five modules read back with a version, `bootc container lint` still passes, `tests/lint.sh` exits 0, and the new static reds are observed. Reject if any of those fails.
- non-goals: no module signing or MOK enrollment (#40), no hardware boot, no publish, no variant lock, no variant CI job, no change to `tests/verify-image.sh`.
- trace evidence: `.evidence/akmods-probe.txt` (akmods exit 0, 1:09.45 wall, five modules, `signer=[]`, `version=620.70.06`, `vermagic 7.3.3-300.fc45.x86_64`); `systemctl is-enabled akmods.service` prints `enabled`; `ConditionPathExists=!/run/ostree-booted` is line 3 of `/usr/lib/systemd/system/akmods.service`; `readlink -f /lib` prints `/usr/lib`; `rpm -q ostree bootc` prints both installed; `akmods-shutdown.service` is disabled and `akmods@.service` is a kernel-transaction trigger, so neither reaches a first boot.
- code change: pending.
- commit SHA + git tree: pending.
- artifact name + checksum: pending.
- exact command/config: `podman build --layers -t localhost/dux-atomic:nvidia -f Containerfile.nvidia .`; `CONTAINER_RUNTIME=podman bash tests/lint.sh`; `bash tests/test-static.sh`.
- test results: results pending.
- eval job path: none. The variant is not built in CI, so the `image` job exercises the shared path only.
- selection score: pending.
- held-out score: pending.
- prev-chain: sha256:4aa64e653f2f24953f19b8e6056e03acc26aca1ee86edb3ab046f5fd367b234b
- gains: results pending.
- losses: results pending.
- exceptions/idiosyncratic constraints: results pending.
- token/cost/duration: results pending.
- interpretation: results pending.
- keep/revert: results pending.
- next hypothesis: results pending.
