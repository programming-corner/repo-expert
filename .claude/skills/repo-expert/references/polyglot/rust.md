# Rust Backend Reference

Load this file when the repo uses Rust (Axum, Actix-web, Tokio, SQLx).

---

## Project Structure

```
src/
  main.rs           ← entry point, router setup
  lib.rs            ← library root (if dual-mode)
  routes/           ← handler functions per domain
  services/         ← business logic
  repositories/     ← DB access (SQLx queries)
  models/           ← domain types
  errors.rs         ← unified error type
  config.rs         ← AppConfig struct from env
```

---

## Error Handling

```rust
// Define a unified error type with thiserror
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("not found: {0}")]
    NotFound(String),

    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("validation error: {0}")]
    Validation(String),
}

// Axum: implement IntoResponse for AppError
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            AppError::NotFound(_)    => (StatusCode::NOT_FOUND, self.to_string()),
            AppError::Validation(_)  => (StatusCode::BAD_REQUEST, self.to_string()),
            AppError::Database(_)    => (StatusCode::INTERNAL_SERVER_ERROR, "internal error".into()),
        };
        (status, Json(json!({"error": message}))).into_response()
    }
}
```

- Avoid `.unwrap()` and `.expect()` in production paths — propagate with `?`
- Use `anyhow::Context` to add context without boxing: `.context("loading config")?`

---

## Async with Tokio

```rust
// Spawn blocking work onto a thread pool
let result = tokio::task::spawn_blocking(|| {
    heavy_cpu_computation()
}).await?;

// Never call blocking I/O inside async fn
// WRONG:
async fn handler() { std::fs::read("file.txt"); }    // blocks the executor

// CORRECT:
async fn handler() { tokio::fs::read("file.txt").await?; }
```

### Common async pitfalls
- **`Mutex` across `.await`**: use `tokio::sync::Mutex`, not `std::sync::Mutex` — the std mutex is not safe to hold across await points
- **Unbounded channels**: `tokio::sync::mpsc::channel(n)` with bounded buffer to apply backpressure
- **Forgetting to poll futures**: futures are lazy — they don't run until `.await`ed or spawned

---

## SQLx Patterns

```rust
// Compile-time checked queries (preferred)
let order = sqlx::query_as!(
    Order,
    "SELECT id, status, total FROM orders WHERE id = $1",
    order_id
)
.fetch_optional(&pool)
.await?
.ok_or(AppError::NotFound(order_id.to_string()))?;
```

### Transaction
```rust
let mut tx = pool.begin().await?;

sqlx::query!("UPDATE orders SET status = $1 WHERE id = $2", "confirmed", id)
    .execute(&mut *tx)
    .await?;

sqlx::query!("INSERT INTO payments ...")
    .execute(&mut *tx)
    .await?;

tx.commit().await?;
```

---

## Memory & Ownership Patterns

- **Avoid unnecessary `.clone()`**: pass references (`&T`) where ownership is not needed
- **`Arc<T>` for shared state**: wrap shared app state in `Arc` — required for multi-threaded handlers
- **`Cow<str>` for conditionally owned strings**: avoids clone when the data might already be owned
- **`Vec` pre-allocation**: `Vec::with_capacity(n)` when size is known to avoid reallocations

---

## Code Quality Checklist
- [ ] `cargo clippy -- -D warnings` passes
- [ ] `cargo fmt` applied
- [ ] `cargo test` passes with no `#[allow(unused)]` hiding failures
- [ ] No `unsafe` blocks without a `// SAFETY:` comment explaining invariants
- [ ] `cargo audit` clean (dependency CVEs)
- [ ] `cargo deny` configured for license policy

---

## Security Checklist
- [ ] `cargo audit` passes (RustSec advisory database)
- [ ] No `unwrap()` in request handling paths
- [ ] Input deserialization with `serde` — no manual string parsing
- [ ] Secrets in env vars via `dotenvy` — never hardcoded
- [ ] TLS via `rustls` or `openssl`; validate certs on outbound connections
