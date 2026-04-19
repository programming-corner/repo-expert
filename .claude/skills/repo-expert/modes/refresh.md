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
schema_version: "1.0"
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

## Two-phase workflow (Claude + terminal)

`doc-check.sh` has two modes so Claude handles the non-interactive work and the developer
only sees the interactive approval + commit prompts.

### Phase 1 — Claude runs (non-interactive)

Claude runs this via the Bash tool:
```bash
cd <repo-root> && ./doc-check.sh --prepare
```

What it does:
- Detects stale docs via git diff (zero API cost)
- Calls `claude --print` to regenerate each stale doc into a temp file
- Saves a manifest at `/tmp/doc-check-<repo-name>.manifest` mapping `original → temp`

### Phase 2 — Developer runs (interactive)

Claude opens a terminal pre-navigated to the repo root for the commit phase:
```bash
osascript -e "tell app \"Terminal\" to do script \"cd $(git rev-parse --show-toplevel) && ./doc-check.sh --commit\""
```

What the developer sees in the terminal:
- Coloured diff for each regenerated doc (metadata summary + content-only diff)
- `Approve? [y]es / [n]o / [e]dit` prompt per doc
- Commit message prompt
- Push prompt

**Fallback — if not on macOS:** Tell the user:
> Prepare is done. Now run in your terminal:
> ```bash
> ./doc-check.sh --commit
> ```

### Phase 2 — Auto mode (non-interactive, CI-safe)

Skips all prompts, applies every regenerated doc, commits with a static message, and pushes.
No TTY required — safe to run in GitHub Actions or any headless environment.

```bash
./doc-check.sh --commit --auto
```

Commit message format: `docs: refresh stale docs [<short-sha>]`

Use this in CI after `--prepare` when you want fully automated doc sync without human review.

---

## How Claude regenerates a doc (when invoked by doc-check.sh)

When `claude --print` is called for a stale doc, follow these steps:

1. Read the current doc — preserve its section structure and frontmatter keys
2. **Check `schema_version`** in the doc's frontmatter against the template in `references/doc-templates.md`.
   If absent or mismatched: abort this doc, print `⚠️ schema_version mismatch in <file> — manual migration required`, and skip to the next doc.
3. Read every file listed in `source_files` that appears in the git diff
4. Regenerate the doc using the same template from `references/doc-templates.md`
5. Update frontmatter:
   - `git_sha` → current `HEAD` SHA (`git rev-parse HEAD`)
   - `generated` → today's date
   - `schema_version` → unchanged (only bump when the template version changes)
6. Output **only** the complete updated doc — no explanation, no markdown fences wrapping it

**Key constraint:** Never invent information. If a source file no longer contains
something the doc referenced, remove that section rather than leaving stale content.
