# Python Backend Reference

Load this file when the repo uses Python (Django, FastAPI, Flask, Celery, SQLAlchemy).

---

## Framework Patterns

### FastAPI
- Use `Depends()` for DI — services, DB sessions, auth
- Always define `response_model=` on endpoints to control serialization
- Use `APIRouter` with prefix/tags for module separation
- Lifespan events (`@asynccontextmanager`) replace deprecated `startup`/`shutdown`
- `BackgroundTasks` for fire-and-forget; Celery for reliable async work

### Django
- Fat models / thin views is the Django convention — but push business logic to service modules in complex apps
- Use `select_related()` for FK/O2O, `prefetch_related()` for M2M and reverse FK
- Always use `F()` expressions for atomic field updates (avoid race conditions)
- Database transactions: `transaction.atomic()` — use as context manager or decorator
- Custom managers over raw QuerySet filtering in views

### Flask
- Application factory pattern (`create_app()`) for testability
- Use `Blueprint` for module separation
- `flask-sqlalchemy` session lifecycle: always close/rollback in teardown

---

## Async Patterns

```python
# FastAPI — async endpoint with DB dependency
@router.get("/orders/{order_id}")
async def get_order(
    order_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> OrderResponse:
    order = await order_service.get_by_id(db, order_id)
    if not order:
        raise HTTPException(status_code=404)
    return OrderResponse.from_orm(order)
```

### Common async pitfalls
- **Blocking calls in async context**: never call `requests`, `time.sleep`, or sync ORM inside `async def` — use `httpx`, `asyncio.sleep`, async ORM
- **Missing `await`**: `async def` functions return coroutines silently if not awaited
- **Thread safety**: `asyncio.Lock()` for shared mutable state in async code

---

## Celery (Task Queue)

```python
@celery_app.task(
    bind=True,
    max_retries=3,
    default_retry_delay=60,
    autoretry_for=(TransientError,),
)
def send_notification(self, user_id: str, message: str) -> None:
    try:
        notification_service.send(user_id, message)
    except TransientError as exc:
        raise self.retry(exc=exc, countdown=2 ** self.request.retries)
```

- **Idempotency**: use task ID or business key in Redis to deduplicate
- **Soft time limits**: `soft_time_limit` raises `SoftTimeLimitExceeded`; `time_limit` kills the worker process
- **Result backend**: use Redis for transient results; avoid storing large payloads
- **Task routing**: route CPU-bound tasks to dedicated queues with fewer workers

---

## SQLAlchemy Patterns

### Session management
```python
# Always use context manager or dependency injection
async with async_session() as session:
    async with session.begin():
        session.add(order)
        # auto-commit on exit, auto-rollback on exception
```

### N+1 prevention
```python
# Eager loading with joinedload / selectinload
result = await session.execute(
    select(Order)
    .options(selectinload(Order.items))
    .where(Order.user_id == user_id)
)
```

### Migration safety (Alembic)
- Never rename columns in one step — add + migrate + drop
- `op.execute("CREATE INDEX CONCURRENTLY ...")` for zero-downtime index creation
- Always test migration rollback (`alembic downgrade -1`) before deploying

---

## Code Quality Checklist
- [ ] Type hints on all function signatures (`mypy --strict` or `pyright`)
- [ ] No mutable default arguments (`def f(x=[])` is a bug)
- [ ] `__all__` defined in public modules
- [ ] No bare `except:` — catch specific exceptions
- [ ] f-strings over `.format()` for performance and readability
- [ ] `pathlib.Path` over `os.path` for file operations
- [ ] `dataclasses` or Pydantic models over raw dicts for structured data

---

## Security Checklist
- [ ] Parameterized queries everywhere — never `f"SELECT ... WHERE id = {user_input}"`
- [ ] `SECRET_KEY` and credentials in env vars, not source code
- [ ] `DEBUG=False` in production; `ALLOWED_HOSTS` set
- [ ] `python-jose` or `PyJWT` for JWT — validate `exp`, `iss`, `aud`
- [ ] `safety check` or `pip-audit` for dependency CVEs
