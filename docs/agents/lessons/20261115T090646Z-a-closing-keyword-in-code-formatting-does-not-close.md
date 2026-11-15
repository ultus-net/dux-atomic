# L007 — a closing keyword in code formatting does not close the issue

**Claim.** GitHub reads closing keywords from the rendered pull-request body, so
`Fixes #123` inside a code span or a fenced block is prose about the keyword.
The work item stays open after the merge, and a person closes it by hand later.
Write the keyword on its own bare line, and check the issue's state after the
merge rather than after writing the body.

**Applicability conditions.** Applies to every forge keyword that closes a work
item from a PR body or a commit message (`Fixes`, `Closes`, `Resolves`, and the
Azure DevOps `AB#` form in a commit). Does not apply to a keyword in a PR
comment, which the forge never reads for closing.

**Evidence.** PR #124 merged at 2026-11-15T06:31:51Z with `Fixes #123` formatted
as a code span in its Work item section. Issue #123 reported `state=CLOSED` with
`closedAt=2026-11-15T08:39:21Z`, 2h07m after the merge and by hand. The
unformatted keyword is on its own line in the same section of later PR bodies.
A tree-level gate cannot see this, because a PR body is not in the repository.

**What this lesson does not license.** It does not say every formatted mention
of an issue is wrong: prose that names `#123` inside backticks is fine. It says
the closing keyword itself must be bare, and that the check is the issue's
state after the merge.
