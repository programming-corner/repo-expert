# Stack Templates — What to Read Per Flow

Used in Phase 4 of bootstrap. For each selected flow, read only these files.

## Node.js / NestJS

| File pattern | What it reveals |
|---|---|
| `*.module.ts` | Module boundaries and dependency graph |
| `*.controller.ts` | API surface — endpoints and request shapes |
| `*.service.ts` | Business logic |
| `*.entity.ts` / `*.schema.ts` | Data model |
| `*.processor.ts` / `*.consumer.ts` | Queue workers and async jobs |
| `*.guard.ts` / `*.interceptor.ts` | Cross-cutting concerns (auth, logging) |
| `*.dto.ts` | Input/output contracts |

## Python (Django / FastAPI / Flask)

| File pattern | What it reveals |
|---|---|
| `views.py`, `routers/*.py`, `routes.py` | API surface |
| `models.py`, `schemas.py` | Data model |
| `services.py`, `domain/*.py` | Business logic |
| `tasks.py`, `workers/*.py`, `celery*.py` | Async/queue processing |
| `serializers.py` | Input/output contracts |
| `middleware.py` | Cross-cutting concerns |

## Go

| File pattern | What it reveals |
|---|---|
| `handlers/`, `routes/*.go`, `api/*.go` | API surface |
| `service*.go`, `domain/*.go` | Business logic |
| `models/*.go`, `entities/*.go` | Data model |
| `worker*.go`, `job*.go`, `queue*.go` | Async processing |
| `middleware/*.go` | Cross-cutting concerns |

## Java / Kotlin (Spring)

| File pattern | What it reveals |
|---|---|
| `*Controller.java/kt` | API surface |
| `*Service.java/kt` | Business logic |
| `*Repository.java/kt` | Data access layer |
| `*Entity.java/kt`, `*Model.java/kt` | Data model |
| `*Listener.java/kt`, `*Consumer.java/kt` | Queue/event consumers |

## Rust

| File pattern | What it reveals |
|---|---|
| `routes/*.rs`, `handlers/*.rs` | API surface |
| `services/*.rs`, `domain/*.rs` | Business logic |
| `models/*.rs`, `entities/*.rs` | Data model |
| `workers/*.rs`, `jobs/*.rs` | Async processing |

## Ruby (Rails)

| File pattern | What it reveals |
|---|---|
| `app/controllers/` | API surface |
| `app/models/` | Data model |
| `app/services/` | Business logic |
| `app/jobs/`, `app/workers/` | Async processing |

## Frontend (Next.js / React)

| File pattern | What it reveals |
|---|---|
| `app/` or `pages/` | Routing structure |
| `components/` | Component library shape |
| `hooks/` | Custom hook patterns |
| `store/`, `context/`, `redux/` | State management |
| `lib/`, `utils/` | Shared utilities |
| `types/`, `interfaces/` | Shared type contracts |

## Shared (any stack)

| File pattern | What it reveals |
|---|---|
| `types/`, `interfaces/`, `dto/` | Shared contracts |
| `constants/`, `config/` | Configuration shape |
| `proto/`, `*.proto` | gRPC contracts |
| `openapi.yaml`, `swagger.json` | REST API spec |
