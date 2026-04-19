# Backend Reference: Databases

Covers: PostgreSQL · MySQL · MongoDB · Redis · Prisma · TypeORM · Indexing · Migrations

---

## PostgreSQL / MySQL

### Indexing strategy — ask these for every query

1. Columns in `WHERE` clause → composite index candidate
2. Columns in `ORDER BY` → include in index
3. Foreign keys → always index them
4. High cardinality (userId, orderId) → good index candidate
5. Low cardinality (status with 3 values) → partial index or skip

```sql
-- Composite index for a common query pattern
CREATE INDEX idx_orders_user_status
  ON orders (user_id, status)
  WHERE deleted_at IS NULL;   -- partial index excludes soft-deleted rows

-- PostgreSQL only — non-blocking on large tables
CREATE INDEX CONCURRENTLY idx_orders_created_at ON orders (created_at);
```

### Transaction isolation levels

| Level | Use for |
|---|---|
| `READ COMMITTED` | Most writes — good default |
| `REPEATABLE READ` | Financial calculations, inventory decrement |
| `SERIALIZABLE` | Critical sections — seat/slot reservation, unique constraints |

```typescript
// TypeORM transaction
await dataSource.transaction(async (em) => {
  const order = await em.findOneOrFail(Order, { where: { id } });
  order.status = OrderStatus.CONFIRMED;
  await em.save(order);
  await em.save(Payment, { orderId: id, amount: order.total });
});

// Prisma transaction
await prisma.$transaction(async (tx) => {
  const order = await tx.order.update({ where: { id }, data: { status: 'CONFIRMED' } });
  await tx.payment.create({ data: { orderId: id, amount: order.total } });
});
```

### Migration safety rules — zero-downtime deploys

1. **Never rename a column directly** → add new column, migrate data, remove old (3 separate deploys)
2. **Never add NOT NULL without a default** → breaks existing rows mid-deploy
3. **Never drop a column in the same deploy as removing the code** → remove code first, drop later
4. **Always `CREATE INDEX CONCURRENTLY`** (PostgreSQL) → avoids table lock on large tables
5. **Run migrations before deploy** → never after (code must tolerate both old and new schema)
6. **Backfill in batches** → `UPDATE ... WHERE id BETWEEN X AND Y LIMIT 1000` to avoid lock escalation

### N+1 detection and fixes

N+1 = a list query returns N rows, then N more queries run per row.

```typescript
// BAD — N+1
const orders = await orderRepo.find();
for (const order of orders) {
  order.user = await userRepo.findById(order.userId); // N queries
}

// TypeORM fix
const orders = await orderRepo.find({ relations: ['user'] });

// Prisma fix
const orders = await prisma.order.findMany({ include: { user: true } });

// Manual batch fix (when ORM join is impractical)
const userIds = orders.map(o => o.userId);
const users = await userRepo.findByIds(userIds);
const userMap = new Map(users.map(u => [u.id, u]));
orders.forEach(o => o.user = userMap.get(o.userId));
```

### Soft deletes — consistent pattern

```typescript
// Entity
@Column({ nullable: true })
deletedAt: Date | null;

// Always filter in queries
WHERE deleted_at IS NULL

// TypeORM built-in
@DeleteDateColumn()
deletedAt: Date;
// then use repo.softDelete(id) and repo.find() auto-filters
```

---

## MongoDB

### Schema design — embed vs reference

**Embed when:**
- Data is always read together (order + line items)
- Child documents have no independent lifecycle
- Document stays under 16MB

**Reference when:**
- Data is large or grows unboundedly (user → orders)
- Data is shared across multiple parent documents
- Child documents are queried independently

### Indexing in MongoDB

```javascript
// Compound index — order matters (equality first, then range, then sort)
db.orders.createIndex({ userId: 1, status: 1, createdAt: -1 });

// Partial index — only index active orders
db.orders.createIndex(
  { createdAt: 1 },
  { partialFilterExpression: { status: { $in: ['PENDING', 'CONFIRMED'] } } }
);

// Text index for search
db.products.createIndex({ name: 'text', description: 'text' });
```

### Aggregation pipeline — performance rules

1. Put `$match` and `$sort` as early as possible (use indexes)
2. Use `$project` early to reduce document size through the pipeline
3. `$lookup` (join) is expensive — denormalize frequently-joined data
4. Use `$facet` for multi-facet pagination (counts + results in one query)

---

## Redis

### Key naming convention — always enforce

```
{service}:{entity}:{id}:{field?}

orders:order:abc-123
users:session:tok-xyz
inventory:sku:SKU-456:stock
rate-limit:user:user-789:minute
```

### Caching strategy decision tree

```
Is data shared across multiple instances?
  Yes → Redis (not in-memory Map)
    Is data frequently read, rarely written?
      Yes → Cache-Aside with TTL
      No  → Write-through or skip cache
    Is brief staleness acceptable?
      Yes → TTL expiry
      No  → Explicit invalidation on every write
  No → In-memory (Map / LRU)
```

### TTL guidelines

| Data type | TTL |
|---|---|
| Session tokens | 24h – 7d |
| Rate limit counters | 1min – 1h |
| Computed aggregates | 5min – 1h |
| Hot entity cache | 30s – 5min |
| Idempotency keys | 24h |

### Cache-Aside pattern (Node.js)

```typescript
async function getOrder(id: string): Promise<Order> {
  const key = `orders:order:${id}`;
  const cached = await redis.get(key);
  if (cached) return JSON.parse(cached);

  const order = await orderRepo.findById(id);
  await redis.set(key, JSON.stringify(order), 'EX', 300); // 5min TTL
  return order;
}

// Invalidation on update
async function updateOrder(id: string, data: Partial<Order>) {
  await orderRepo.update(id, data);
  await redis.del(`orders:order:${id}`); // always invalidate, never update in place
}
```

### Redis pitfalls

- **Cache stampede** → use `SET NX EX` distributed lock or probabilistic early expiration
- **Missing `maxmemory-policy`** → always set `allkeys-lru` for pure cache use
- **TTL storms** → add jitter: `ttl + Math.floor(Math.random() * ttl * 0.1)`
- **Storing JS objects directly** → always `JSON.stringify` / `JSON.parse`
- **Forgetting expiry on idempotency keys** → always set TTL, never store indefinitely

### Distributed lock pattern

```typescript
const lock = await redis.set(
  `lock:order:${orderId}`,
  requestId,
  'NX',   // only set if not exists
  'EX',   // with expiry
  30      // 30 seconds max lock duration
);

if (!lock) throw new ConflictException('Order already being processed');

try {
  // critical section
} finally {
  // release only if we own the lock
  const script = `
    if redis.call("get", KEYS[1]) == ARGV[1] then
      return redis.call("del", KEYS[1])
    else return 0 end`;
  await redis.eval(script, 1, `lock:order:${orderId}`, requestId);
}
```

---

## Prisma patterns

### Always use `select` / `include` explicitly — never return full models to the API

```typescript
const order = await prisma.order.findUnique({
  where: { id },
  select: {
    id: true,
    status: true,
    total: true,
    user: { select: { id: true, email: true } }, // never expose passwordHash etc.
    items: { select: { productId: true, quantity: true, price: true } },
  },
});
```

### Pagination with cursor

```typescript
const orders = await prisma.order.findMany({
  where: { userId },
  orderBy: { createdAt: 'desc' },
  take: limit + 1,        // fetch one extra to detect hasNextPage
  cursor: cursor ? { id: cursor } : undefined,
  skip: cursor ? 1 : 0,   // skip the cursor item itself
});

const hasNextPage = orders.length > limit;
const items = hasNextPage ? orders.slice(0, -1) : orders;
const nextCursor = hasNextPage ? items[items.length - 1].id : null;
```
