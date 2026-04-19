# Backend Reference: System Design

Covers: Architecture Patterns · Distributed Systems · API Design Decisions · Tech Debt · Observability

---

## Design Patterns — when to use each

### Repository Pattern
Abstracts data access. Service never knows if data comes from DB, cache, or API.

```typescript
interface IOrderRepository {
  findById(id: string): Promise<Order | null>;
  findByUserId(userId: string, pagination: Pagination): Promise<Order[]>;
  save(order: Order): Promise<void>;
  delete(id: string): Promise<void>;
}

// Service depends on interface, not concrete class
@Injectable()
export class OrderService {
  constructor(
    @Inject(ORDER_REPOSITORY) private readonly repo: IOrderRepository
  ) {}
}
```

Use when: you want to swap DB implementations, mock data access in tests, or cache transparently.
Don't use when: simple CRUD with no business logic — just use the ORM directly.

### CQRS (Command Query Responsibility Segregation)
Separate read and write models.

Use when:
- Read models need a different shape than write models
- Heavy read load needs separate optimization
- Audit trail or event sourcing is required

Don't use when:
- Simple CRUD — CQRS adds significant complexity without benefit for simple cases

### Outbox Pattern — reliable event publishing
Problem: DB write + queue publish in one operation. One can succeed while the other fails.

Solution:
```
1. Write business data + write event to outbox table in ONE transaction
2. Separate poller reads outbox → publishes to queue → marks as published
3. At-least-once delivery guaranteed — consumers must be idempotent
```

```sql
CREATE TABLE outbox_events (
  id UUID PRIMARY KEY,
  event_type VARCHAR NOT NULL,
  payload JSONB NOT NULL,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Saga Pattern — distributed transactions across services
When one operation spans multiple services (order + payment + inventory + notification):

**Choreography** (event-driven):
- Each service publishes events, next service listens
- Simpler, looser coupling
- Harder to visualize overall flow

**Orchestration** (central coordinator):
- A saga orchestrator drives each step
- Easier to debug and visualize
- Better for complex flows with many compensation steps

### Circuit Breaker — resilience for external calls
States: `CLOSED` (normal) → `OPEN` (failing, fast-fail) → `HALF-OPEN` (probing recovery)

Use for: every external service call — payment gateway, SMS provider, warehouse API, third-party APIs.

```typescript
import Opossum from 'opossum';

const breaker = new Opossum(stripeClient.charge, {
  timeout: 3_000,           // fail if takes > 3s
  errorThresholdPercentage: 50,  // open if 50% of calls fail
  resetTimeout: 30_000,     // try again after 30s
});

breaker.fallback(() => ({ status: 'PENDING', retryLater: true }));
```

---

## Distributed Systems Concepts

### Idempotency — the most important property in distributed systems

A request is idempotent if making it multiple times has the same effect as making it once.

**Implementation pattern:**
```typescript
// Client sends Idempotency-Key header
// Server stores result by key, returns stored result on duplicate

async function idempotentCreate(key: string, fn: () => Promise<Order>): Promise<Order> {
  const cached = await redis.get(`idempotency:${key}`);
  if (cached) return JSON.parse(cached);

  const result = await fn();
  await redis.set(`idempotency:${key}`, JSON.stringify(result), 'EX', 86_400);
  return result;
}
```

**Make these always idempotent:**
- Payment endpoints
- Order creation
- Job processors / queue consumers
- Webhook handlers

### Eventual consistency — designing for it

Accept that distributed systems are not always consistent. Design around it:
- Show optimistic UI updates, reconcile later
- Use saga compensations instead of distributed transactions
- Version your data (optimistic locking) to detect conflicts

```typescript
// Optimistic locking — prevents lost updates
@VersionColumn()
version: number;

// TypeORM will fail if version doesn't match
await repo.save({ ...order, status: 'CONFIRMED', version: order.version });
```

### CAP Theorem — practical implications

| System | Chooses | Implication |
|---|---|---|
| PostgreSQL | CP (consistency + partition tolerance) | May reject writes during network partition |
| MongoDB (default) | CP | Same |
| Cassandra | AP (availability + partition tolerance) | May return stale reads |
| Redis Cluster | AP | Possible data loss on partition |

For most web apps: use PostgreSQL as source of truth, tolerate eventual consistency in caches and queues.

---

## API Design Decisions

### REST vs GraphQL vs tRPC

| | REST | GraphQL | tRPC |
|---|---|---|---|
| Best for | Public APIs, mobile clients | Complex FE with many data shapes | Internal fullstack (Next.js + NestJS) |
| Overfetching | Common problem | Solved | Solved |
| Type safety | Manual (OpenAPI) | Codegen needed | Native end-to-end |
| Caching | Easy (HTTP cache) | Complex | Complex |
| Learning curve | Low | Medium | Low (TypeScript teams) |

### Webhook design (receiving external events)

```typescript
// 1. Always verify signature
const signature = req.headers['x-stripe-signature'];
stripe.webhooks.constructEvent(req.rawBody, signature, process.env.WEBHOOK_SECRET);

// 2. Respond fast — queue the heavy work
app.post('/webhooks/stripe', async (req, res) => {
  const event = verifySignature(req);
  await queue.add('process-webhook', { eventId: event.id, type: event.type });
  res.status(200).send('ok'); // always respond within 5s
});

// 3. Process idempotently in the queue
// eventId is your idempotency key
```

---

## Observability

### Structured logging — always JSON, always context

```typescript
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  base: { service: 'orders-api', env: process.env.NODE_ENV },
});

// Always include request context
logger.info({
  orderId,
  userId,
  action: 'order.confirmed',
  durationMs: Date.now() - startTime,
}, 'Order confirmed');

// Never log sensitive data
// Never: logger.info({ user }) — may include passwordHash, tokens
// Always: logger.info({ userId: user.id })
```

### Key metrics to expose (Prometheus / DataDog / CloudWatch)

```typescript
// Request rate, error rate, latency (RED metrics)
http_requests_total{method, path, status}
http_request_duration_seconds{method, path}

// Queue health
queue_jobs_waiting{queue}
queue_jobs_failed{queue}
queue_job_duration_seconds{queue, processor}

// Business metrics
orders_created_total
payments_processed_total{status}
```

### Distributed tracing (OpenTelemetry)

```typescript
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('orders-service');

async function confirmOrder(orderId: string) {
  return tracer.startActiveSpan('order.confirm', async (span) => {
    span.setAttribute('order.id', orderId);
    try {
      const result = await doConfirm(orderId);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (err) {
      span.recordException(err);
      span.setStatus({ code: SpanStatusCode.ERROR });
      throw err;
    } finally {
      span.end();
    }
  });
}
```

---

## Tech Debt Classification

### Intentional debt (documented shortcuts)
- "We'll add pagination later" — known, planned tradeoff
- "This query is slow but serves <100 users" — acceptable for now

Mark in code: `// TECH-DEBT: [reason] [ticket]`

### Accidental debt (rot)
- Outdated dependencies with known CVEs
- Missing tests on critical paths
- Duplicated logic across services
- Deprecated API usage

### Prioritization matrix

| Impact | Effort | Priority |
|---|---|---|
| High | Low | 🔴 Do now — easy win with high payoff |
| High | High | 🟡 Plan carefully — schedule a spike first |
| Low | Low | 🟢 Easy win — do in next slow sprint |
| Low | High | ⚪ Backlog indefinitely or accept it |

### Code smell checklist

- [ ] Functions longer than 30 lines → extract
- [ ] More than 3 levels of nesting → flatten with early returns
- [ ] Magic numbers → named constants
- [ ] `any` type in TypeScript → type it properly
- [ ] Missing error handling on async → add try/catch or `.catch()`
- [ ] `console.log` in production code → use structured logger
- [ ] Hardcoded URLs or credentials → move to config/env
- [ ] Commented-out code → delete it (git has history)
- [ ] Duplicate logic in 3+ places → extract to shared utility
- [ ] Cyclomatic complexity > 10 → refactor
