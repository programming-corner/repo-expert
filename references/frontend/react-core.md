# Frontend Reference: React & Next.js

Covers: React patterns · Next.js App Router · State Management · Performance · SSR/CSR · Accessibility

---

## React Patterns

### Component design — single responsibility

```tsx
// BAD — component doing too much
function OrderPage({ orderId }: { orderId: string }) {
  const [order, setOrder] = useState(null);
  const [loading, setLoading] = useState(true);
  // 200 lines of fetching, business logic, and rendering...
}

// GOOD — split by concern
function OrderPage({ orderId }: { orderId: string }) {
  const { order, loading, error } = useOrder(orderId);  // data fetching
  if (loading) return <OrderSkeleton />;
  if (error)   return <ErrorBoundary error={error} />;
  return <OrderView order={order} />;                   // pure rendering
}
```

### Custom hooks — the right extraction point

Extract a custom hook when:
- Data fetching logic is reused across 2+ components
- A component has 3+ `useState` / `useEffect` hooks
- Side effects need lifecycle management

```typescript
function useOrder(orderId: string) {
  const [state, setState] = useState<{
    order: Order | null;
    loading: boolean;
    error: Error | null;
  }>({ order: null, loading: true, error: null });

  useEffect(() => {
    let cancelled = false; // prevent state update on unmounted component
    orderApi.getById(orderId)
      .then(order => !cancelled && setState({ order, loading: false, error: null }))
      .catch(error => !cancelled && setState({ order: null, loading: false, error }));
    return () => { cancelled = true; };
  }, [orderId]);

  return state;
}
```

### State management — choose the right tool

| Need | Tool |
|---|---|
| Local UI state (modal open, form values) | `useState` |
| Shared UI state within a component tree | `useContext` + `useReducer` |
| Server state (fetching, caching, sync) | TanStack Query (React Query) |
| Complex global client state | Zustand or Redux Toolkit |
| Form state | React Hook Form |

**Never use global state for server data** — use TanStack Query instead.

### TanStack Query — the right patterns

```typescript
// Query with caching
const { data: order, isLoading, error } = useQuery({
  queryKey: ['order', orderId],
  queryFn: () => orderApi.getById(orderId),
  staleTime: 30_000,       // treat as fresh for 30s
  gcTime: 5 * 60_000,      // keep in cache for 5min after unmount
});

// Mutation with optimistic update
const { mutate: confirmOrder } = useMutation({
  mutationFn: (orderId: string) => orderApi.confirm(orderId),
  onMutate: async (orderId) => {
    await queryClient.cancelQueries({ queryKey: ['order', orderId] });
    const previous = queryClient.getQueryData(['order', orderId]);
    queryClient.setQueryData(['order', orderId], old => ({
      ...old, status: 'CONFIRMED'  // optimistic update
    }));
    return { previous };
  },
  onError: (err, orderId, ctx) => {
    queryClient.setQueryData(['order', orderId], ctx.previous); // rollback
  },
  onSettled: (_, __, orderId) => {
    queryClient.invalidateQueries({ queryKey: ['order', orderId] }); // refetch
  },
});
```

### Performance — avoiding unnecessary re-renders

```tsx
// Memoize expensive child components
const OrderItem = React.memo(({ item }: { item: OrderItem }) => {
  return <div>{item.name} × {item.quantity}</div>;
});

// Stable callback references
const handleConfirm = useCallback(() => {
  confirmOrder(orderId);
}, [orderId]); // recreates only when orderId changes

// Expensive computations
const subtotal = useMemo(
  () => items.reduce((sum, item) => sum + item.price * item.quantity, 0),
  [items]
);

// When NOT to memoize: simple components, trivial computations, rarely updated data
// Over-memoization adds complexity with no benefit
```

### Context — avoid prop drilling, avoid over-use

```tsx
// Good use: auth, theme, feature flags — truly global, rarely changing
const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  // ...
  return <AuthContext.Provider value={{ user, login, logout }}>{children}</AuthContext.Provider>;
}

// Bad use: server data (use TanStack Query), form state (use React Hook Form)
```

---

## Next.js App Router

### Server vs Client components — the decision

```
Is this component interactive? (onClick, onChange, useState, useEffect)
  Yes → Client Component ('use client')
  No  →
    Does it fetch data?
      Yes → Server Component (default — no directive needed)
      No  → Server Component (static, renders once)
```

**Push 'use client' as far down the tree as possible.**
The page is a Server Component. Only the interactive leaf nodes are Client Components.

### Data fetching patterns (App Router)

```tsx
// Server Component — async/await directly, no useEffect needed
export default async function OrderPage({ params }: { params: { id: string } }) {
  const order = await orderApi.getById(params.id); // runs on server
  return <OrderView order={order} />;
}

// With caching control
const order = await fetch(`/api/orders/${id}`, {
  next: { revalidate: 60 }   // ISR — revalidate every 60s
  // or: cache: 'no-store'   // always fresh (SSR)
  // or: cache: 'force-cache' // cache forever (SSG)
});

// Parallel fetching — don't await sequentially
const [order, user] = await Promise.all([
  orderApi.getById(id),
  userApi.getById(userId),
]);
```

### Route handlers (API routes in App Router)

```typescript
// app/api/orders/[id]/route.ts
export async function GET(
  request: Request,
  { params }: { params: { id: string } }
) {
  const order = await orderService.findById(params.id);
  if (!order) return NextResponse.json({ error: 'Not found' }, { status: 404 });
  return NextResponse.json({ data: order });
}

export async function PATCH(
  request: Request,
  { params }: { params: { id: string } }
) {
  const body = await request.json();
  const validated = UpdateOrderSchema.parse(body); // always validate
  const order = await orderService.update(params.id, validated);
  return NextResponse.json({ data: order });
}
```

### Middleware — auth guards, redirects

```typescript
// middleware.ts (runs on edge, before every request)
export function middleware(request: NextRequest) {
  const token = request.cookies.get('auth-token');

  if (!token && request.nextUrl.pathname.startsWith('/dashboard')) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*', '/api/orders/:path*'],
};
```

### Loading and error states (built-in Next.js)

```
app/
  orders/
    [id]/
      page.tsx        ← the actual page
      loading.tsx     ← shown while page.tsx is loading (Suspense boundary)
      error.tsx       ← shown when page.tsx throws ('use client' required)
      not-found.tsx   ← shown when notFound() is called in page.tsx
```

---

## Accessibility (always required, not optional)

### Semantic HTML first

```tsx
// BAD
<div onClick={handleSubmit}>Submit Order</div>

// GOOD
<button type="submit" onClick={handleSubmit}>Submit Order</button>
// button is keyboard focusable, has implicit role, fires on Enter/Space
```

### ARIA — only when HTML semantics aren't enough

```tsx
// Loading state
<button aria-busy={isLoading} disabled={isLoading}>
  {isLoading ? 'Processing...' : 'Confirm Order'}
</button>

// Dynamic regions
<div role="status" aria-live="polite">
  {successMessage}
</div>

// Icon-only buttons must have a label
<button aria-label="Close modal">
  <XIcon aria-hidden="true" />
</button>
```

### Keyboard navigation

- All interactive elements must be reachable by Tab
- Custom dropdowns, modals, tooltips must trap focus when open
- `Escape` must close modals and dropdowns
- Focus must return to the trigger element after a modal closes

---

## Performance

### Bundle size — always check

```bash
# Next.js bundle analyzer
ANALYZE=true next build

# What to watch for:
# - Large libraries (moment.js → use date-fns or dayjs)
# - Importing full lodash (import { debounce } from 'lodash' → import debounce from 'lodash/debounce')
# - Unintentional server-side code in client bundles
```

### Image optimization

```tsx
// Always use next/image — handles lazy loading, sizing, modern formats
import Image from 'next/image';

<Image
  src="/hero.jpg"
  alt="Hero image"
  width={1200}
  height={600}
  priority      // add for above-the-fold images only
/>
```

### Code splitting

```tsx
// Dynamic import for heavy components not needed on initial load
const HeavyChart = dynamic(() => import('@/components/HeavyChart'), {
  loading: () => <ChartSkeleton />,
  ssr: false,   // for browser-only libraries
});
```
