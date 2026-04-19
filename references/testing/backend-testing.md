# Backend Reference: Testing

Covers: Jest · Supertest · Unit · Integration · E2E · Contract Testing · Mocking strategies

---

## Testing Philosophy for Backend

**Test the behavior of the system, not the internal wiring.**

```
Unit:        Pure functions, business logic, transformations — isolated
Integration: Service + repository against a real test DB — no mocks for DB
E2E:         HTTP request to response — full stack, real DB, mocked external APIs
Contract:    API contract between services — prevent silent breaking changes
```

**Test pyramid:**
```
       [Contract / E2E]       ← few, slow, high confidence
      [Integration tests]     ← moderate — service + DB
     [Unit tests]             ← many, fast — pure logic only
```

---

## Jest Setup (NestJS)

```typescript
// jest.config.ts
import type { Config } from 'jest';

const config: Config = {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: 'src',
  testRegex: '.*\\.spec\\.ts$',
  transform: { '^.+\\.(t|j)s$': 'ts-jest' },
  collectCoverageFrom: ['**/*.(t|j)s'],
  coverageDirectory: '../coverage',
  testEnvironment: 'node',
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/$1',  // path aliases
  },
};

export default config;
```

---

## Unit Tests — pure business logic

Unit tests should test functions with no side effects. No DB, no HTTP, no queue.

```typescript
// orders.service.spec.ts — testing business logic in isolation
describe('OrderService.calculateTotal', () => {
  let service: OrderService;
  let orderRepo: jest.Mocked<IOrderRepository>;
  let paymentService: jest.Mocked<PaymentService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        OrderService,
        {
          provide: ORDER_REPOSITORY,
          useValue: {
            findById: jest.fn(),
            save: jest.fn(),
          },
        },
        {
          provide: PaymentService,
          useValue: { charge: jest.fn() },
        },
      ],
    }).compile();

    service = module.get(OrderService);
    orderRepo = module.get(ORDER_REPOSITORY);
    paymentService = module.get(PaymentService);
  });

  it('confirms a pending order', async () => {
    const order = buildOrder({ status: OrderStatus.PENDING });
    orderRepo.findById.mockResolvedValue(order);
    paymentService.charge.mockResolvedValue({ transactionId: 'tx-1' });

    const result = await service.confirm(order.id);

    expect(result.status).toBe(OrderStatus.CONFIRMED);
    expect(orderRepo.save).toHaveBeenCalledWith(
      expect.objectContaining({ status: OrderStatus.CONFIRMED })
    );
  });

  it('throws when order is already confirmed', async () => {
    orderRepo.findById.mockResolvedValue(
      buildOrder({ status: OrderStatus.CONFIRMED })
    );

    await expect(service.confirm('order-1'))
      .rejects.toThrow(ConflictException);
  });

  it('throws when order not found', async () => {
    orderRepo.findById.mockResolvedValue(null);

    await expect(service.confirm('order-1'))
      .rejects.toThrow(NotFoundException);
  });
});

// Test data builder — always use builders, never raw objects
function buildOrder(overrides: Partial<Order> = {}): Order {
  return {
    id: 'order-1',
    userId: 'user-1',
    status: OrderStatus.PENDING,
    total: 4999,
    items: [],
    createdAt: new Date(),
    ...overrides,
  };
}
```

---

## Integration Tests — service + real database

Test the full service layer against a real test database. No mocks for DB calls.

```typescript
// orders.integration.spec.ts
describe('OrderService (integration)', () => {
  let app: INestApplication;
  let service: OrderService;
  let dataSource: DataSource;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [
        TypeOrmModule.forRoot({
          type: 'postgres',
          url: process.env.TEST_DATABASE_URL,
          entities: [Order, User, OrderItem],
          synchronize: true,    // apply schema for tests — never in production
        }),
        OrdersModule,
      ],
    }).compile();

    app = module.createNestApplication();
    await app.init();

    service = module.get(OrderService);
    dataSource = module.get(DataSource);
  });

  afterEach(async () => {
    // Clean up after each test — order matters for FK constraints
    await dataSource.query('DELETE FROM order_items');
    await dataSource.query('DELETE FROM orders');
  });

  afterAll(async () => {
    await app.close();
  });

  it('creates and retrieves an order', async () => {
    const order = await service.create({ userId: 'user-1', items: [
      { productId: 'prod-1', quantity: 2, price: 999 },
    ]});

    const retrieved = await service.findById(order.id);
    expect(retrieved.items).toHaveLength(1);
    expect(retrieved.total).toBe(1998);
  });
});
```

---

## E2E Tests — HTTP endpoint to response

Test the full HTTP stack. Mock only external services (Stripe, SMS, etc.).

```typescript
// orders.e2e.spec.ts
describe('/orders (E2E)', () => {
  let app: INestApplication;
  let jwtToken: string;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    })
    .overrideProvider(StripeService)
    .useValue({ charge: jest.fn().mockResolvedValue({ id: 'ch_test' }) })
    .compile();

    app = module.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true }));
    await app.init();

    // Get auth token for tests
    const res = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email: 'test@example.com', password: 'password' });
    jwtToken = res.body.data.token;
  });

  afterAll(() => app.close());

  describe('POST /orders', () => {
    it('creates an order for authenticated user', async () => {
      const res = await request(app.getHttpServer())
        .post('/orders')
        .set('Authorization', `Bearer ${jwtToken}`)
        .send({
          items: [{ productId: 'prod-1', quantity: 1 }],
        })
        .expect(201);

      expect(res.body.data).toMatchObject({
        status: 'PENDING',
        items: expect.arrayContaining([
          expect.objectContaining({ productId: 'prod-1' }),
        ]),
      });
    });

    it('returns 401 without auth token', async () => {
      await request(app.getHttpServer())
        .post('/orders')
        .send({ items: [] })
        .expect(401);
    });

    it('returns 400 with empty items array', async () => {
      const res = await request(app.getHttpServer())
        .post('/orders')
        .set('Authorization', `Bearer ${jwtToken}`)
        .send({ items: [] })
        .expect(400);

      expect(res.body.error).toMatch(/items/i);
    });
  });
});
```

---

## Queue Processor Tests

```typescript
describe('PaymentProcessor', () => {
  let processor: PaymentProcessor;
  let paymentService: jest.Mocked<PaymentService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        PaymentProcessor,
        { provide: PaymentService, useValue: { charge: jest.fn() } },
        { provide: OrderService, useValue: { findById: jest.fn(), updateStatus: jest.fn() } },
      ],
    }).compile();

    processor = module.get(PaymentProcessor);
    paymentService = module.get(PaymentService);
  });

  function buildJob(data: object): Job {
    return {
      id: 'job-1',
      data,
      attemptsMade: 0,
      opts: { attempts: 3 },
      updateProgress: jest.fn(),
    } as unknown as Job;
  }

  it('processes payment and updates order status', async () => {
    const job = buildJob({ orderId: 'order-1' });
    paymentService.charge.mockResolvedValue({ transactionId: 'tx-1' });

    await processor.handle(job);

    expect(paymentService.charge).toHaveBeenCalledWith('order-1');
    expect(job.updateProgress).toHaveBeenCalledWith(100);
  });

  it('throws on payment failure — BullMQ handles retry', async () => {
    const job = buildJob({ orderId: 'order-1' });
    paymentService.charge.mockRejectedValue(new Error('Card declined'));

    await expect(processor.handle(job)).rejects.toThrow('Card declined');
    // BullMQ will retry automatically — we just let the error propagate
  });
});
```

---

## Test Scenarios Checklist

### For every new endpoint
- [ ] Happy path — correct input → correct response + status code
- [ ] Auth: unauthenticated → 401, unauthorized role → 403
- [ ] Validation: missing required field → 400 with field error
- [ ] Validation: invalid type → 400
- [ ] Not found: non-existent resource → 404
- [ ] Conflict: duplicate or invalid state transition → 409
- [ ] Idempotency: duplicate request → same result, no duplicate side effects

### For every queue processor
- [ ] Happy path — job completes, side effects triggered
- [ ] Throws on failure — BullMQ retries it
- [ ] Idempotent — processing same job twice has no bad effect
- [ ] Handles missing resource gracefully (order deleted between enqueue and process)

### For every service method
- [ ] Happy path
- [ ] Not found → NotFoundException
- [ ] Invalid state → ConflictException or BusinessException
- [ ] External service failure → correct error propagation
