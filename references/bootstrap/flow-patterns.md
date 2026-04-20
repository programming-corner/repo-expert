# Flow Patterns — Naming & Detection Reference

Used in Phase 2 of bootstrap to infer flows from folder/file structure alone.

## Backend Flow Detection

| Pattern | Inferred Flow | Icon |
|---|---|---|
| `src/<domain>/` folder | `[Domain] flow` | 🔄 |
| `*.controller.ts`, `views.py`, `routes/*.go`, `handlers/` | API surface hint — group by domain | 🌐 |
| `*.processor.ts`, `*.consumer.ts`, `*worker*`, `celery*.py` | Queue / async processing flow | 📦 |
| `*.gateway.ts`, `*websocket*`, `*ws*` | Realtime / WebSocket flow | ⚡ |
| `migrations/`, `db/` | DB migration flow | 🗄️ |
| `src/auth/`, `*auth*`, `*jwt*`, `*session*` | Auth flow | 🔐 |
| `src/payment*`, `*stripe*`, `*billing*` | Payment flow | 💳 |
| `src/notification*`, `*email*`, `*sms*` | Notification flow | 🔔 |
| `src/search*`, `*elasticsearch*`, `*algolia*` | Search flow | 🔍 |
| `src/file*`, `*upload*`, `*s3*`, `*storage*` | File / storage flow | 📁 |

## Frontend Area Detection

| Pattern | Inferred Area | Icon |
|---|---|---|
| `app/<section>/` or `pages/<section>/` | One area per route group | varies |
| `components/<name>/` (>3 files) | Component area | 🧩 |
| `store/` or `context/` or `redux/` | State management area | 🗃️ |
| `app/checkout/` or `pages/checkout/` | Checkout UI | 🛍️ |
| `app/auth/` or `pages/login/` | Auth UI | 🔑 |
| `app/dashboard/` | Dashboard UI | 📊 |
| `app/profile/` or `pages/account/` | Profile / Account UI | 👤 |
| `app/admin/` | Admin UI | ⚙️ |

## Monorepo App Detection

| Pattern | Inferred App |
|---|---|
| `apps/<name>/` | One app per directory |
| `packages/<name>/` | Shared library/package |
| `services/<name>/` | One microservice per directory |

## Naming Rules

- Name flows by domain, not by file type: "Order flow" not "order.service.ts"
- One flow = one cohesive business domain
- If a folder is too small (<3 files), merge it into the nearest parent domain
- Avoid generic names like "utils flow" or "helpers flow" — these are not flows
