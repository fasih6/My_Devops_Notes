# Reliability Patterns — Building Systems That Survive Failure

## Why Reliability Patterns Matter

No system is infinitely reliable. Hardware fails. Networks partition. Dependencies go down. The question is not whether your system will experience failures — it's whether those failures cascade into user-facing incidents or get absorbed gracefully.

Reliability patterns are **design choices that make systems resilient in the face of failure.** They don't prevent failure; they contain it.

---

## Pattern 1: Circuit Breaker

### The Problem

When Service A calls Service B, and Service B is slow or failing:
- Service A waits for timeouts repeatedly
- Threads pile up waiting for B to respond
- Service A's resources exhaust
- Service A fails — even though B was the problem

This is called **cascading failure** — one failing service brings down its upstream callers.

### The Solution

A circuit breaker sits between A and B. It tracks the success/failure rate of calls to B:

```
CLOSED state (normal):
  Requests pass through to Service B
  Circuit tracks failure rate

  If failure rate > threshold → trip to OPEN

OPEN state (B is failing):
  Requests immediately return error (fail fast)
  No traffic sent to Service B
  Service B gets time to recover

  After timeout → move to HALF-OPEN

HALF-OPEN state (testing recovery):
  Allow a small number of requests through
  If they succeed → close circuit (B recovered)
  If they fail → reopen circuit (B still failing)
```

### Circuit Breaker States Diagram

```
         failures > threshold
CLOSED ──────────────────────→ OPEN
  ↑                               │
  │ requests succeed              │ timeout expires
  │                               ↓
  └──────────────────────── HALF-OPEN
         (test requests)
```

### Key Configuration

```
Failure threshold:   50% failure rate over last 10 requests
Timeout:             30 seconds in OPEN state before trying HALF-OPEN
Half-open requests:  3 test requests before deciding
```

### Real-world use

Circuit breakers are implemented in:
- **Resilience4j** (Java)
- **Polly** (.NET)
- **Hystrix** (Java, now maintenance mode)
- **Istio / Envoy** (service mesh — circuit breaking at infrastructure level)
- **Azure API Management** (built-in circuit breaker)

---

## Pattern 2: Retry with Exponential Backoff and Jitter

### The Problem

When a call fails, the naive approach is to retry immediately. If 1,000 clients all retry at the same time, they create a thundering herd that overwhelms the recovering service.

### The Solution

**Exponential backoff:** each retry waits longer than the last.

```
Attempt 1: fail → wait 1 second
Attempt 2: fail → wait 2 seconds
Attempt 3: fail → wait 4 seconds
Attempt 4: fail → wait 8 seconds
Attempt 5: fail → give up (max retries exceeded)
```

**Jitter:** add randomness to prevent synchronized retries across clients.

```
Without jitter (thundering herd):
  1000 clients all retry at t=1s, t=2s, t=4s — synchronized spikes

With jitter:
  Client A retries at t=0.7s, t=1.9s, t=3.4s
  Client B retries at t=1.2s, t=2.6s, t=5.1s
  Spread evenly — recovering service isn't overwhelmed
```

**Formula:**
```
wait = min(cap, base × 2^attempt) + random(0, base)

Example with base=1s, cap=30s:
  Attempt 1: min(30, 1×2^1) + random(0,1) = 2 + 0.6 = 2.6s
  Attempt 2: min(30, 1×2^2) + random(0,1) = 4 + 0.3 = 4.3s
  Attempt 3: min(30, 1×2^3) + random(0,1) = 8 + 0.8 = 8.8s
```

### What to retry and what not to

```
RETRY these:
  - Network timeouts
  - HTTP 429 (rate limited) — with backoff
  - HTTP 503 (service unavailable) — temporary
  - HTTP 500 (server error) — if idempotent

DO NOT retry these:
  - HTTP 400 (bad request) — retrying won't help
  - HTTP 401/403 (auth error) — retrying won't help
  - HTTP 404 (not found) — retrying won't help
  - Non-idempotent operations (payment processing, order creation)
    unless you have idempotency keys
```

---

## Pattern 3: Timeout

### The Problem

Without timeouts, a slow dependency can hold a thread indefinitely. Enough slow dependencies = thread pool exhaustion = your service is down.

### The Solution

Set explicit timeouts at every network boundary:

```
Connection timeout:  Time allowed to establish the connection
                     (e.g. 1-2 seconds)

Read timeout:        Time allowed to read the response after connection
                     (e.g. 5-30 seconds depending on expected response time)

Overall timeout:     Total budget for the entire operation
                     (prevents retry loops from running too long)
```

### Timeout budgeting

In a chain of services: A → B → C → D

Each service's timeout must be shorter than the calling service's timeout:

```
User request: 10 second overall timeout
  Service A: 8 second timeout to B
    Service B: 6 second timeout to C
      Service C: 4 second timeout to D
```

This ensures that by the time Service A times out, B, C, and D have already given up — no dangling connections.

---

## Pattern 4: Bulkhead

### The Problem

If a slow dependency causes thread exhaustion, it takes down the entire service — including parts that don't depend on that dependency.

### The Solution

Isolate resources (thread pools, connection pools) by function — like watertight compartments (bulkheads) in a ship.

```
Without bulkhead:
  Single thread pool: [T1 T2 T3 T4 T5 T6 T7 T8 T9 T10]
  Slow payment service uses: [T1 T2 T3 T4 T5 T6 T7 T8] ← 8 threads stuck
  Remaining threads: [T9 T10] ← not enough to serve any requests
  Result: entire service fails

With bulkhead:
  Thread pool for payments:  [T1 T2 T3]
  Thread pool for checkout:  [T4 T5 T6]
  Thread pool for search:    [T7 T8 T9 T10]
  
  Slow payment uses: [T1 T2 T3] ← contained
  Checkout and search: [T4-T10] still working fine
  Result: payment feature fails, everything else keeps running
```

Bulkheads limit the **blast radius** of a failure.

---

## Pattern 5: Rate Limiting and Load Shedding

### Rate Limiting

Limit how many requests a client can make in a time window:

```
Per-user rate limit: 100 requests/minute
Per-IP rate limit: 1000 requests/minute
Global rate limit: 50,000 requests/minute

Exceeding limit → HTTP 429 Too Many Requests
```

Rate limiting protects against:
- DDoS attacks
- Runaway clients with bugs causing request loops
- One noisy tenant consuming shared resources

### Load Shedding

When the system is overloaded, deliberately reject some requests to protect the rest:

```
Without load shedding:
  1000 req/s capacity, 2000 req/s arriving
  Result: All 2000 requests are slow, most time out
  Users get: 5 second timeouts → bad experience

With load shedding:
  1000 req/s capacity, 2000 req/s arriving
  Shed 1000 requests immediately with 503
  Remaining 1000 requests: fast, normal response
  Users get: 50% see instant 503 → can retry; 50% see fast response
```

The key insight: **a fast error is better than a slow error.** Fail fast so clients can retry or fall back quickly.

---

## Pattern 6: Graceful Degradation

### The Problem

A service depends on 5 components. One fails. Should the whole service fail?

### The Solution

Design services to keep working (in a reduced capacity) when dependencies are unavailable.

```
E-commerce product page depends on:
  - Product database (critical — can't show product without this)
  - Recommendation engine (non-critical — show page without recommendations)
  - Review service (non-critical — show "reviews unavailable" message)
  - Inventory service (partially critical — show "check availability" button)
  - Personalization service (non-critical — show generic content)

If recommendation engine is down:
  → Show product page without "You might also like" section
  → User barely notices, sale can still complete

If product database is down:
  → Show error page — can't degrade further without core data
```

### Feature flags for degradation

Feature flags allow instant degradation without a deploy:

```
if feature_flag("recommendations_enabled"):
    recommendations = fetch_recommendations(user_id)
else:
    recommendations = []  # degraded mode
```

When the recommendations service is struggling, flip the flag. Instant degradation, no deploy needed.

---

## Pattern 7: Canary Deployments

### The Problem

Every deployment is a risk. How do you validate a new version without exposing all users to a potential failure?

### The Solution

Deploy the new version to a small subset of traffic first ("the canary"), monitor it, then gradually roll out.

```
Phase 1: Deploy v2 to 1% of traffic
  Monitor: error rate, latency, key business metrics
  Wait: 30 minutes to 1 hour
  Decision: metrics healthy → continue; metrics bad → rollback

Phase 2: Increase to 10% of traffic
  Monitor same metrics
  Wait: 1-2 hours
  Decision: proceed or rollback

Phase 3: Increase to 50%, then 100%
  Full rollout once confident
```

### Why it works

- **Early detection**: if v2 has a bug, only 1% of users see it
- **Fast rollback**: reduce traffic split to 0% and rollback — no full rollout to undo
- **Data-driven**: the decision to proceed is based on metrics, not intuition

### Canary in Kubernetes with Argo Rollouts

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: checkout-api
spec:
  strategy:
    canary:
      steps:
      - setWeight: 5      # 5% to canary
      - pause: {duration: 10m}
      - setWeight: 20     # 20% to canary
      - pause: {duration: 10m}
      - setWeight: 50     # 50% to canary
      - pause: {duration: 10m}
      # Full rollout if no manual abort
```

---

## Pattern 8: Chaos Engineering

### What Is Chaos Engineering?

Chaos engineering is the practice of **deliberately injecting failures into production systems to find weaknesses before they cause real incidents.**

The premise: if your system will eventually fail in these ways (and it will), it's better to find out during a controlled experiment than during an incident.

Famous example: Netflix's **Chaos Monkey** randomly terminates production instances to ensure services are resilient to instance failures.

### The Chaos Engineering Process

```
1. Define steady state
   "Normal" = error rate < 0.1%, p99 latency < 300ms

2. Form a hypothesis
   "If we kill one replica of the checkout service,
    the system will self-heal within 30 seconds
    and steady state will be maintained."

3. Design the experiment
   Kill one pod. Observe.

4. Run the experiment (start small)
   kubectl delete pod checkout-api-7d9f8-abc123

5. Observe
   Did steady state hold?
   Did the system recover as expected?
   Did any unexpected downstream effects occur?

6. Fix weaknesses found
   If the system didn't recover as expected → fix it

7. Expand scope
   Run more aggressive experiments as confidence grows
```

### Chaos Tools

| Tool | What it can do |
|------|---------------|
| **Chaos Monkey (Netflix)** | Randomly terminate instances |
| **Litmus Chaos** | Kubernetes-native chaos experiments |
| **Chaos Mesh** | K8s chaos: pod kill, network delay, disk fill |
| **Azure Chaos Studio** | Azure-native chaos engineering |
| **Gremlin** | Enterprise chaos platform, many failure types |

### Common Chaos Experiments

```
Infrastructure failures:
  - Kill a pod / node
  - Drain a node
  - Kill an availability zone (region failure simulation)

Network failures:
  - Add latency to service calls (e.g. +200ms)
  - Drop a percentage of packets
  - Partition network between services

Resource failures:
  - CPU stress (simulate hot CPU)
  - Memory pressure
  - Disk fill

Dependency failures:
  - Kill a database connection
  - Make a downstream service return errors
  - Slow down an external API
```

### Chaos Engineering Safety Rules

- **Always start in staging** — not production
- **Have a kill switch** — ability to immediately stop the experiment
- **Small blast radius first** — single pod, then single node, then AZ
- **Run during business hours** — when full team can respond
- **Never run during other changes** — too many variables
- **Document the experiment** — hypothesis, what happened, outcome

---

## Interview Questions on Reliability Patterns

**Q: What is a circuit breaker and when would you use one?**
A: A circuit breaker monitors calls to a dependency and stops sending traffic when the failure rate exceeds a threshold (OPEN state), protecting the caller from cascading failures. After a timeout it allows test traffic through (HALF-OPEN). Use it whenever Service A calls Service B and B's failure could exhaust A's resources.

**Q: Why add jitter to retry logic?**
A: Without jitter, all clients retry at the same intervals after a failure, creating thundering herd spikes that overwhelm the recovering service. Jitter randomizes retry timing, spreading the load and giving the recovering service a chance to catch up.

**Q: What is chaos engineering and why do companies do it?**
A: Chaos engineering is deliberately injecting failures into systems to find weaknesses before they cause real incidents. Companies do it because production will eventually fail in unexpected ways — it's better to find those failure modes in a controlled experiment with a team ready to respond than during an actual incident at 3am.

**Q: What's the difference between a canary deployment and a blue-green deployment?**
A: In a blue-green deployment, you switch 100% of traffic from old (blue) to new (green) at once — rollback means switching back. In a canary, you gradually increase traffic to the new version (1% → 10% → 50% → 100%), allowing data-driven confidence building. Canary has a smaller blast radius if the new version has issues.
