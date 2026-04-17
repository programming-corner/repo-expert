# Mode: Refresh — Keeping Knowledge Current

Triggered by: "refresh", "rescan", "update knowledge", "re-learn this repo"

---

## How staleness detection works — NO token consumption

The refresh system is **purely git-based**. It never calls the Claude API just to detect
whether a doc is stale. Detection is a fast, local operation:

1. Each generated doc carries frontmatter with the `git_sha` at generation time and a list of `source_files`
2. The refresh script runs `git diff <stored_sha>..HEAD --name-only`
3. If any `source_files` appear in the changed list → the doc is marked stale
4. Only when you explicitly pass `--auto` does the script call the Claude API to regenerate

This means:
- The git post-merge hook runs in milliseconds with zero API cost
- CI/CD staleness checks are cheap enough to run on every PR
- The Claude API is only invoked when you actually want the content updated

---

## Staleness detection (runs silently on every Consult invocation)

Each generated doc has frontmatter:
```yaml
---
generated: YYYY-MM-DD
git_sha: <sha>
source_files:
  - src/orders/orders.service.ts
  - src/orders/orders.controller.ts
---
```

If bash is available:
```bash
git diff <stored_git_sha>..HEAD --name-only
```

Compare changed files against each doc's `source_files`.
Mark affected docs as `⚠️ stale` in KNOWLEDGE.md's flows index.
Only surface this to the user if the stale doc is needed for the current question.

---

## Manual refresh

When user triggers refresh:
1. Run `npx tsx scripts/refresh.ts --check-only` (or `python scripts/refresh.py --check-only` for non-Node repos) to see which docs are stale
2. For each stale doc: read the changed source files, regenerate using templates in `references/doc-templates.md`
3. Update `git_sha` in regenerated docs to current HEAD SHA
4. Update KNOWLEDGE.md flows index status back to `✅ ready`

---

## Automated refresh (set up during Bootstrap)

Run once to install hooks and CI workflow:
```bash
npx tsx scripts/refresh.ts --install-hooks
```

This generates:
- `.git/hooks/post-merge` — zero-cost staleness check after every pull/merge (no API key needed)
- `.github/workflows/repomind-refresh.yml` — marks stale docs on every PR merge; regenerates only when `--auto` flag is set

**Key architecture decision:** The GitHub Actions workflow runs in two modes:
- **Check mode** (default, no secrets needed): marks docs as stale in KNOWLEDGE.md, opens a PR comment listing what needs refresh
- **Auto mode** (requires `ANTHROPIC_API_KEY` secret): regenerates stale docs and commits them

This separates staleness detection (always free, always runs) from AI regeneration (opt-in, costs tokens).
