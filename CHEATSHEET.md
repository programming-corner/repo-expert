# RepoMind — Command Cheat Sheet

> All trigger phrases that activate each mode or question type.
> Use in any Claude Code session where the repo-expert skill is active.

---

## 🚀 Bootstrap — First time in a repo
_Triggers when no `KNOWLEDGE.md` exists in repo root_
_Writes `KNOWLEDGE.md` to **repo root** and flow docs to `docs/expert/`_

| What you say | What happens |
|---|---|
| `learn this repo` | Full repo scan — detects stack, reads source files, writes KNOWLEDGE.md to repo root |
| `boot the expert` | Same as above |
| `explain this repo` | Same as above |
| `what's the tech stack?` | Same — bootstraps if no knowledge base yet |
| `walk me through the codebase` | Same |
| `create a knowledge base` | Same |
| `generate an architecture diagram` | Same — bootstraps first, then generates diagram |
| `I just joined this team` | Same — also generates onboarding guide after scan |
| `onboard me` | Same as above |

---

## 💬 Consult — General Q&A
_Requires KNOWLEDGE.md to exist_

### Business Logic & Flows
| What you say | What happens |
|---|---|
| `how does the order lifecycle work?` | Loads or generates the flow doc, includes Mermaid diagram |
| `walk me through checkout` | Same — prose + sequence diagram |
| `explain the payment flow` | Same |

### Implementation Guidance
| What you say | What happens |
|---|---|
| `how should I implement retry logic?` | Answers aligned to repo's stack + loads nodejs-core / python / go etc. |
| `what's the best way to add pagination?` | Same |
| `how do I structure this service?` | Same |

### Architecture & Design
| What you say | What happens |
|---|---|
| `what's the architecture?` | Overview from KNOWLEDGE.md + diagram |
| `how should I architect this feature?` | Loads system-design.md, options with tradeoffs |
| `what pattern fits here?` | Same |
| `system design for X` | Same |
| `generate a diagram` | Mermaid diagram — sequence / flowchart / ER / dependency graph |
| `show me the sequence for checkout` | Sequence diagram for that flow |
| `draw the architecture` | System context or module dependency diagram |

### Database & Queries
| What you say | What happens |
|---|---|
| `is this query performant?` | Loads databases.md, checks indexes, N+1, migration safety |
| `how should I model this relationship?` | Same |
| `database schema` | Reads migration files / entity models, summarises |

### Frontend
| What you say | What happens |
|---|---|
| `how is state managed?` | Loads react-core.md, reads actual component structure |
| `where should this component live?` | Same |
| `frontend architecture` | Same |

### Impact Analysis
| What you say | What happens |
|---|---|
| `what breaks if I change X?` | Traces services, DB, API contracts, events, caches, FE components |
| `what's affected by this DB change?` | Same |
| `impact analysis for X` | Same |

### Technical Debt
| What you say | What happens |
|---|---|
| `what's the debt in this module?` | Classifies intentional vs accidental, prioritises by risk × effort |
| `where are the biggest risks?` | Same |
| `tech debt in orders` | Same, scoped to that module |

### Test Strategy
| What you say | What happens |
|---|---|
| `what should I test here?` | Loads backend-testing.md or testing-fe.md, happy path → edge → failure → race conditions |
| `what are the test scenarios for X?` | Same |
| `testing strategy` | Same |
| `write test scenarios for the order flow` | Same, scoped to that flow |

### Onboarding
| What you say | What happens |
|---|---|
| `I just joined — what do I need to know?` | Stack overview, key flows, fragile areas, naming conventions, gotchas, reading order |
| `onboard me` | Same |

---

## 🔍 Performance & Health Audit
_Repo-wide or scoped to a specific flow_

| What you say | Scope | What happens |
|---|---|---|
| `audit performance` | All files | Scans every service / controller / processor / consumer / interceptor / gateway |
| `health check` | All files | Same |
| `check for memory leaks` | All files | Same |
| `check for event loop blocking` | All files | Same |
| `audit performance for orders` | Order flow only | Reads `docs/expert/orders.md` source_files, scans only those |
| `health check the payment flow` | Payment flow only | Same, scoped to payment source files |
| `check for memory leaks in auth` | Auth flow only | Same, scoped to auth source files |

**Output always includes:**
- 🔴 Memory leak risks (listener leaks, timer refs, unbounded caches, stream leaks)
- 🟡 Event loop blocking (sync I/O, sync crypto, large JSON, ReDoS, sequential awaits)
- 🟠 NestJS health (REQUEST scope, missing shutdown hooks, interceptor body logging)
- ✅ Clean areas
- Diagnostics checklist to add to the codebase

---

## 🔀 PR Review
_Triggered by a diff, PR keyword, or GitHub PR URL — not by "review this" alone_

| What you say | What happens |
|---|---|
| `review this PR` | Full structured review — risk level, critical issues, suggestions, positives, test gaps |
| `review this diff` | Same |
| `review pull request #N` | Same |
| _(paste a git diff)_ | Auto-triggers PR review mode |
| _(paste a GitHub PR URL)_ | Same — asks for diff if not accessible |

> **Note:** "review this" alone routes to **Consult** (too ambiguous). Use "review this PR" or "review this diff" to trigger PR review.

---

## 🔄 Refresh — Keep docs up to date
_Detects stale docs via git SHA comparison, zero API cost until approved_

| What you say | What happens |
|---|---|
| `refresh` | Staleness report → regenerate approved docs |
| `rescan` | Same |
| `update knowledge` | Same |
| `re-learn this repo` | Same |

---

## 📋 Requirements — Build a feature
_Discovery-first: never jumps to code before understanding the requirement_

| What you say | What happens |
|---|---|
| `we need to build X` | Phase 1: surfaces conflicts from codebase, asks one question at a time |
| `the requirement is Y` | Same |
| `the client wants Z` | Same |
| `users should be able to X` | Same |
| `add a feature that...` | Same |
| `implement this story` | Same |
| `new business rule: ...` | Same |
| _(paste a PRD or Jira ticket)_ | Same — extracts requirement from the pasted text |

**Delivery options after approval:**
| Option | What you say | What happens |
|---|---|---|
| A | `full solution` | Generates all approved changes at once |
| B | `step by step` | One change at a time with progress tracker |
| C | `TDD only` | Technical Design Document saved to `docs/tdd/` — no code yet |

---

## Priority order when multiple modes match

```
PR Review  >  Refresh  >  Requirements  >  Consult  >  Bootstrap
```
