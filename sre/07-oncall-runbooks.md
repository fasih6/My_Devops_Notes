# On-Call & Runbooks — Sustainable Operations

## What Is On-Call?

On-call is the practice of having an engineer available outside normal working hours to respond to production incidents. The on-call engineer is the first line of defense when alerts fire — they are reachable, responsive, and ready to act.

On-call is necessary. Every production system will fail at inconvenient times. The question is not whether to have on-call, but how to do it without destroying your team.

---

## The On-Call Problem

Poor on-call is one of the leading causes of burnout and attrition in operations teams.

### Signs of unhealthy on-call

```
- Pages fire at 3am for issues that resolve themselves
- The same alert fires every week and nobody fixes the root cause
- On-call engineer handles 10+ pages per shift
- No runbooks exist — every incident requires deep tribal knowledge
- On-call rotations are too small (same person every 2 weeks)
- Post-on-call, engineers come in exhausted and unproductive
- Engineers dread their on-call week
```

### The cost of bad on-call

- **Sleep disruption** is serious. Even one interrupted night affects cognitive performance for 2 days
- **Alert fatigue** — if too many alerts fire, engineers start ignoring them
- **Talent flight** — experienced engineers leave teams with brutal on-call
- **Reduced reliability** — exhausted engineers make more mistakes

---

## Principles of Sustainable On-Call

### 1. On-call load should be manageable

Google's guideline: **no more than 2 significant incidents per 12-hour shift.**

If consistently exceeded:
- Too many alerts need tuning
- Too much toil masquerading as incidents
- Services are not reliable enough

Track pages per shift per on-call rotation. If the number is creeping up, that's a reliability signal requiring engineering work — not more on-call staffing.

### 2. Compensation

On-call outside business hours is a burden. Compensate fairly:
- **Time off in lieu** — on-call shift = some hours of comp time
- **Cash compensation** — many companies pay a flat rate per on-call week
- **Reduced next-day workload** — if you were paged at 3am, you come in late

Without compensation, on-call becomes exploitation. Engineers notice.

### 3. Rotation size matters

```
Ideal rotation: 6-8 engineers
Too small (2-3): Each person is on-call every 2-3 weeks — exhausting
Too large (15+): Engineers are on-call so rarely they forget the systems

With 6-8: Each engineer is on-call once every 6-8 weeks — sustainable
```

### 4. On-call should not require heroics

If resolving incidents requires unique knowledge held by one person, that knowledge is a liability. Runbooks, documentation, and cross-training exist to eliminate single points of human failure.

### 5. Post-incident learning, not post-incident blame

If an on-call engineer makes a mistake during an incident, the system failed to support them. Review the runbook, improve the tooling, reduce the cognitive load — don't blame the engineer.

---

## On-Call Rotation Setup

### Primary and Secondary

Most teams use a two-tier model:

```
Primary on-call:
  - First to be paged
  - Handles investigation and response
  - Expected to respond within 5 minutes

Secondary on-call:
  - Paged if primary doesn't acknowledge within 10-15 minutes
  - Backup for escalation when primary is overwhelmed
  - Also receives context for learning

Escalation path:
  Alert → Primary (5 min) → Secondary (10 min) → Engineering manager (15 min)
```

### Handoff

Good on-call handoffs:
- Written summary of current open issues and their status
- Active alerts that are known/expected (don't alarm the incoming on-call)
- Any unusual deployments or changes in the past 48 hours
- Any services in a degraded but stable state

A verbal-only handoff loses context. Write it down.

### On-Call Schedule Tools

- **PagerDuty** — industry standard, rich scheduling, escalation policies
- **Opsgenie** — strong alternative, good Kubernetes/Azure integration
- **VictorOps/Splunk On-Call** — popular in ops-heavy orgs
- **Alertmanager + email** — minimal, works for small teams

---

## What Are Runbooks?

A runbook is a **documented procedure for handling a specific operational scenario.** It answers the question: "When alert X fires at 3am, what do I do?"

Runbooks exist so that:
- The on-call engineer doesn't need to hold all knowledge in their head
- A new engineer can handle common incidents without escalating
- Response is consistent — every engineer follows the same proven steps
- Recovery is faster — no time lost figuring out what to do

### Runbook vs Playbook

These terms are used interchangeably but have a subtle distinction:

| Term | Scope | Detail level |
|------|-------|-------------|
| **Runbook** | Single specific procedure | Step-by-step, very specific |
| **Playbook** | Set of runbooks for a scenario | Higher level, links to runbooks |

Example:
- Playbook: "Database incident response"
- Runbooks within it: "Handle connection pool exhaustion", "Handle replication lag", "Handle disk full"

---

## How to Write a Good Runbook

### Structure

Every runbook should have:

```
1. Title and Alert Name
   Exactly matching the alert it corresponds to

2. Overview (2-3 sentences)
   What this alert means, why it fires, what the impact is

3. Severity
   What SEV level this typically warrants

4. Prerequisites
   Access required, tools needed, background knowledge assumed

5. Investigation Steps
   Numbered, specific, copy-pasteable commands
   Includes what to look for at each step

6. Resolution Steps
   How to fix the most common causes
   Ordered by likelihood

7. Escalation
   When to escalate and who to escalate to

8. Related Resources
   Links to dashboards, related runbooks, architecture docs
```

### Example Runbook

```markdown
# Runbook: High Database Connection Pool Utilization

## Alert
Alert name: `checkout_db_connection_pool_high`
Threshold: Connection pool utilization > 80% for 5 minutes

## Overview
The checkout service is using more than 80% of its database connection
pool. If this reaches 100%, new requests will fail with connection errors
until connections free up. This typically indicates either elevated traffic
or a connection leak.

## Severity
SEV 2 if > 95% (service degradation imminent)
SEV 3 if 80-95% (investigate proactively)

## Prerequisites
- kubectl access to production cluster
- Read access to Grafana dashboard: Checkout Service Overview
- Read access to PostgreSQL slow query log

## Investigation Steps

1. Check current connection count:
   kubectl exec -n checkout deploy/checkout-api -- \
     psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity;"

2. Check connection pool utilization in Grafana:
   Dashboard: Checkout Service Overview → Panel: DB Connection Pool
   URL: https://grafana.internal/d/checkout-overview

3. Check for connection-heavy queries:
   kubectl exec -n checkout deploy/checkout-api -- \
     psql $DATABASE_URL -c \
     "SELECT pid, now()-query_start AS duration, query
      FROM pg_stat_activity
      WHERE state = 'active'
      ORDER BY duration DESC LIMIT 20;"

4. Check for recent deploys that may have changed connection config:
   kubectl rollout history deploy/checkout-api -n checkout

5. Check current traffic vs baseline in Grafana:
   Dashboard: Checkout Service Overview → Panel: Request Rate

## Resolution Steps

### Cause 1: Traffic spike (most common)
Symptoms: Connection count correlates with request rate spike
Fix: Scale checkout-api replicas
  kubectl scale deploy/checkout-api -n checkout --replicas=<current+2>

Monitor: Watch connection pool utilization drop after scaling

### Cause 2: Connection leak (second most common)
Symptoms: Connection count growing even as traffic normalizes
Fix: Rolling restart to recycle connections
  kubectl rollout restart deploy/checkout-api -n checkout

Monitor: Connection count should drop after each pod restarts

### Cause 3: Slow queries holding connections
Symptoms: Long-running queries visible in step 3
Fix: Kill long-running queries (if safe)
  kubectl exec -n checkout deploy/checkout-api -- \
    psql $DATABASE_URL -c "SELECT pg_terminate_backend(<pid>);"

Note: Coordinate with DBA before killing queries in production

## Escalation
If none of the above resolves the issue within 20 minutes:
- Escalate to DB team (database-oncall@company.com)
- Escalate to checkout team lead

## Related Resources
- Checkout Service Architecture: [link]
- DB Connection Pool Configuration: [link]
- Related runbook: Checkout High Error Rate
```

---

## Runbook Anti-Patterns

**The vague runbook**
"Check if the database is okay."
Check what? How? What does "okay" look like?
Good runbooks have specific, executable commands.

**The stale runbook**
Written 2 years ago, never updated. Commands don't work anymore. Services were renamed. Dashboards moved.
Runbooks must be treated as living documents — updated after every incident that reveals gaps.

**The runbook that assumes too much**
"Fix the replication lag issue."
Assumes the reader knows what replication lag is, where to find it, and how to fix it.
Write for someone who is on-call for the first time and it's 3am.

**The runbook nobody knows about**
Exists in a wiki nobody visits. Not linked from alerts.
Every alert should directly link to its runbook.

**The runbook that replaces thinking**
Overly prescriptive runbooks that give no context make engineers mechanical.
Include the "why" alongside the "what" — engineers who understand the system can handle novel situations.

---

## Linking Alerts to Runbooks

Every alert should include a runbook link in its annotations:

**Prometheus/Alertmanager example:**
```yaml
groups:
  - name: checkout
    rules:
      - alert: CheckoutHighErrorRate
        expr: |
          sum(rate(http_requests_total{service="checkout",status=~"5.."}[5m]))
          /
          sum(rate(http_requests_total{service="checkout"}[5m])) > 0.01
        for: 2m
        labels:
          severity: warning
          team: checkout
        annotations:
          summary: "Checkout API error rate above 1%"
          description: "Current error rate: {{ $value | humanizePercentage }}"
          runbook: "https://wiki.internal/runbooks/checkout-high-error-rate"
          dashboard: "https://grafana.internal/d/checkout-overview"
```

When the on-call engineer acknowledges the alert, they click the runbook link. No searching, no guessing.

---

## On-Call Health Metrics

Track these to measure on-call sustainability:

| Metric | Target | Action if exceeded |
|--------|--------|-------------------|
| Pages per on-call shift | < 2 significant | Tune alerts, fix root causes |
| % of alerts that are actionable | > 80% | Remove or tune noisy alerts |
| MTTA (mean time to acknowledge) | < 5 minutes | Review paging policy, staffing |
| % of incidents with runbooks | > 90% | Write missing runbooks |
| On-call satisfaction score | > 7/10 (survey) | Reduce load, improve tooling |

---

## Interview Questions on On-Call and Runbooks

**Q: What makes on-call sustainable?**
A: Manageable page volume (under 2 significant incidents per shift), fair compensation, rotation size of 6-8 engineers, good runbooks that reduce cognitive load, and a culture where postmortems fix root causes rather than expecting engineers to endure the same pain repeatedly.

**Q: What should a good runbook contain?**
A: The alert name it corresponds to, a brief overview of what the alert means, investigation steps with specific executable commands, resolution steps ordered by most common cause, escalation criteria and contacts, and links to relevant dashboards and architecture docs.

**Q: How do you handle alert fatigue?**
A: Audit every alert regularly. Each alert should answer: "Is this actionable?" and "Does this require a human decision?" Alerts that auto-resolve, fire for known-acceptable conditions, or can't be acted on should be tuned or removed. Track the ratio of actionable to total alerts — target above 80%.

**Q: What's the difference between a runbook and a postmortem?**
A: A runbook is a proactive document — written before incidents to guide response. A postmortem is a reactive document — written after an incident to capture what happened and how to prevent recurrence. Good postmortems often produce new or updated runbooks as action items.
