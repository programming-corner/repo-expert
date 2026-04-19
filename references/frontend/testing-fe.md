# Frontend Reference: Testing

Covers: Vitest · React Testing Library · Playwright · Cypress · Testing Philosophy

---

## Testing Philosophy for Frontend

**Test behavior, not implementation.**
Users don't care about state variables or internal methods — they care about what they see and can do.

```
Avoid: expect(component.state.isLoading).toBe(true)
Prefer: expect(screen.getByRole('status')).toHaveTextContent('Loading...')
```

**Test pyramid for frontend:**
```
         [E2E / Playwright]        ← few, slow, high confidence
        [Integration / RTL]        ← most tests live here
       [Unit / pure functions]      ← utilities, formatters, reducers
```

---

## Vitest — unit and integration tests

### Setup

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
      exclude: ['**/*.stories.*', '**/index.ts'],
    },
  },
});

// src/test/setup.ts
import '@testing-library/jest-dom';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';
afterEach(cleanup);
```

### Testing pure functions — simple and fast

```typescript
import { describe, it, expect } from 'vitest';
import { formatPrice, calculateSubtotal } from '@/lib/pricing';

describe('formatPrice', () => {
  it('formats integers without decimals', () => {
    expect(formatPrice(1000)).toBe('$10.00');
  });

  it('rounds to 2 decimal places', () => {
    expect(formatPrice(999)).toBe('$9.99');
  });

  it('handles zero', () => {
    expect(formatPrice(0)).toBe('$0.00');
  });
});
```

### Mocking with Vitest

```typescript
import { vi, expect } from 'vitest';

// Mock a module
vi.mock('@/lib/orderApi', () => ({
  getOrder: vi.fn(),
}));

// Mock implementation per test
import { getOrder } from '@/lib/orderApi';
vi.mocked(getOrder).mockResolvedValue({ id: '1', status: 'CONFIRMED' });

// Spy on a method
const spy = vi.spyOn(orderService, 'confirm');
spy.mockResolvedValueOnce({ success: true });

// Restore mocks between tests
afterEach(() => vi.clearAllMocks());
```

---

## React Testing Library (RTL)

### Queries — priority order (use top ones first)

1. `getByRole` — semantic query, mirrors how screen readers see the page
2. `getByLabelText` — for form inputs
3. `getByPlaceholderText` — fallback for inputs without labels
4. `getByText` — for static text content
5. `getByTestId` — last resort only (add `data-testid` sparingly)

```typescript
// Prefer role queries
screen.getByRole('button', { name: /confirm order/i })
screen.getByRole('textbox', { name: /email address/i })
screen.getByRole('heading', { name: /order summary/i })
screen.getByRole('status') // for loading/error states
```

### Component integration test — the right structure

```tsx
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { vi } from 'vitest';
import { OrderConfirmation } from './OrderConfirmation';
import * as orderApi from '@/lib/orderApi';

vi.mock('@/lib/orderApi');

function renderWithProviders(ui: React.ReactElement) {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      {ui}
    </QueryClientProvider>
  );
}

describe('OrderConfirmation', () => {
  const user = userEvent.setup();

  it('shows order details after loading', async () => {
    vi.mocked(orderApi.getOrder).mockResolvedValue({
      id: 'order-1',
      status: 'PENDING',
      total: 4999,
    });

    renderWithProviders(<OrderConfirmation orderId="order-1" />);

    // Loading state
    expect(screen.getByRole('status')).toBeInTheDocument();

    // Loaded state
    await waitFor(() => {
      expect(screen.getByText('$49.99')).toBeInTheDocument();
    });
  });

  it('confirms the order when button is clicked', async () => {
    vi.mocked(orderApi.confirmOrder).mockResolvedValue({ success: true });

    renderWithProviders(<OrderConfirmation orderId="order-1" />);
    await waitFor(() => screen.getByRole('button', { name: /confirm/i }));

    await user.click(screen.getByRole('button', { name: /confirm/i }));

    await waitFor(() => {
      expect(screen.getByText(/order confirmed/i)).toBeInTheDocument();
    });
    expect(orderApi.confirmOrder).toHaveBeenCalledWith('order-1');
  });

  it('shows error when confirmation fails', async () => {
    vi.mocked(orderApi.confirmOrder).mockRejectedValue(new Error('Payment failed'));

    renderWithProviders(<OrderConfirmation orderId="order-1" />);
    await waitFor(() => screen.getByRole('button', { name: /confirm/i }));

    await user.click(screen.getByRole('button', { name: /confirm/i }));

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('Payment failed');
    });
  });
});
```

### Testing custom hooks

```typescript
import { renderHook, waitFor } from '@testing-library/react';
import { useOrder } from './useOrder';

it('fetches and returns order data', async () => {
  vi.mocked(orderApi.getOrder).mockResolvedValue({ id: '1', status: 'CONFIRMED' });

  const { result } = renderHook(() => useOrder('1'), { wrapper: QueryWrapper });

  expect(result.current.loading).toBe(true);

  await waitFor(() => {
    expect(result.current.loading).toBe(false);
    expect(result.current.order?.status).toBe('CONFIRMED');
  });
});
```

---

## Playwright — end-to-end tests

### Configuration

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'Mobile Chrome', use: { ...devices['Pixel 5'] } },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
});
```

### Page Object Model — organise complex E2E tests

```typescript
// e2e/pages/checkout.page.ts
export class CheckoutPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/checkout');
  }

  async fillShipping(data: { name: string; address: string }) {
    await this.page.getByLabel('Full name').fill(data.name);
    await this.page.getByLabel('Address').fill(data.address);
  }

  async confirmOrder() {
    await this.page.getByRole('button', { name: 'Place order' }).click();
    await this.page.waitForURL('/order/confirmation/**');
  }

  async getConfirmationNumber() {
    return this.page.getByTestId('confirmation-number').textContent();
  }
}

// e2e/checkout.spec.ts
test('complete checkout flow', async ({ page }) => {
  const checkout = new CheckoutPage(page);
  await checkout.goto();
  await checkout.fillShipping({ name: 'John Doe', address: '123 Main St' });
  await checkout.confirmOrder();
  expect(await checkout.getConfirmationNumber()).toMatch(/ORD-\d+/);
});
```

### API mocking in Playwright (for stable E2E tests)

```typescript
test('shows error when payment fails', async ({ page }) => {
  // Mock the API before navigating
  await page.route('**/api/orders/*/confirm', route => {
    route.fulfill({
      status: 402,
      body: JSON.stringify({ error: 'Payment declined' }),
    });
  });

  await page.goto('/checkout');
  await page.getByRole('button', { name: 'Place order' }).click();

  await expect(page.getByRole('alert')).toContainText('Payment declined');
});
```

---

## Testing Checklist

### For every new component
- [ ] Renders without crashing (smoke test)
- [ ] Happy path — renders correct content
- [ ] Loading state shown while fetching
- [ ] Error state shown when request fails
- [ ] User interactions trigger correct behavior
- [ ] Accessible by keyboard (Tab, Enter, Escape)

### For every custom hook
- [ ] Returns correct initial state
- [ ] Updates state correctly after async operation
- [ ] Handles errors gracefully
- [ ] Cleans up on unmount (no state updates after unmount)

### For critical user flows (E2E)
- [ ] Happy path works end-to-end
- [ ] Form validation prevents invalid submissions
- [ ] Works on mobile viewport
- [ ] Works without JavaScript (if SSR)
