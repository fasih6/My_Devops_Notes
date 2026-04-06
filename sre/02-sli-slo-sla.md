# SLI / SLO / SLA — Measuring and Contracting Reliability

## The Three Layers of Reliability

These three terms are related but distinct. Most people confuse them. Know the difference cold.

```
SLA  ──── Contract with the customer (external, legal)
  └── SLO ──── Internal target you must hit to keep the SLA
        └── SLI ──── The actual metric you measure
```

Think of it as: **SLI is what you measure, SLO is what you aim for, SLA is what you promise.**

---

## SLI — Service Level Indicator

An SLI is a **carefully defined quantitative measure of some aspect of the level of service being provided.**

In plain English: it's the metric that tells you how reliable your service is right now.

### Properties of a Good SLI

- **Measurable**: you can get a number for it
- **Meaningful**: it reflects the user's experience
- **Aggregated over time**: usually expressed as a ratio or percentage over a window (e.g. 28 days)

### Common SLI Types

| SLI Type | What it measures | Example |
|----------|-----------------|---------|
| **Availability** | Is the service responding? | % of HTTP requests that return non-5xx |
| **Latency** | How fast does it respond? | % of requests completing in < 300ms |
| **Error rate** | How often does it fail? | % of requests that return errors |
| **Throughput** | How much can it handle? | Requests per second successfully served |
| **Durability** | Is data preserved? | % of writes that can be read back |
| **Freshness** | Is data up to date? | % of reads returning data < 10 minutes old |
| **Coverage** | Does it process everything? | % of expected batch jobs that completed |

### SLI Formula

Most SLIs follow this pattern:

```
SLI = (number of good events) / (total events) × 100

Example (availability):
  SLI = (successful requests) / (total requests) × 100
  SLI = 998,000 / 1,000,000 × 100 = 99.8%

Example (latency):
  SLI = (requests completing < 300ms) / (total requests) × 100
  SLI = 995,000 / 1,000,000 × 100 = 99.5%
```

### What NOT to use as SLIs

- **CPU usage** — an internal metric, not user-facing
- **Memory usage** — same, not directly experienced by users
- **Disk I/O** — internal resource metric
- **"Is the server up?"** — too coarse, doesn't capture quality

The test: *would a user notice if this metric was bad?* If no, it's probably not a good SLI.

---

## SLO — Service Level Objective

An SLO is a **target value or range of values for a service level that is measured by an SLI.**

In plain English: it's the number you're trying to hit.

```
SLO = SLI target over a time window

Example:
  "99.9% of requests will return a successful response
   over a rolling 28-day window"
```

### Choosing the Right SLO Target

The most common mistake: setting the SLO too high.

```
100%  ← Impossible. Never target this.
99.99% ← Very high bar. Requires serious engineering. ~52 min downtime/year.
99.9%  ← Common for important services. ~8.7 hours downtime/year.
99.5%  ← Acceptable for less critical services. ~43 hours/year.
99%    ← Baseline. ~3.65 days/year.
```

**Downtime calculator:**

| SLO | Max downtime/year | Max downtime/month | Max downtime/week |
|-----|------------------|-------------------|------------------|
| 99% | 3.65 days | 7.2 hours | 1.68 hours |
| 99.5% | 1.83 days | 3.6 hours | 50.4 min |
| 99.9% | 8.77 hours | 43.8 min | 10.1 min |
| 99.95% | 4.38 hours | 21.9 min | 5 min |
| 99.99% | 52.6 min | 4.38 min | 1 min |

### SLO Design Principles

**1. Base it on user happiness, not infrastructure metrics**
Ask: "What level of reliability would make users stop noticing problems?"
That's usually your SLO target — set it there, not higher.

**2. Start lower than you think you need**
It's much easier to raise an SLO than to lower one.
Lowering an SLO requires a difficult conversation with stakeholders.

**3. Add a safety margin**
Your SLO should be slightly tighter than your SLA.
If your SLA promises 99.9%, your internal SLO should target 99.95%.
This gives you warning before you breach the contract.

**4. Use a rolling window, not a calendar window**
A 28-day rolling window is more operationally useful than "this month."

**5. Have multiple SLOs for the same service**
A service might have:
- Availability SLO: 99.9% of requests succeed
- Latency SLO: 99% of requests complete in < 300ms (p99 latency)
- Both matter independently to users

### SLO Examples by Service Type

| Service | Example SLO |
|---------|------------|
| Payment API | 99.99% availability, p99 latency < 500ms |
| User auth | 99.9% availability, p99 latency < 200ms |
| Search | 99.5% availability, p95 latency < 1s |
| Batch reports | 99% of jobs complete within 4 hours of schedule |
| Data pipeline | 99.9% of records processed, freshness < 15 min |

---

## SLA — Service Level Agreement

An SLA is a **contract between a service provider and a customer that specifies what level of service is promised, and what happens if it isn't delivered.**

Key characteristics:
- **External** — involves the customer/user, not just internal teams
- **Legal** — has consequences (refunds, credits, penalties)
- **Coarser** than SLOs — usually a subset of what you track internally

### SLA vs SLO — The Practical Difference

```
                SLO (internal)      SLA (external)
────────────────────────────────────────────────────
Who sees it?    Engineering team    Customers / legal
Consequence?    Error budget burn   Financial penalty / churn
Target          99.95%              99.9%  ← always lower
Window          28-day rolling      Monthly calendar
Enforced by?    SRE team culture    Contract law
```

The SLO is always more aggressive than the SLA. This gap is your buffer.

### What Happens When an SLA Is Breached?

Typically: service credits (refunds as % of monthly bill).

Example from a cloud provider:
- Monthly uptime < 99.9% → 10% service credit
- Monthly uptime < 99% → 25% service credit
- Monthly uptime < 95% → 100% service credit

---

## Putting It All Together — A Real Example

Imagine you run a checkout API:

```
SLI: (HTTP 2xx responses) / (total HTTP responses) × 100

SLO: SLI ≥ 99.9% over rolling 28 days
     (internal target your team owns)

SLA: 99.5% availability guaranteed to customers
     (external, with 10% refund if breached)

Error budget (from SLO):
  100% - 99.9% = 0.1% of requests can fail
  Over 28 days × 24h × 60min × 60s = 2,419,200 seconds
  0.1% of that = 2,419 seconds of downtime allowed
```

---

## How to Implement SLIs and SLOs

### Step 1 — Choose your SLIs
Ask: "What does the user care about for this service?"
For an API: availability and latency.
For a database: durability and query latency.
For a batch job: completion rate and freshness.

### Step 2 — Instrument the SLI
You need a query that produces the SLI value.

**Prometheus example (availability SLI):**
```promql
# Success rate over 28 days
sum(rate(http_requests_total{status!~"5.."}[28d]))
/
sum(rate(http_requests_total[28d]))
```

**Prometheus example (latency SLI — % of requests < 300ms):**
```promql
sum(rate(http_request_duration_seconds_bucket{le="0.3"}[28d]))
/
sum(rate(http_request_duration_seconds_count[28d]))
```

### Step 3 — Set the SLO target
Pick the target based on user impact analysis, not gut feel.
Document the reasoning.

### Step 4 — Calculate the error budget
```
Error budget = 1 - SLO target
Example: 1 - 0.999 = 0.001 = 0.1%
Over 28 days: 0.001 × 28 × 24 × 60 = 40.32 minutes of allowed downtime
```

### Step 5 — Alert on error budget burn
Don't alert when SLO is breached — alert when you're consuming the error budget too fast.
(See `03-error-budgets.md` for burn rate alerting.)

---

## Common Interview Questions on SLI/SLO/SLA

**Q: What's the difference between SLI, SLO, and SLA?**
A: SLI is the metric (e.g. % successful requests). SLO is the target for that metric (e.g. 99.9%). SLA is the external contract with consequences if the target isn't met. SLOs are always more aggressive than SLAs to give a buffer.

**Q: Why shouldn't you target 100% availability?**
A: 100% is unachievable in practice, and targeting it creates perverse incentives — teams become afraid to deploy because any deployment risks a breach. A meaningful error budget (e.g. 0.1%) allows controlled risk-taking and keeps teams shipping.

**Q: How do you choose what to use as an SLI?**
A: The SLI should directly measure user experience, not internal system health. Ask "would a user notice if this metric was bad?" Good SLIs: request success rate, latency percentiles. Bad SLIs: CPU usage, memory consumption.

**Q: What's a good SLO for a payment API?**
A: Typically 99.99% availability (payments are high-value, failures directly cost money) with p99 latency < 500ms. The exact number depends on the business context and historical performance.
