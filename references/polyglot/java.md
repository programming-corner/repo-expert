# Java / Kotlin Backend Reference

Load this file when the repo uses Java or Kotlin with Spring Boot, Maven, or Gradle.

---

## Spring Boot Architecture

```
src/main/java/com/example/
  controller/     ← @RestController — HTTP surface only
  service/        ← @Service — business logic
  repository/     ← @Repository — data access (Spring Data JPA)
  domain/         ← entities, value objects
  dto/            ← request/response shapes (separate from domain)
  config/         ← @Configuration beans
  exception/      ← @ControllerAdvice, custom exceptions
```

---

## Dependency Injection

```java
// Constructor injection (preferred over @Autowired on fields)
@Service
public class OrderService {
    private final OrderRepository orderRepository;
    private final PaymentService paymentService;

    public OrderService(OrderRepository orderRepository, PaymentService paymentService) {
        this.orderRepository = orderRepository;
        this.paymentService  = paymentService;
    }
}
```

- Field injection (`@Autowired` on fields) makes testing harder — avoid it
- `@Lazy` on circular dependencies is a design smell — fix the coupling instead

---

## JPA / Hibernate Patterns

### N+1 prevention
```java
// WRONG — triggers N+1 for each order's items
List<Order> orders = orderRepo.findAll();
orders.forEach(o -> o.getItems().size()); // lazy load per order

// CORRECT — single query with JOIN FETCH
@Query("SELECT o FROM Order o JOIN FETCH o.items WHERE o.status = :status")
List<Order> findWithItemsByStatus(@Param("status") OrderStatus status);
```

### Transaction boundaries
```java
@Transactional                          // read-write transaction
public Order confirmOrder(String id) { ... }

@Transactional(readOnly = true)        // read-only — DB can optimize
public List<Order> findPending() { ... }

@Transactional(propagation = Propagation.REQUIRES_NEW)  // separate transaction
public void auditLog(String action) { ... }
```

### Common JPA pitfalls
- **`@OneToMany` without `fetch = FetchType.LAZY`**: eager loading can pull entire tables
- **Bidirectional relationships without `mappedBy`**: causes duplicate joins
- **Missing `@Column(nullable = false)` on required fields**: DB constraint not enforced by schema
- **Open Session in View pattern**: loads data in the view layer — breaks at scale

---

## Spring Security

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(csrf -> csrf.disable())            // stateless API
            .sessionManagement(s -> s.sessionCreationPolicy(STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/public/**").permitAll()
                .anyRequest().authenticated()
            )
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            .build();
    }
}
```

---

## Async / Reactive

```java
// @Async with CompletableFuture
@Async("taskExecutor")
public CompletableFuture<Order> processOrderAsync(String orderId) {
    return CompletableFuture.completedFuture(process(orderId));
}

// Spring WebFlux (reactive)
public Mono<Order> getOrder(String id) {
    return orderRepository.findById(id)
        .switchIfEmpty(Mono.error(new NotFoundException(id)));
}
```

---

## Code Quality Checklist
- [ ] `mvn verify` / `./gradlew check` passes
- [ ] SpotBugs / FindBugs clean
- [ ] Checkstyle or PMD rules pass
- [ ] No `System.out.println` in production code — use SLF4J logger
- [ ] `Optional` returned instead of `null` from service/repo layer
- [ ] Immutable value objects where possible (`final` fields, no setters)

---

## Security Checklist
- [ ] OWASP Dependency Check passes (`mvn dependency-check:check`)
- [ ] No hardcoded secrets — use `@Value` from env or Spring Cloud Config
- [ ] SQL via JPA/JPQL — never concatenated strings
- [ ] Password hashing with BCrypt (`BCryptPasswordEncoder`)
- [ ] HTTPS enforced; HTTP headers: `X-Content-Type-Options`, `X-Frame-Options`
