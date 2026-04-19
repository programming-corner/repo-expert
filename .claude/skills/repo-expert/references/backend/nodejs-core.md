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

---

## Memory Leak Patterns

### Event emitter listeners never removed
```typescript
// BAD — new listener added on every request, never removed
app.on('request', (req, res) => {
  someEmitter.on('data', (chunk) => process(chunk));
});

// GOOD — remove after use
const handler = (chunk) => process(chunk);
someEmitter.on('data', handler);
someEmitter.once('end', () => someEmitter.off('data', handler));
```
**Detection signal:** `emitter.listenerCount('event')` growing over time, or `MaxListenersExceededWarning` in logs.

### Timers holding references
```typescript
// BAD — interval keeps the process alive and leaks closure scope
class PollingService {
  start() {
    setInterval(() => this.poll(), 5000); // ref never stored
  }
}

// GOOD — store and clear on shutdown
class PollingService implements OnApplicationShutdown {
  private timer: NodeJS.Timeout;
  start() { this.timer = setInterval(() => this.poll(), 5000); }
  onApplicationShutdown() { clearInterval(this.timer); }
}
```

### Unbounded module-level caches
```typescript
// BAD — grows forever, never evicted
const cache = new Map<string, Result>();
export function get(key: string) {
  if (!cache.has(key)) cache.set(key, compute(key));
  return cache.get(key);
}

// GOOD — cap size or use a proper LRU (e.g. lru-cache)
import { LRUCache } from 'lru-cache';
const cache = new LRUCache<string, Result>({ max: 1000, ttl: 60_000 });
```

### Streams not consumed or destroyed
```typescript
// BAD — response stream never read; buffer grows in memory
const res = await fetch(url);
// forgot to consume res.body

// GOOD — always consume or destroy
const res = await fetch(url);
if (!res.ok) { await res.body?.cancel(); throw new Error(res.statusText); }
const data = await res.json();
```

### NestJS REQUEST-scoped providers — silent memory pressure
```typescript
// BAD — creates a full DI sub-tree per request; high-traffic = high heap churn
@Injectable({ scope: Scope.REQUEST })
export class OrderService { ... }

// GOOD — default singleton scope unless you genuinely need per-request state
@Injectable()
export class OrderService { ... }
```

### Missing shutdown hooks — connections left open
```typescript
// BAD — DB/Redis connections stay open after app stops → eventual leak in long-running envs
@Module({}) export class AppModule {}

// GOOD
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableShutdownHooks(); // triggers OnApplicationShutdown on all providers
  await app.listen(3000);
}
```

---

## Event Loop Blocking Patterns

Node.js runs JS on a single thread. Any synchronous work > ~1ms on the hot path delays every other request.

### Sync I/O in request handlers
```typescript
// BAD — blocks the event loop for the duration of the read
app.get('/config', (req, res) => {
  const cfg = fs.readFileSync('./config.json', 'utf8'); // blocks!
  res.json(JSON.parse(cfg));
});

// GOOD — async I/O yields control back to the event loop
app.get('/config', async (req, res) => {
  const cfg = await fs.promises.readFile('./config.json', 'utf8');
  res.json(JSON.parse(cfg));
});
```

### Sync crypto on the hot path
```typescript
// BAD — pbkdf2Sync blocks for ~100ms per call
const hash = crypto.pbkdf2Sync(password, salt, 100_000, 64, 'sha512');

// GOOD — async version uses the libuv thread pool
const hash = await promisify(crypto.pbkdf2)(password, salt, 100_000, 64, 'sha512');
```

### JSON.parse / JSON.stringify on large payloads
```typescript
// BAD — parsing a 10MB JSON object synchronously stalls all other requests
const data = JSON.parse(req.body); // if body is huge

// GOOD — stream-parse with a library, or reject oversized payloads early
app.use(express.json({ limit: '1mb' })); // reject before it hits your handler
```

### Catastrophic regex backtracking
```typescript
// BAD — nested quantifiers cause exponential backtracking on crafted input
const EMAIL_RE = /^([a-zA-Z0-9]+)*@/; // ReDoS vector

// GOOD — linear-time regex or a dedicated validation library
import isEmail from 'validator/lib/isEmail';
if (!isEmail(input)) throw new BadRequestException('Invalid email');
```

### Sequential awaits where parallel is possible
```typescript
// BAD — total time = A + B + C
const user    = await getUser(id);
const orders  = await getOrders(id);
const balance = await getBalance(id);

// GOOD — total time = max(A, B, C)
const [user, orders, balance] = await Promise.all([
  getUser(id), getOrders(id), getBalance(id),
]);
```

### CPU-bound work on the main thread
```typescript
// BAD — heavy computation blocks all in-flight requests
app.post('/report', (req, res) => {
  const result = generateHeavyReport(req.body); // 500ms of CPU
  res.json(result);
});

// GOOD — offload to a worker thread
import { Worker } from 'worker_threads';
app.post('/report', (req, res) => {
  const worker = new Worker('./report-worker.js', { workerData: req.body });
  worker.once('message', (result) => res.json(result));
  worker.once('error', (err) => res.status(500).json({ error: err.message }));
});
```

### Yielding in long synchronous loops
```typescript
// BAD — iterating 100k items synchronously starves the event loop
for (const item of hugeArray) process(item);

// GOOD — yield between batches with setImmediate
async function processBatched(items: unknown[]) {
  for (let i = 0; i < items.length; i++) {
    process(items[i]);
    if (i % 1000 === 0) await new Promise(resolve => setImmediate(resolve));
  }
}
```

---

## Performance Diagnostics

### Measure event loop lag (add to any long-running service)
```typescript
let lastTick = Date.now();
setInterval(() => {
  const lag = Date.now() - lastTick - 1000; // expected 1000ms
  if (lag > 100) logger.warn({ lag }, 'Event loop lag detected');
  lastTick = Date.now();
}, 1000).unref(); // .unref() so this doesn't prevent process exit
```

### Track heap growth over time
```typescript
setInterval(() => {
  const { heapUsed, heapTotal, rss } = process.memoryUsage();
  logger.info({
    heapUsedMB: Math.round(heapUsed / 1024 / 1024),
    heapTotalMB: Math.round(heapTotal / 1024 / 1024),
    rssMB: Math.round(rss / 1024 / 1024),
  }, 'memory');
}, 30_000).unref();
```
A steadily climbing `heapUsed` that never drops after GC = leak.

### Heap snapshot workflow (--inspect)
```bash
# 1. Start with inspector
node --inspect dist/main.js

# 2. Open chrome://inspect in Chrome
# 3. Memory tab → Take heap snapshot (before)
# 4. Reproduce the leak (run load, make requests)
# 5. Take heap snapshot (after)
# 6. Switch to "Comparison" view — objects with high "# Delta" are the leak
```

### Flamegraph for CPU profiling (0x)
```bash
npx 0x -- node dist/main.js
# Run your load test, then Ctrl+C
# 0x opens a flamegraph in the browser
# Wide flat bars at the top = functions spending the most CPU time
```

### clinic.js — all-in-one diagnostics
```bash
npm i -g clinic
clinic doctor -- node dist/main.js   # detects event loop lag, I/O, memory
clinic flame  -- node dist/main.js   # flamegraph (CPU)
clinic bubbleprof -- node dist/main.js  # async operation profiling
```

### What to look for in code review (no runtime needed)
| Signal in code | Likely issue |
|---|---|
| `emitter.on(...)` inside a function called per-request | Listener leak |
| `new Map()` / `new Set()` at module scope, never pruned | Unbounded cache |
| `setInterval` result not stored | Timer leak |
| `fs.*Sync`, `crypto.*Sync` in route handler | Event loop block |
| `(a+)+`, `(.*)+`, nested quantifiers in regex | ReDoS risk |
| `await` calls in sequence that don't depend on each other | Avoidable latency |
| `scope: Scope.REQUEST` on a high-traffic service | Heap churn |
| No `enableShutdownHooks()` or `onModuleDestroy` | Connection leak on restart |
| Interceptor calling `JSON.stringify(response)` for logging | Large payload block |
| `JSON.parse` / `JSON.stringify` with no size guard | Event loop block on large input |
