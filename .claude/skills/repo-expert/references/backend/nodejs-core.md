# Backend Reference: Node.js Core

Covers: NestJS · Express · Fastify · API Design · TypeScript patterns

---

## NestJS Architecture

### Module boundaries — the golden rule
Each feature module owns: controller, service, repository, DTOs, entities.
Nothing leaks across module boundaries except through exported providers.

```
src/
  orders/
    orders.module.ts       ← imports, exports, providers
    orders.controller.ts   ← HTTP surface only, no business logic
    orders.service.ts      ← all business logic lives here
    orders.repository.ts   ← all DB access lives here
    dto/
      create-order.dto.ts
      order-response.dto.ts
    entities/
      order.entity.ts
```

**Shared modules** (DatabaseModule, RedisModule, PubSubModule) → `src/shared/` or `src/core/`
**Dynamic modules** for config-driven behavior → use `forRoot` / `forRootAsync` pattern

### Dependency injection patterns

```typescript
// Non-class providers (config values, external clients)
export const STRIPE_CLIENT = new InjectionToken<Stripe>('STRIPE_CLIENT');

// Async initialization
{
  provide: STRIPE_CLIENT,
  useFactory: async (config: ConfigService) => new Stripe(config.get('STRIPE_KEY')),
  inject: [ConfigService],
}

// Request-scoped (use sparingly — kills performance at scale)
@Injectable({ scope: Scope.REQUEST })
```

### Guards · Interceptors · Pipes · Filters — when to use what

| Tool | Use for |
|---|---|
| Guard | Auth, authorization, role/permission checks |
| Interceptor | Logging, caching, response transformation, timing |
| Pipe | Input validation and transformation (class-validator + class-transformer) |
| Filter | Error normalization, mapping exceptions to HTTP responses |
| Middleware | Raw HTTP concerns — CORS, rate limiting, request ID injection |

### Common NestJS pitfalls

- **Missing `await`** on async queue processor operations → silent failures
- **N+1 in repositories** → use `QueryBuilder.leftJoinAndSelect()` or dataloader
- **Missing transactions** on multi-step writes → use `DataSource.transaction()` or `EntityManager`
- **`any` types in DTOs** → always use class-validator with `whitelist: true` on `ValidationPipe`
- **Circular dependencies** → use `forwardRef` as last resort, fix the design root cause
- **Large God services** → split by subdomain when service exceeds ~300 lines

### Global ValidationPipe setup (always apply)

```typescript
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,          // strip unknown properties
  forbidNonWhitelisted: true,
  transform: true,          // auto-transform to DTO types
  transformOptions: { enableImplicitConversion: true },
}));
```

---

## Express / Fastify patterns

### Error handling middleware (Express)

```typescript
// Always last middleware — catches everything above it
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  const status = err instanceof HttpError ? err.status : 500;
  logger.error({ err, path: req.path }, 'Unhandled error');
  res.status(status).json({ error: err.message });
});
```

### Fastify schema validation (built-in, faster than class-validator)

```typescript
fastify.post('/orders', {
  schema: {
    body: {
      type: 'object',
      required: ['userId', 'items'],
      properties: {
        userId: { type: 'string', format: 'uuid' },
        items: { type: 'array', minItems: 1 },
      },
    },
  },
}, handler);
```

---

## API Design

### REST endpoint naming conventions

```
GET    /orders              → list (paginated)
GET    /orders/:id          → single resource
POST   /orders              → create
PATCH  /orders/:id          → partial update
PUT    /orders/:id          → full replace (use rarely)
DELETE /orders/:id          → soft or hard delete
POST   /orders/:id/cancel   → state transitions as verbs on sub-resource
```

### Pagination — always use cursor-based for large datasets

```typescript
// Offset pagination — simple but slow at high offsets
GET /orders?page=1&limit=20

// Cursor pagination — consistent performance regardless of dataset size
GET /orders?cursor=eyJpZCI6MTAwfQ&limit=20
// cursor = base64(JSON({ id: lastSeenId }))
```

### Versioning strategy

```typescript
// URI versioning (most common, explicit)
/api/v1/orders
/api/v2/orders

// Header versioning (cleaner URLs, harder to test)
Accept: application/vnd.api+json;version=2
```

### Response envelope pattern

```typescript
// Always consistent shape — makes FE error handling predictable
{
  "data": { ... },         // null on error
  "meta": {                // pagination, timing
    "total": 100,
    "page": 1,
    "limit": 20
  },
  "error": null            // populated on error, null on success
}
```

---

## TypeScript patterns for Node.js backends

### Result type — avoid throwing for expected failures

```typescript
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

// Usage
async function findOrder(id: string): Promise<Result<Order, 'NOT_FOUND' | 'DB_ERROR'>> {
  try {
    const order = await repo.findById(id);
    if (!order) return { ok: false, error: 'NOT_FOUND' };
    return { ok: true, value: order };
  } catch {
    return { ok: false, error: 'DB_ERROR' };
  }
}
```

### Branded types — prevent ID mix-ups

```typescript
type OrderId = string & { readonly _brand: 'OrderId' };
type UserId  = string & { readonly _brand: 'UserId' };

// Now passing a UserId where OrderId is expected is a compile error
```

### Zod for runtime validation (alternative to class-validator)

```typescript
const CreateOrderSchema = z.object({
  userId: z.string().uuid(),
  items: z.array(z.object({
    productId: z.string().uuid(),
    quantity: z.number().int().positive(),
  })).min(1),
});

type CreateOrderDto = z.infer<typeof CreateOrderSchema>;
```

---

## Performance patterns

### Connection pooling — always configure explicitly

```typescript
// TypeORM
DataSource({
  extra: {
    max: 20,           // max pool size
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 3_000,
  }
})
```

### Rate limiting (NestJS + @nestjs/throttler)

```typescript
ThrottlerModule.forRoot([{
  name: 'short',
  ttl: 1000,    // 1 second
  limit: 10,    // 10 req/sec
}, {
  name: 'long',
  ttl: 60_000,  // 1 minute
  limit: 100,   // 100 req/min
}])
```

### Health checks — always expose

```typescript
// NestJS Terminus
@Get('/health')
@HealthCheck()
check() {
  return this.health.check([
    () => this.db.pingCheck('database'),
    () => this.redis.checkHealth('redis'),
  ]);
}
```
