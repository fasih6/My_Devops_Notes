# Error Budgets — Balancing Reliability and Velocity

## What Is an Error Budget?

An error budget is the **maximum amount of unreliability your service is allowed to have while still meeting its SLO.**

It's the direct mathematical consequence of your SLO:

```
Error budget = 1 - SLO target

SLO = 99.9%  →  Error budget = 0.1%
SLO = 99.5%  →  Error budget = 0.5%
SLO = 99.99% →  Error budget = 0.01%
```

But "0.1%" is abstract. Convert it to something tangible:

```
Over 30 days (2,592,000 seconds):
  99.9% SLO → 0.1% × 2,592,000 = 2,592 seconds ≈ 43 minutes of downtime allowed

Over 30 days (2,592,000 requests):
  99.9% SLO → 0.1% × 2,592,000 = 2,592 failed requests allowed
```

The error budget exists to be **spent** — not to be hoarded.

---

## Why Error Budgets Exist — The Core Insight

Before error budgets, development and operations had a fundamental conflict:

```
Development team wants:     Operations team wants:
─────────────────────────   ──────────────────────
Ship features fast          System stays stable
Deploy often                Fewer risky changes
Move quickly                Reliability above all
```

This conflict never resolves — it just gets louder.

**Error budgets solve this by making the tradeoff explicit and shared:**

```
If error budget is healthy (lots remaining):
  → Both teams agree: ship faster, deploy more often, take more risk
  → Reliability is good, so we have room to move

If error budget is nearly exhausted (almost gone):
  → Both teams agree: slow down, focus on reliability, freeze features
  → Not a political fight — the math says stop

If error budget is exhausted:
  → Freeze all non-critical deployments until budget recovers
  → Focus 100% on reliability work
```

The error budget turns a political argument into an engineering constraint. Neither team "wins" — the budget decides.

---

## Error Budget Policy

An error budget policy is the **written agreement between SRE and product teams about what happens at different budget levels.**

Without a written policy, error budget conversations become political every time.

### Example Error Budget Policy

```
Service: Checkout API
SLO: 99.9% availability over rolling 28 days
Error budget: 43.8 minutes/month

┌────────────────────────────────────────────────────────────┐
│ Budget remaining  │ Action                                  │
├────────────────────────────────────────────────────────────┤
│ > 50%             │ Normal operations. Ship freely.         │
│ 25% – 50%         │ Increased caution. Review risky changes.│
│ 10% – 25%         │ Slow down. No experimental features.    │
│                   │ Reliability work takes priority.        │
│ < 10%             │ Feature freeze. Only critical fixes and │
│                   │ reliability improvements allowed.       │
│ Exhausted (0%)    │ Full freeze. SRE escalates to eng lead. │
│                   │ Postmortem required for root cause.     │
└────────────────────────────────────────────────────────────┘
```

This policy must be agreed upon and signed off by:
- SRE team
- Product engineering team
- Product management
- Engineering leadership

### What counts as "spending" the error budget?

Any event that degrades reliability below the SLO:
- Outages and incidents
- Bad deployments that cause increased error rates
- Performance degradations that push latency above SLO
- Planned maintenance (yes, this counts too)
- Infrastructure failures (cloud provider issues)

---

## Error Budget Burn Rate

Burn rate is **how fast you're consuming your error budget relative to how fast it should be consumed.**

If your 28-day error budget is 43.8 minutes, and you're spread evenly, you'd burn about 1.57 minutes per day.

```
Burn rate = 1 → consuming budget at exactly the expected rate
Burn rate = 2 → consuming budget twice as fast as expected
Burn rate = 10 → at this rate, budget exhausted in 1/10 of the window
```

### Why Burn Rate Matters for Alerting

Simple threshold alerting on SLO doesn't work well:

```
Problem with "alert when SLO is breached":
  If your SLO is 99.9% and you have a slow leak of 0.11% error rate,
  it takes WEEKS before you breach the 28-day SLO — but you're burning
  budget the whole time, silently.

  By the time the alert fires, you've already failed.
```

**Burn rate alerting catches problems early:**

```
Alert when burn rate is too high relative to time remaining.

Fast burn (e.g. burn rate > 14):
  → You'll exhaust the ENTIRE 28-day budget in less than 2 days
  → Page immediately — this is an incident

Slow burn (e.g. burn rate > 1):
  → You're consuming more budget than you should
  → Create a ticket, investigate, but don't wake anyone up
```

### Google's Multi-Window Burn Rate Alerting

Google recommends using two alert windows to catch both fast and slow burns:

```
Alert 1 — Fast burn (critical, page on-call):
  Condition: 2% budget consumed in last 1 hour
  AND 5% consumed in last 6 hours
  Meaning: burn rate ≥ ~14.4x normal
  Response: Incident, immediate action

Alert 2 — Slow burn (warning, ticket):
  Condition: 10% budget consumed in last 3 days
  Meaning: burn rate ≥ ~3x normal sustained
  Response: Engineering team investigates this week
```

This approach catches:
- Sudden catastrophic failures (fast burn)
- Slow degradation that would exhaust budget by month end (slow burn)

---

## Error Budget in Practice — A Day in the Life

### Scenario 1: Healthy budget, shipping fast

```
Monday: Error budget at 90% remaining
Product team wants to ship a major feature Friday
SRE says: "Budget is healthy, go ahead. Monitor closely post-deploy."
Deploy happens Friday, small spike in errors, budget drops to 75%
Both teams happy — velocity maintained, budget still comfortable
```

### Scenario 2: Budget getting low, tension rises

```
Wednesday: Error budget at 15% remaining (2 weeks into the month)
Product team wants to ship 3 features before the sprint ends
SRE says: "Per our error budget policy, we're in caution zone"
Agreement: ship 1 low-risk feature, hold the other 2
SRE focuses on identifying the source of the budget burn
Root cause found: noisy retry logic in upstream service
Fix deployed, burn rate drops back to normal
```

### Scenario 3: Budget exhausted, freeze enforced

```
Error budget hits 0% on day 18 of 28
Per the policy: feature freeze immediately
Postmortem opens for the incident that exhausted the budget
Dev team pivots to reliability work for the remainder of the month
SLO resets at day 28, and the team starts fresh with full budget
```

---

## Common Mistakes with Error Budgets

**Mistake 1: SLO set too high from the start**
If your service is naturally 99.7% reliable, setting a 99.9% SLO means you're always in violation.
Set your SLO based on current reality, then improve.

**Mistake 2: Not counting planned maintenance**
"It was scheduled downtime, so it doesn't count."
Wrong. Users experience it. It counts. Either exclude it from SLI measurement deliberately, or count it.

**Mistake 3: No written policy**
Without a policy, every budget decision is a negotiation. Write the policy when the budget is healthy so it's agreed upon before pressure hits.

**Mistake 4: Treating the error budget as a shame metric**
The budget exists to be spent. Spending it on a risky feature that delivers value is fine.
Only spending it on preventable failures is a problem.

**Mistake 5: Different teams measuring differently**
If SRE and product measure the error budget differently, every conversation is a fight about whose numbers are right.
One system of record, one dashboard, agreed upon upfront.

---

## Interview Questions on Error Budgets

**Q: What is an error budget and why does it matter?**
A: An error budget is the maximum allowed unreliability derived from the SLO (e.g. 99.9% SLO = 0.1% error budget). It matters because it creates a shared, data-driven framework for balancing feature velocity and reliability — instead of political arguments, the budget decides how fast to ship.

**Q: What happens when an error budget is exhausted?**
A: Per the error budget policy: feature releases freeze, reliability work takes priority, and a postmortem is opened to find the root cause. Once the 28-day window rolls forward and new budget is available, normal operations resume.

**Q: What is burn rate?**
A: Burn rate is how fast you're consuming the error budget compared to the expected rate. A burn rate of 1 means normal consumption. A burn rate of 14 means you'll exhaust the entire 28-day budget in 2 days — page the on-call immediately.

**Q: How do you alert on SLO violations without too many false positives?**
A: Use multi-window burn rate alerting. Alert immediately on fast burns (e.g. 2% budget consumed in 1 hour). Use a ticket/warning for slow burns (e.g. 10% budget in 3 days). This catches both sudden failures and slow degradation without waking people up unnecessarily.
