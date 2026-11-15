# L006 — a conflict resolution is a deletion until the diff says otherwise

**Claim.** A merge that resolves a conflicted file by keeping one side deletes
the other side's lines, and nothing in the merge commit's subject says so. Read
`git show --stat <merge>` on the conflicted path before treating the merge as
plumbing, and compare the file's line count against each parent. A gate that
checks only the merged tree's shape cannot see a deletion the merged tree is
happy to satisfy.

**Applicability conditions.** Applies to a merge that reports conflicts, and to
any file whose history matters: `CHANGELOG.md`, a lock, a migration list, a
glossary. Does not apply to a merge that had no conflicts, where the tree is the
union of both sides.

**Evidence.** On 2026-11-15, commit `b3bb525` merged `origin/main` (d53b19b) into
`chore/102-repin-probe` and reported a conflict on `CHANGELOG.md`. `git show
--stat b3bb525 -- CHANGELOG.md` reads `1 file changed, 1 insertion(+), 95
deletions(-)`: the first parent `b3a2f8f` holds 100 lines and the merge result
holds 6. The `static` check run recorded on `b3bb525` concluded `success`, so
`tests/lint.sh` passed on the truncated tree. A human counting lines caught it,
and #123 added a gate that compares the tree's `CHANGELOG.md` against the base
branch and fails when the tree is shorter. PR #124's body attributes the cut to
`3001e71`, which is the commit after the merge and only adds one line: the
truncating commit is `b3bb525`.

**What this lesson does not license.** It does not say every merge needs a diff
review. It says a conflicted merge is a change to the conflicted files, and the
deletion is only visible in the stat and in the line counts between parents.
