# Go Backend Reference

Load this file when the repo uses Go (Gin, Echo, Fiber, gRPC, standard library).

---

## Project Structure Conventions

```
cmd/
  server/main.go          ← entry point per binary
internal/
  domain/                 ← business logic (no framework imports)
  handler/                ← HTTP / gRPC handlers
  repository/             ← DB access
  service/                ← orchestration layer
  middleware/
pkg/                      ← code safe to import by external packages
```

The `internal/` boundary is enforced by the Go compiler — external packages cannot import it.

---

## Context Propagation

Context must flow through every function call chain:
```go
// CORRECT — context threaded through
func (s *OrderService) GetOrder(ctx context.Context, id string) (*Order, error) {
    return s.repo.FindByID(ctx, id)
}

// WRONG — context dropped
func (s *OrderService) GetOrder(id string) (*Order, error) {
    return s.repo.FindByID(context.Background(), id) // ← loses deadline/cancellation
}
```

Always set timeouts on outbound calls:
```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
resp, err := http.Get(ctx, url)
```

---

## Error Handling

```go
// Wrap errors with context (errors package or github.com/pkg/errors)
if err != nil {
    return fmt.Errorf("order service GetOrder %s: %w", id, err)
}

// Sentinel errors for type checking
var ErrNotFound = errors.New("not found")

if errors.Is(err, ErrNotFound) {
    // handle not found
}
```

- Never swallow errors silently (`_ = someFunc()` is almost always wrong)
- Use `%w` in `fmt.Errorf` to preserve the error chain
- Return errors up the stack; log only at the top (handler) level

---

## Goroutine Patterns

```go
// Always provide a cancel path to avoid goroutine leaks
ctx, cancel := context.WithCancel(context.Background())
defer cancel()

go func() {
    for {
        select {
        case <-ctx.Done():
            return // goroutine exits when context cancelled
        case msg := <-ch:
            process(msg)
        }
    }
}()
```

### Common goroutine pitfalls
- **Loop variable capture**: `go func() { use(v) }()` in a loop captures the pointer, not the value — use `v := v` inside the loop
- **WaitGroup misuse**: call `wg.Add(n)` before spawning goroutines, not inside them
- **`defer` inside loops**: defers accumulate until the function returns — extract to a helper function

---

## Database (database/sql + sqlx / pgx)

```go
// Always use parameterized queries
row := db.QueryRowContext(ctx, 
    "SELECT id, status FROM orders WHERE id = $1", orderID)

// N+1 prevention — batch load
rows, err := db.QueryContext(ctx,
    "SELECT * FROM order_items WHERE order_id = ANY($1)", pq.Array(orderIDs))
```

### Transaction pattern
```go
tx, err := db.BeginTx(ctx, nil)
if err != nil { return err }
defer func() {
    if p := recover(); p != nil { _ = tx.Rollback(); panic(p) }
    if err != nil { _ = tx.Rollback() }
    err = tx.Commit()
}()
```

---

## Code Quality Checklist
- [ ] `go vet ./...` passes with no warnings
- [ ] `golangci-lint run` clean (at minimum: `errcheck`, `staticcheck`, `gosec`)
- [ ] No `init()` functions for side effects — use explicit initialization
- [ ] Interfaces defined at the consumer, not the producer
- [ ] Exported types and functions have Go doc comments
- [ ] Table-driven tests using `t.Run()` subtests

---

## Security Checklist
- [ ] `gosec` scanner passes
- [ ] No `G104` (errors unhandled) or `G304` (file path injection)
- [ ] TLS configured for all outbound connections
- [ ] `govulncheck ./...` for dependency CVEs
- [ ] Secrets in env vars — never in source or binary
