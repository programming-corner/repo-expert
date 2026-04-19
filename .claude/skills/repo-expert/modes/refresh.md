# Mode: Refresh — Keeping Knowledge Current

Triggered by: "refresh", "rescan", "update knowledge", "re-learn this repo"

---

## How staleness detection works — NO token consumption

The refresh system is **purely git-based**. It never calls the Claude API just to detect
whether a doc is stale. Detection is a fast, local operation:

1. Each generated doc carries frontmatter with the `git_sha` at generation time and a list of `source_files`
2. `doc-check.sh` reads `git diff <stored_sha>..HEAD --name-only`
3. If any `source_files` appear in the changed list → the doc is marked stale
4. The Claude API is only called to regenerate docs the developer explicitly approves

This means:
- Staleness detection runs in milliseconds with zero API cost
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

```bash
git diff <stored_git_sha>..HEAD --name-only
```

Compare changed files against each doc's `source_files`.
Mark affected docs as `⚠️ stale` in KNOWLEDGE.md's flows index.
Only surface this to the user if the stale doc is needed for the current question.

---

## Local pre-commit refresh (doc-check.sh)

The primary refresh mechanism is `doc-check.sh` — a plain bash script developers run
**instead of** `git commit` when they want docs kept in sync.

**Setup** (copy once to repo root):
```bash
cp .claude/skills/repo-expert/doc-check.sh ./doc-check.sh
chmod +x doc-check.sh
```

**Workflow:**
```bash
git add src/orders/orders.service.ts   # stage your code changes
./doc-check.sh "feat: add retry logic" # run instead of git commit
```

**What it does:**
1. Aborts if nothing is staged
2. Scans `docs/expert/*.md` and `KNOWLEDGE.md` for stale frontmatter
3. For each stale doc: calls `claude --print` (headless, non-interactive) with a regeneration prompt
4. Shows a coloured `diff` for each regenerated doc — developer chooses `y / n / e(dit)`
5. Approved docs are `git add`-ed automatically
6. Prompts for a commit message (or accepts it as `$1`), appends `[docs refreshed]` when docs were updated
7. Commits all staged changes (code + approved docs) in a single atomic commit
8. Optionally pushes immediately

**Configurable via env vars:**

| Variable | Default | Purpose |
|---|---|---|
| `DOCS_DIR` | `docs/expert` | Where flow docs live |
| `KNOWLEDGE_FILE` | `KNOWLEDGE.md` | Master index file |
| `SKILL_DIR` | `.claude/skills/repo-expert` | Path to this skill |

---

## How Claude regenerates a doc (when invoked by doc-check.sh)

When `claude --print` is called for a stale doc, follow these steps:

1. Read the current doc — preserve its section structure and frontmatter keys
2. Read every file listed in `source_files` that appears in the git diff
3. Regenerate the doc using the same template from `references/doc-templates.md`
4. Update frontmatter:
   - `git_sha` → current `HEAD` SHA (`git rev-parse HEAD`)
   - `generated` → today's date
5. Output **only** the complete updated doc — no explanation, no markdown fences wrapping it

**Key constraint:** Never invent information. If a source file no longer contains
something the doc referenced, remove that section rather than leaving stale content.
