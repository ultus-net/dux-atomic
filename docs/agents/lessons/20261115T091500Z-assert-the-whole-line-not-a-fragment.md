# L005 — assert the whole line, not a fragment of it

**Claim.** `grep -qF` over a script passes on any mention of the fragment,
including a comment that documents the command, a second call in another
function, and a rename that keeps the fragment as a prefix. An assertion about a
specific call must match that call's whole line, anchored at both ends
(`grep -qxF`), so only the line itself satisfies it.

**Applicability conditions.** Applies to assertions that a named command is
still invoked, or that a named line is still present. Does not apply to a
count assertion over a region, where the fragment is the thing being counted and
the count is the contract.

**Evidence.** Iteration 1 shipped
`grep -qF 'dnf5 --dump-main-config)'` as the check that `tests/verify-image.sh`
still reads the dnf.conf values back. The reviewer pointed out that the closing
parenthesis is still a fragment: a comment naming the command, or a different
call site, satisfies it. The committed check is
`grep -qxF "$dnf_readback"` against the whole line
`dnf_conf=$("$runtime" run --rm "$image" dnf5 --dump-main-config) \` held in a
variable, and the negative proof is renaming the flag on that line, which prints
`FAIL tests/verify-image.sh no longer reads the dnf.conf values back with dnf5 --dump-main-config`
with exit 1. The earlier `)`-anchored form was a fix for the first false green
(L004) and was still too weak, which is why the two lessons are separate.

**What this lesson does not license.** It does not say every assertion must be
an exact line. A whole-line match is brittle by design: reformatting the call
reds the gate, and that red is the review signal. It says a fragment match is a
claim about the file's text, not about the call.
