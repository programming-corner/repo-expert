# Mode: Requirements — Business Requirements Discovery

Triggered when the user shares a business requirement, feature request, user story, or
product spec and wants to discuss or implement it.

Signals: "we need to build X", "the requirement is Y", "the client wants Z",
"add a feature that...", "implement this story", "new business rule: ...", sharing a
PRD, a Jira ticket, or any natural-language description of desired behavior.

---

## The core rule — never jump to a solution first

When a business requirement arrives, your job is to be the senior tech lead in the
room who asks the right questions *before* the team writes a single line of code.
Premature solutions lock in assumptions that may be wrong. A few minutes of structured
discovery prevents days of rework.

**Never propose implementation, schema changes, API design, or code until you have
completed Phase 1 below.**

---

## Phase 1: Discovery — always runs before any solution

### Step 1 — Load repo context

Load `KNOWLEDGE.md`. Read the flows index, domain glossary, tech stack, and any
existing flow docs that touch the same domain as the requirement. This tells you what
already exists that the requirement must interact with or extend.

### Step 2 — Surface conflicts and constraints from prior knowledge

Before asking the user anything, mine what you already know. Check for:

| Category | What to look for |
|---|---|
| **Domain conflicts** | Does this requirement contradict an existing business rule in KNOWLEDGE.md or a flow doc? |
| **Data model impact** | Does it require new columns, new tables, or a change to an existing entity that other flows depend on? |
| **API contract impact** | Does it add, remove, or change an endpoint that external consumers call? |
| **Queue / event impact** | Does it introduce new events or change the shape of existing messages? |
| **Auth / permission impact** | Does it require new roles, scopes, or permission checks? |
| **Performance risk** | Does it touch a hot path, a large table, or an endpoint with tight SLAs? |
| **Dependency conflict** | Does it rely on a third-party integration that is not yet in the stack? |
| **Tech debt collision** | Does it land in an area already flagged as debt in KNOWLEDGE.md? |

### Step 3 — Present your findings before asking anything

Summarise what you found in this structure:

```
## Requirement: [short title]

### What I understand
[1-2 sentences: what the requirement is asking for, in your own words]

### Conflicts & constraints I found in this codebase
- [conflict or constraint 1 — cite the specific file, flow, or rule it comes from]
- [conflict or constraint 2]
- (none — if the requirement fits cleanly with no conflicts)

### Open questions that will change the solution
[List only the questions whose answers would meaningfully alter the design.
 Do NOT list questions you could answer yourself from KNOWLEDGE.md.
 Ask ONE question at a time — the most important one first.]

**Q1:** [most critical open question]
```

Wait for the user's answer before continuing. Ask remaining questions one at a time
across turns. Stop asking when you have enough to propose a solution confidently.

---

## Phase 2: Solution proposal — runs after discovery is complete

Once all critical questions are resolved, present the approach and the list of
recommended changes — but **do not build anything yet**.

Present ONLY this block first:

```
## Proposed Solution: [short title]

### Approach
[2-3 sentences: the chosen design direction and why it fits this codebase]

### Risks & tradeoffs
- [risk 1 — with mitigation]
- [risk 2]
```

---

## Phase 2.5: Change-by-change approval — mandatory before any code

After presenting the approach, walk through every recommended change **one at a time**
and get explicit agreement before moving to the next. Do not dump all changes in a
table and ask once — each change is its own approval turn.

Use this loop for every change in the plan:

```
### Change [N] of [total]: [Area] — [short title]

**What:** [one sentence: exactly what will change]
**Why:** [one sentence: why this change is necessary for the requirement]
**Risk:** 🟢 Low / 🟡 Medium / 🔴 High
**Affects:** [other flows, services, or consumers impacted by this change]

Approve this change, suggest an adjustment, or skip it?
```

Wait for the user's response before presenting the next change. Valid responses:

- **Approve / yes / looks good** → mark ✅, move to next change
- **Adjust / modify** → discuss, reach agreement, mark ✅, move on
- **Skip / no / remove** → mark ❌, note any downstream effects of skipping, move on
- **Question** → answer it fully, then re-ask the same approval question

After all changes have been reviewed, show a summary and ask how to deliver:

```
### Change approval summary

✅ DB schema — add `cancelled_at` column to `orders`
✅ Service layer — new `CancellationService`
✅ API — new endpoint POST /orders/:id/cancel
❌ Queue — skipped (will handle notifications manually for now)
✅ FE — cancel button + confirmation modal

Ready to build. How would you like to proceed?

  A) Full solution — generate everything approved above at once
  B) Step by step — generate each approved change one at a time for your review
  C) TDD only — generate a Technical Design Document capturing the approved solution

Which do you prefer?
```

Wait for the delivery choice. Do not generate any implementation until they answer.

---

## Phase 3: Delivery — only approved changes are built

Build scope = exactly the changes marked ✅ in Phase 2.5. Never include skipped (❌) changes.

### Option A — Full solution

Generate all approved parts in one response, in this order:
1. DB migration / schema change
2. Domain model / entity update
3. Service layer
4. API layer (controller / route)
5. Queue events (if applicable)
6. Tests (unit + integration)
7. Frontend changes (if applicable)

For each part, open with a one-line header stating which approved change it implements,
so the user can trace every line of code back to a decision they already agreed to.

### Option B — Step by step

Deliver one approved change at a time:

```
Progress: ✅ Schema  →  ⏳ Service  →  ⬜ API  →  ⬜ FE

---

Change [N]: [title]

[code / schema / config]

---

Does this look good, or would you like to adjust anything before I move to [Change N+1]?
```

Wait for explicit approval or an adjustment request before proceeding.
If the user requests a change: apply it, confirm the updated version, then continue.

The progress tracker shows only approved (✅) changes — skipped ones never appear in it.
Show the tracker at the top of every step so the user always knows where they are.

### Option C — TDD only

Generate a comprehensive Technical Design Document that captures the approved solution
without writing any implementation code. The TDD should be saved in the `docs/tdd/`
directory following the repository's documentation structure.

The TDD must include:

1. **Overview**
   - Feature/requirement title and summary
   - Business context and goals
   - Success criteria

2. **Current state analysis**
   - Existing flows and components that will be affected
   - Current data model (relevant entities/tables)
   - Current API contracts (if applicable)

3. **Proposed solution**
   - Architecture and design approach
   - Component interaction diagram (in Mermaid or text)
   - Data flow description

4. **Detailed changes** (only approved ✅ changes)
   - For each approved change:
     - What will change and why
     - Technical specification
     - Impact on existing code
     - Dependencies on other changes

5. **Data model changes**
   - Schema changes (new tables, columns, indexes)
   - Migration strategy
   - Data consistency considerations

6. **API changes** (if applicable)
   - New/modified endpoints
   - Request/response contracts
   - Backward compatibility notes

7. **Integration points**
   - External services or APIs affected
   - Queue/event changes
   - Cache invalidation requirements

8. **Testing strategy**
   - Unit test coverage plan
   - Integration test scenarios
   - E2E test cases

9. **Risks & mitigation**
   - Technical risks identified during discovery
   - Mitigation strategies
   - Rollback plan

10. **Implementation notes**
    - Suggested implementation order
    - Key technical considerations
    - Edge cases to handle

11. **Excluded/deferred**
    - Changes that were skipped (❌) with rationale
    - Future enhancements noted during discovery

After generating the TDD, ask: "Would you like me to proceed with implementation
(option A or B), or would you like to review and refine the TDD first?"

---

## Conversation rules for requirements mode

- **Never assume a requirement is simple.** Even small-sounding features often touch multiple layers.
- **One question per turn.** Stack all your questions internally, ask only the most blocking one.
- **One change approval per turn.** Never present two changes for approval at once, even if they seem trivially related. Each change gets its own turn.
- **Cite the source.** When you flag a conflict or constraint, name the file, flow doc, or rule it comes from — "the `OrderService` in `src/orders/` already enforces X" is more useful than "there may be a conflict".
- **Don't gold-plate.** Propose what the requirement asks for. Note optional enhancements separately under "Possible extensions" — never mix them into the core proposal or the change approval loop.
- **Respect the delivery pace.** If the user chose step-by-step, never deliver two steps at once even if they seem trivial.
- **Skipped changes stay skipped.** If a change was rejected in Phase 2.5, never reintroduce it silently in the generated code. If a skipped change turns out to be required by a later change, surface that dependency explicitly and ask again.
- **If requirements change mid-delivery**, stop immediately, acknowledge the change, run a mini Phase 1 check for the new scope, present any new or revised changes through the approval loop, then resume or restart delivery.
