# Mode: Bootstrap — First Time in a Repo

Triggered when `KNOWLEDGE.md` does not exist in repo root or `.claude/`.

---

## Step 1 — Detect the stack

Walk the directory tree. Read these signal files:

### Universal signals (every repo)
| File | What it tells you |
|---|---|
| `README.md` | Always read first |
| `.env.example`, `config/` | Integrations, env vars, third-party services |
| `docker-compose.yml`, `docker-compose.yaml` | Local infra — DBs, Redis, queues |
| `Dockerfile` | Runtime container |
| `.github/workflows/` | CI/CD pipeline |
| `Makefile` | Common task targets |
| `migrations/`, `db/` | DB schema history |

### Node.js signals
| File | What it tells you |
|---|---|
| `package.json` | Runtime, framework, scripts — read deps carefully |
| `tsconfig.json` | TypeScript, path aliases |
| `nest-cli.json` | NestJS confirmed |
| `next.config.*` | Next.js (fullstack or FE-only) |
| `vite.config.*` | Vite-based React SPA |
| `prisma/schema.prisma` | Prisma ORM — read all models |
| `src/app.module.ts` | NestJS root — read all imports |
| `src/main.ts` | NestJS entry point |
| `apps/`, `packages/` | Monorepo — read workspace config |
| `jest.config.*`, `vitest.config.*` | Test setup |

### Python signals
| File | What it tells you |
|---|---|
| `pyproject.toml`, `requirements.txt`, `setup.py` | Python — read deps |
| `manage.py` | Django — read settings |
| `alembic/`, `alembic.ini` | Alembic migrations |
| `celery*.py`, `celeryconfig.py` | Celery task queues |
| `conftest.py` | pytest fixtures |

### Go signals
| File | What it tells you |
|---|---|
| `go.mod`, `go.sum` | Go modules |
| `cmd/` | Entry points |
| `internal/` | Private packages |
| `pkg/` | Public packages |

### Java / Kotlin signals
| File | What it tells you |
|---|---|
| `pom.xml` | Maven — read deps |
| `build.gradle`, `build.gradle.kts` | Gradle |
| `src/main/resources/application.yml` | Spring Boot config |

### Rust signals
| File | What it tells you |
|---|---|
| `Cargo.toml`, `Cargo.lock` | Rust crates and deps |
| `src/main.rs`, `src/lib.rs` | Entry points |

### Ruby / PHP signals
| File | What it tells you |
|---|---|
| `Gemfile`, `Gemfile.lock` | Ruby — read deps |
| `config/routes.rb` | Rails routing |
| `composer.json` | PHP — read deps |

---

## Step 2 — Identify project type

**From Node.js `package.json` deps:**

| Detected | Project type |
|---|---|
| `@nestjs/core` | NestJS backend |
| `next` | Next.js fullstack or FE-only |
| `react` + `vite` | React SPA |
| NestJS + Next.js | Monorepo fullstack |
| `express` or `fastify` | Lightweight Node.js API |

**From other stacks:**

| Detected | Project type |
|---|---|
| `django` or `fastapi` or `flask` | Python web API |
| `gin`, `echo`, `fiber` in go.mod | Go HTTP API |
| `spring-boot` in pom.xml | Java Spring Boot |
| `axum` or `actix-web` in Cargo.toml | Rust web API |
| `rails` in Gemfile | Ruby on Rails |
| `laravel/framework` in composer.json | PHP Laravel |

---

## Step 3 — Read key source files

**Backend (Node.js / NestJS):**
- `*.module.ts` → module boundaries
- `*.controller.ts` → API surface
- `*.service.ts` → business logic
- `*.entity.ts` / `*.schema.ts` → data model
- `*.processor.ts` / `*.consumer.ts` → queue workers
- `*.guard.ts` / `*.interceptor.ts` → cross-cutting concerns

**Backend (Python / Go / Java / Rust):**
- Routing files (views.py, routes/, handlers/) → API surface
- Service/domain files → business logic
- Model/schema files → data model
- Worker/task files → async processing

**Frontend (Next.js / React):**
- `app/` or `pages/` → routing structure
- `components/` → component library shape
- `hooks/` → custom hook patterns
- `store/` / `context/` → state management
- `lib/` / `utils/` → shared utilities

**Shared:**
- `types/` / `interfaces/` / `dto/` → shared contracts
- `constants/` / `config/` → configuration shape

---

## Step 4 — Generate KNOWLEDGE.md

Save to repo root (or `.claude/` if that folder exists).
Load `references/doc-templates.md` for the exact template.

KNOWLEDGE.md must be lean — max ~200 lines. It is the index, not the encyclopedia.

---

## Step 5 — Interactive Discovery

After writing KNOWLEDGE.md, present clearly:

```
I've learned this repo. Here's what I found:

**[Repo Name]** — [one-line purpose]
Stack: [detected stack]
Type: [Backend API / Fullstack / SPA / Monorepo / CLI / Library]

Backend flows identified (N):
1. [icon] [Flow name]
...

Frontend areas identified (N):   ← omit if no frontend
1. [icon] [Area name]
...

Which flows or areas should I document in detail now?
(The rest are available on demand — just ask)
```

Wait for selection. Generate selected docs using templates from `references/doc-templates.md`.
Save each to `docs/expert/<slug>.md`.

Then ask one final question:
> "Anything I should know before answering questions — business rules, legacy quirks, naming conventions, known pain points?"

Record the answer in KNOWLEDGE.md under `## Notes from the Team`.

Finally, tell the user:
> "Run `npx tsx scripts/refresh.ts --install-hooks` to set up automatic staleness detection after merges. No API key required — detection is purely git-based."
