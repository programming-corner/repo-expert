# Ruby (Rails) & PHP (Laravel) Reference

Load this file when the repo uses Ruby on Rails or PHP with Laravel.

---

## Ruby on Rails

### Architecture conventions
- **Fat models, thin controllers** is the Rails default — but push beyond-CRUD logic into service objects (`app/services/`)
- **Concerns** for shared model/controller behavior — use sparingly; prefer explicit composition
- **Form objects** for complex multi-model forms
- **Query objects** for complex ActiveRecord scopes

### ActiveRecord patterns

```ruby
# N+1 prevention — always eager load associations
# WRONG
orders = Order.all
orders.each { |o| puts o.user.email }   # N+1

# CORRECT
orders = Order.includes(:user).all
orders.each { |o| puts o.user.email }   # single query

# Batch processing large datasets
Order.where(status: :pending).find_each(batch_size: 500) do |order|
  OrderProcessor.new(order).call
end
```

### Transaction pattern
```ruby
ActiveRecord::Base.transaction do
  order.update!(status: :confirmed)
  payment.create!(order: order, amount: order.total)
  NotificationJob.perform_later(order.id)  # runs after commit
end
```

### Background jobs (Sidekiq)
```ruby
class NotificationJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 3, backtrace: true

  def perform(order_id)
    order = Order.find(order_id)   # re-fetch — don't pass AR objects
    NotificationService.send(order)
  end
end
```

### Code quality checklist
- [ ] `rubocop` passes
- [ ] `brakeman` security scan passes (SQL injection, XSS, mass assignment)
- [ ] No `N+1` in `rails_best_practices` or Bullet gem output
- [ ] `bundle audit` clean (CVEs)
- [ ] `strong_parameters` on every controller action

---

## PHP / Laravel

### Architecture conventions
- **Thin controllers, fat services**: controllers should only validate input, call a service, return a response
- **Form Requests** for validation — never validate in controllers directly
- **Service Provider** for binding interfaces to implementations
- **Repository pattern** optional but useful for complex query logic

### Eloquent patterns

```php
// N+1 prevention — eager load
// WRONG
$orders = Order::all();
foreach ($orders as $order) {
    echo $order->user->email;   // N+1
}

// CORRECT
$orders = Order::with('user')->get();

// Lazy loading in chunks
Order::where('status', 'pending')
    ->chunkById(500, function ($orders) {
        foreach ($orders as $order) {
            ProcessOrderJob::dispatch($order->id);
        }
    });
```

### Transaction pattern
```php
DB::transaction(function () use ($order) {
    $order->update(['status' => 'confirmed']);
    Payment::create(['order_id' => $order->id, 'amount' => $order->total]);
});
```

### Queue / Jobs (Laravel Queues)
```php
class ProcessOrderJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries    = 3;
    public int $backoff  = 60;    // seconds between retries

    public function __construct(private readonly string $orderId) {}

    public function handle(OrderService $service): void
    {
        $order = Order::findOrFail($this->orderId);  // re-fetch
        $service->process($order);
    }
}
```

### Code quality checklist
- [ ] `phpstan` at level 6+ passes
- [ ] `php-cs-fixer` applied
- [ ] `composer audit` clean (CVEs in deps)
- [ ] All routes use Form Requests for validation
- [ ] No raw `DB::statement()` with user input — use bindings
- [ ] `.env` not committed; `config/` uses `env()` helper

### Security checklist
- [ ] CSRF protection enabled (default in Laravel)
- [ ] Mass assignment protection: `$fillable` or `$guarded` on all models
- [ ] No `{!! !!}` (unescaped) Blade output for user data
- [ ] Passwords hashed with `Hash::make()` (bcrypt)
- [ ] `php artisan key:generate` run — `APP_KEY` set in production
