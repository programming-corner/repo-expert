# RepoMind — Universal Repo Expert

> A self-bootstrapping Claude Code skill that thinks and speaks like a senior tech lead. Drop it into any repo and ask anything.

---

## Installation

```bash
npx skills add programming-corner/repo-expert
```

---

## What it does

RepoMind reads your codebase before answering — it never guesses about repo-specific details. It builds a persistent knowledge base (`KNOWLEDGE.md`) on first run and keeps it current across code changes.

**Covers all stacks:** Node.js · Python · Go · Java · Ruby · PHP · Rust · any frontend.

---

## Modes

| Mode | When it triggers |
|---|---|
| **Bootstrap** | No `KNOWLEDGE.md` in repo root — scans the repo, generates the knowledge base |
| **Consult** | `KNOWLEDGE.md` exists — answers questions about code, flows, architecture, performance |
| **Refresh** | "refresh" / "rescan" — detects stale docs and fills missing sections |
| **Requirements** | User shares a feature request or business requirement |
| **PR Review** | User pastes a diff, mentions a PR, or shares a GitHub PR URL |

Priority when multiple modes match: `PR Review > Refresh > Requirements > Consult > Bootstrap`

---

## Trigger phrases

| Say this | What happens |
|---|---|
| `onboard me` / `I just joined this team` | Full bootstrap — stack, flows, architecture diagram |
| `learn this repo` / `boot the expert` | Same |
| `explain this repo` / `what's the architecture?` | Same |
| `how does X work in our code?` | Consult — reads source files, anchors answer to repo |
| `what will break if I change Y?` | Impact analysis across services, DB, API contracts, events |
| `review this PR` / _(paste a diff)_ | Structured PR review — risk level, issues, suggestions, positives |
| `we need to build X` / _(paste a requirement)_ | Requirements mode — surfaces conflicts before any code |
| `refresh` / `rescan` | Staleness check + gap detection — works even with no new commits |
| `audit performance` / `health check` | Repo-wide or flow-scoped performance scan |
| `system design for X` / `generate a diagram` | Architecture or sequence diagram anchored to the repo |

See [CHEATSHEET.md](CHEATSHEET.md) for the full trigger phrase reference.

---

## Bootstrap — how the knowledge base is built

1. **Index** — lists all paths and reads signal files only (no source reads yet)
2. **Identify** — infers flows and areas from structure; generates a high-level Mermaid architecture diagram
3. **Ask** — presents findings and asks which flows to document (all / subset / none)
4. **Read** — reads source files for selected flows only
5. **Validate** — shares a structured summary, waits for approval before writing anything
6. **Write** — generates `KNOWLEDGE.md` at repo root and `docs/expert/<flow>.md` per selected flow
7. **Commit** — stages and pushes the knowledge base

Unselected flows are marked `🔵 lazy` — their docs are generated on demand when you ask about them.

---

## Refresh — gap detection

`refresh` / `rescan` runs two checks every time:

- **Staleness** — compares stored git SHA against HEAD; marks docs whose source files changed
- **Gaps** — scans `KNOWLEDGE.md` for missing sections (architecture diagram, glossary, integrations, etc.) and new repo directories not yet in the flows index

Gap detection runs **even with no new commits** — useful when `KNOWLEDGE.md` was generated before a section existed.

After the scan you choose: `all` · `gaps only` · `stale only` · `select [names]` · `cancel`

---

## File structure

```
SKILL.md                          ← skill entry point and routing rules
CHEATSHEET.md                     ← trigger phrase quick reference
modes/
  bootstrap.md                    ← first-time repo scan
  consult.md                      ← Q&A against existing knowledge base
  refresh.md                      ← staleness + gap detection
  requirements.md                 ← feature discovery and design
  pr-review.md                    ← structured code review
references/
  bootstrap/
    signal-files.md               ← stack and monorepo detection rules
    flow-patterns.md              ← flow naming conventions
    stack-templates.md            ← what source files to read per stack
  backend/
    nodejs-core.md
    databases.md
    queuing.md
    system-design.md
  frontend/
    react-core.md
    testing-fe.md
  polyglot/
    python.md  go.md  java.md  rust.md  ruby-php.md
  testing/
    backend-testing.md
  doc-templates.md                ← KNOWLEDGE.md and flow doc templates
```

---

## Guiding principles

1. **Know before you speak** — load `KNOWLEDGE.md` before any repo-specific answer
2. **One question at a time** — never overwhelm with multiple clarifying questions
3. **Repo patterns over prescriptions** — align suggestions with what the codebase already does
4. **Show the why** — explain reasoning, not just the what
5. **Flag the risk** — surface security, performance, and data integrity issues even when not asked
6. **Tech debt is first-class** — classify it, prioritize it, never ignore it
7. **Diagrams first** — generate Mermaid before explaining complex flows in prose
8. **New joiners are primary users** — onboarding clarity is as important as architecture depth
9. **Polyglot by default** — read signal files first, never assume a stack
10. **Requirements before solutions** — always surface conflicts and constraints before proposing code
