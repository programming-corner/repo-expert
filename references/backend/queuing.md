# Backend Reference: Queuing & Messaging

Covers: BullMQ · Kafka · RabbitMQ · Google PubSub · AWS SQS · Job Design · Event-Driven Architecture

---

## Job Design Principles (apply to any queue system)

1. **Idempotency is non-negotiable** — jobs must be safe to run multiple times. Use a business-key-based `jobId` to prevent duplicates
2. **Keep jobs thin** — pass IDs and minimal context, not full objects. Objects change between enqueue and process
3. **Exponential backoff always** — never fixed-interval retries
4. **Dead Letter Queue** — failed-after-max-retries jobs must go somewhere inspectable
5. **Poison pill detection** — a job that always fails must not block the queue indefinitely

---

## BullMQ (Node.js native, Redis-backed)

### Queue configuration (NestJS)

```typescript
BullModule.registerQueue({
  name: QueueName.PAYMENTS,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 2_000 },
    removeOnComplete: { count: 1_000, age: 24 * 3600 },
    removeOnFail: false,        // keep failed jobs for inspection
    timeout: 30_000,            // 30s max — always set this
  },
})
```

### Job design — thin payload pattern

```typescript
// BAD — full object, stale by the time it's processed
await queue.add('process-payment', { order: fullOrderObject });

// GOOD — ID only, fetch fresh data in processor
await queue.add('process-payment', { orderId: order.id }, {
  jobId: `payment-${order.id}`,  // idempotency key — prevents duplicate jobs
});
```

### Processor pattern (NestJS)

```typescript
@Processor(QueueName.PAYMENTS)
export class PaymentProcessor {
  constructor(private readonly paymentService: PaymentService) {}

  @Process('process-payment')
  async handle(job: Job<{ orderId: string }>) {
    await job.updateProgress(0);
    const order = await this.orderService.findById(job.data.orderId);

    if (!order) {
      // Order deleted between enqueue and process — not an error, skip it
      return { skipped: true };
    }

    await job.updateProgress(50);
    const result = await this.paymentService.charge(order);
    await job.updateProgress(100);
    return result;
  }

  @OnQueueFailed()
  onFailed(job: Job, error: Error) {
    this.logger.error({ jobId: job.id, error }, 'Payment job failed');
    // Alert if max attempts reached
    if (job.attemptsMade >= job.opts.attempts) {
      this.alerting.notify(`Payment job ${job.id} exhausted retries`);
    }
  }
}
```

### Worker concurrency guidelines

| Job type | Concurrency |
|---|---|
| External API calls | 5 – 20 (respect their rate limits) |
| DB writes | 10 – 50 |
| File / image processing | 2 – 5 (CPU/memory bound) |
| Email / SMS / push | 20 – 100 |
| Heavy computation | 1 – 2 |

### BullMQ pitfalls

- **No `timeout`** → long-running jobs block workers indefinitely
- **No `jobId`** → duplicate jobs on network retries or re-enqueue bugs
- **Missing `await`** in processor → job marked complete before work finishes
- **Queue name as inline string** → use a `QueueName` enum/const always
- **Not calling `updateProgress`** → no visibility in dashboards (Bull Board, etc.)

---

## Kafka (high-throughput event streaming)

### When Kafka over BullMQ

Use Kafka when you need:
- Event replay / audit trail (consumers can rewind)
- Multiple independent consumers of the same event (fan-out without copying jobs)
- Very high throughput (millions of events/day)
- Ordered processing within a partition

Use BullMQ when you need:
- Job scheduling, delayed jobs, cron
- Job retry with exponential backoff out of the box
- Simple task queues for a single consumer

### Message design (Kafka)

```typescript
interface KafkaMessage<T> {
  eventType: string;     // 'order.confirmed'
  eventId: string;       // UUID — for deduplication
  occurredAt: string;    // ISO 8601
  schemaVersion: string; // '1.0' — for backwards compat
  payload: T;
}
```

### Consumer group patterns (NestJS + @nestjs/microservices)

```typescript
// Each consumer group gets all messages independently
// Scale consumers within a group = parallel processing of partitions

@MessagePattern('order.confirmed')
async handleOrderConfirmed(@Payload() message: KafkaMessage<OrderConfirmedPayload>) {
  // Always idempotent — Kafka delivers at-least-once
  const alreadyProcessed = await this.idempotency.check(message.eventId);
  if (alreadyProcessed) return;

  await this.notificationService.sendConfirmation(message.payload.orderId);
  await this.idempotency.mark(message.eventId);
}
```

### Kafka pitfalls

- **Not tracking consumer group offset** → messages lost or reprocessed on restart
- **Non-idempotent consumers** → at-least-once delivery means duplicate processing
- **Single partition for ordered data** → throughput bottleneck; partition by entity ID
- **Large messages** → Kafka default max is 1MB; use object storage + reference pattern for large payloads
- **Missing schema registry** → producers and consumers go out of sync silently

---

## RabbitMQ

### Exchange types — choose correctly

| Exchange | When to use |
|---|---|
| `direct` | Route to one specific queue by routing key |
| `fanout` | Broadcast to all bound queues (notifications) |
| `topic` | Pattern-matched routing (`order.*`, `*.failed`) |
| `headers` | Route by message headers (rare) |

### Dead letter exchange setup

```typescript
channel.assertQueue('payments', {
  durable: true,
  arguments: {
    'x-dead-letter-exchange': 'payments.dlx',
    'x-message-ttl': 30_000,    // 30s before moving to DLX
    'x-max-retries': 3,
  },
});
channel.assertExchange('payments.dlx', 'direct', { durable: true });
channel.assertQueue('payments.dead', { durable: true });
channel.bindQueue('payments.dead', 'payments.dlx', 'payments');
```

---

## Google PubSub

### Core concepts
- **Topic** → the channel (`order-events`, `payment-events`)
- **Subscription** → named consumer (one topic, many subscriptions = fan-out)
- **At-least-once delivery** → always design consumers to be idempotent

### Idempotency in PubSub consumers

```typescript
async processMessage(message: Message) {
  const { eventId } = JSON.parse(message.data.toString());

  // Check idempotency (Redis SET with TTL)
  const key = `pubsub:processed:${eventId}`;
  const alreadyProcessed = await redis.set(key, '1', 'NX', 'EX', 86_400);
  if (!alreadyProcessed) {
    message.ack();
    return;
  }

  try {
    await this.handleEvent(JSON.parse(message.data.toString()));
    message.ack();
  } catch (err) {
    message.nack(); // redelivers — do NOT ack on failure
  }
}
```

### PubSub pitfalls

- **Acking before processing** → message lost if processor crashes mid-flight
- **Large payloads** → 10MB limit; use GCS + PubSub reference pattern
- **No dead letter topic** → configure on subscription — undeliverable messages after N retries land there
- **No schema versioning** → add `schemaVersion` field to every message

---

## AWS SQS

### FIFO vs Standard

| | Standard | FIFO |
|---|---|---|
| Ordering | Best-effort | Strict per MessageGroupId |
| Throughput | Unlimited | 300 msg/s (3000 with batching) |
| Deduplication | No | Yes — 5min dedup window |
| Use for | High-volume async tasks | Ordered processing, payments |

### SQS visibility timeout — critical setting

```
visibilityTimeout must be > max processing time

If processing takes up to 60s, set visibilityTimeout to 90s minimum.
If a consumer dies mid-processing, the message reappears after timeout.
```

### Message batching for throughput

```typescript
// Send up to 10 messages per request
await sqs.sendMessageBatch({
  QueueUrl: process.env.QUEUE_URL,
  Entries: messages.map((msg, i) => ({
    Id: `msg-${i}`,
    MessageBody: JSON.stringify(msg),
    MessageGroupId: msg.orderId,      // FIFO only — groups ordered messages
  })),
});
```
