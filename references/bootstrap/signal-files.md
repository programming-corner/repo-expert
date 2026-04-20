# Signal Files — Stack Detection Reference

Read these files during Phase 1 of bootstrap. No other source files.

| File | What it tells you |
|---|---|
| `README.md` | Always read first — repo purpose and overview |
| `.env.example`, `config/` | Integration names and env var keys — never surface actual values |
| `docker-compose.yml` / `docker-compose.yaml` | Local infra: DBs, Redis, queues |
| `Dockerfile` | Runtime container and base image |
| `.github/workflows/` | CI/CD pipeline structure |
| `Makefile` | Common task targets |
| `package.json` | Runtime, framework, scripts, deps |
| `tsconfig.json` | TypeScript config and path aliases |
| `nest-cli.json` | NestJS confirmed |
| `next.config.*` | Next.js confirmed |
| `pyproject.toml`, `requirements.txt` | Python deps and tooling |
| `go.mod` | Go modules and dependencies |
| `pom.xml`, `build.gradle` | Java/Kotlin deps |
| `Cargo.toml` | Rust crates |
| `Gemfile` | Ruby deps |
| `composer.json` | PHP deps |
| `prisma/schema.prisma` | Data models — read all models |
| `migrations/`, `db/` | DB schema history |

## Stack Detection Rules

| Signal | Detected Stack |
|---|---|
| `nest-cli.json` + `package.json` | NestJS (Node.js) |
| `next.config.*` + `package.json` | Next.js (React) |
| `package.json` only | Node.js (check scripts for framework) |
| `pyproject.toml` or `requirements.txt` | Python (check for Django/FastAPI/Flask) |
| `go.mod` | Go |
| `pom.xml` | Java (Spring if spring deps present) |
| `build.gradle` | Java/Kotlin |
| `Cargo.toml` | Rust |
| `Gemfile` | Ruby (check for Rails) |
| `composer.json` | PHP (check for Laravel/Symfony) |
| Multiple `package.json` at root + subdirs | Monorepo (check for nx, turborepo, lerna) |
