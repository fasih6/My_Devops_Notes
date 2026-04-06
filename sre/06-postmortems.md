# Postmortems — Blameless Culture, Root Cause Analysis, and Follow-ups

## What Is a Postmortem?

A postmortem (also called an incident review or post-incident analysis) is a **structured written record of an incident that captures what happened, why it happened, and what will be done to prevent it from happening again.**

The word comes from medicine — a postmortem examination determines cause of death. In SRE, it determines cause of failure.

Key properties of a good postmortem:
- **Written** — not just a verbal debrief, a persistent document
- **Blameless** — focuses on systems and processes, not individuals
- **Actionable** — produces concrete follow-up items with owners and deadlines
- **Shared** — distributed across the organization so others can learn

---

## Blameless Postmortems — The Foundation

The most important word in SRE postmortem culture is **blameless**.

### Why blameless?

When you blame people for incidents, you get:
- Engineers who hide mistakes rather than report them
- Incomplete incident timelines (people omit their own errors)
- No learning — the same incident happens again
- Fear of on-call rotations and production responsibility
- Attrition — good engineers leave environments where one mistake ends a career

When you focus on systems rather than people, you get:
- Complete, honest incident timelines
- Real root causes (not just "human error")
- Systemic fixes that prevent recurrence
- Psychological safety — engineers take production ownership
- A learning culture where failures make the system stronger

### The blameless principle in practice

**"Human error" is never a root cause — it's a symptom.**

```
Bad postmortem:
  Root cause: Engineer ran the wrong command in production.
  Action item: Train engineers to be more careful.

  Why this is wrong: The system allowed a catastrophic command to run
  in production without safeguards. The next engineer will make the
  same mistake. Nothing was fixed.

Good postmortem:
  Root cause: No safeguard prevented a destructive command from
  running in production. The staging and production environments
  use identical CLI access, making accidental production changes easy.
  Action items:
  - Add confirmation prompt for destructive operations in prod
  - Implement separate credentials for prod vs staging
  - Add automated backup before any schema change
  - Review access controls on production database

  Why this is right: The system is now harder to break accidentally.
  A different engineer making the same mistake will be protected.
```

The shift: from "who made the mistake" to "what conditions made the mistake possible and likely."

### Just Culture

Blameless doesn't mean consequence-free. It means:
- Honest mistakes in good faith → no punishment, full learning
- Negligence or willful policy violations → appropriate consequences

This is called "just culture" — borrowed from aviation safety. The goal is an environment where engineers report problems immediately and honestly because they know the system responds to help, not blame.

---

## When to Write a Postmortem

Not every incident needs a full postmortem. Common triggers:

| Trigger | Write postmortem? |
|---------|------------------|
| SEV 1 incident | Always |
| SEV 2 incident | Always |
| SEV 3 with user impact | Usually |
| SEV 3 caught before user impact | Sometimes |
| SEV 4 | Rarely (unless systemic pattern) |
| Error budget significantly burned | Yes |
| Same incident recurring | Yes, even if minor |
| Near-miss that could have been SEV 1 | Yes |

**The 24-hour rule:** Open the postmortem document within 24 hours of incident resolution, while memory is fresh. The full writeup can take longer, but the timeline should be captured immediately.

---

## Postmortem Structure

Every postmortem document should have these sections:

### 1. Summary

A 2-3 sentence executive summary of the incident.

```
Example:
On 2024-11-15 between 14:35 and 15:42 UTC, the checkout API returned
500 errors for approximately 40% of requests. The root cause was an
unconfigured connection pool limit in the v2.3.1 deploy that exhausted
database connections under normal load. Service was restored by rolling
back to v2.3.0.
```

### 2. Impact

Quantify the impact precisely:

```
Duration: 67 minutes (14:35 – 15:42 UTC)
Users affected: ~40% of checkout attempts failed
Requests failed: approximately 28,400
Revenue impact: estimated €12,000 in lost transactions
Error budget consumed: 31 minutes of a 43.8-minute monthly budget (71%)
Services affected: checkout-api, order-service (downstream)
Geographic scope: EU region only
```

### 3. Timeline

A chronological log of events. This is built from the scribe's notes during the incident.

```
14:28 UTC  Database maintenance window ends (routine, no issues)
14:32 UTC  checkout-service v2.3.1 deployed to production
14:35 UTC  Alertmanager fires: checkout error rate > 5% (threshold)
14:37 UTC  On-call engineer (Ali) acknowledges alert
14:39 UTC  Ali opens #incident-2024-11-15 channel, declares SEV 2
14:41 UTC  IC (Sara) joins, assigns Ali as responder, Kai as comms
14:42 UTC  Status page updated: "Investigating checkout issues"
14:45 UTC  Hypothesis 1: DB maintenance caused connection issues — ruled out
           (DB metrics healthy, maintenance ended before deploy)
14:49 UTC  Hypothesis 2: Recent deploy introduced bug — correlates with timeline
14:52 UTC  Ali reviews v2.3.1 changes — finds new DB connection config
14:55 UTC  Decision: roll back to v2.3.0
14:58 UTC  Rollback initiated
15:03 UTC  Error rate dropping — rollback successful
15:08 UTC  Error rate back to baseline
15:10 UTC  Status page updated: "Issue resolved, investigating root cause"
15:42 UTC  Root cause confirmed. Incident closed.
16:30 UTC  Postmortem opened.
```

### 4. Root Cause Analysis

Go deeper than the surface explanation. Use the 5 Whys.

```
Surface cause: checkout-service v2.3.1 returned 500 errors

5 Whys:
  Why did v2.3.1 return errors?
  → Database connection pool was exhausted

  Why was the pool exhausted?
  → New config file had no MAX_CONNECTIONS value set

  Why was MAX_CONNECTIONS not set?
  → It was a new required config added in v2.3.1 but not
    documented in the deployment checklist

  Why wasn't it in the deployment checklist?
  → The checklist is manually maintained and wasn't updated
    when the new config was added

  Why wasn't the checklist update caught in review?
  → No automated validation checks that all required env
    variables are present before deployment

Root cause: No automated validation of required configuration
before production deployment allows misconfigured services
to deploy silently.
```

### 5. Contributing Factors

Factors that made the incident worse or harder to detect:

```
- No staging environment load test that would have caught the missing config
- Alert threshold of 5% error rate meant 5 minutes of elevated errors
  before detection (lower threshold would have caught it faster)
- Rollback procedure not documented — engineer had to look it up during incident
  (added 3-4 minutes to resolution time)
- DB connection pool exhaustion metric not dashboarded (relied on app errors
  to detect, not the leading indicator)
```

### 6. Action Items

The most important section. Every action item needs:
- A specific, concrete description
- An owner (one person, not a team)
- A deadline
- A priority (P1/P2/P3)

```
| Action | Owner | Deadline | Priority |
|--------|-------|----------|----------|
| Add automated config validation to deployment pipeline that fails build if required env vars are missing | Ali | 2024-11-22 | P1 |
| Add DB connection pool utilization to Grafana dashboard and alert at 80% | Priya | 2024-11-22 | P1 |
| Document rollback procedure in runbook | Kai | 2024-11-20 | P2 |
| Add checkout load test to staging CI pipeline | Sara | 2024-12-01 | P2 |
| Reduce checkout error rate alert threshold from 5% to 1% | Ali | 2024-11-19 | P2 |
| Update deployment checklist process to require changelog when new config vars are added | Team | 2024-11-25 | P3 |
```

### 7. Lessons Learned

Broader takeaways that may apply beyond this specific service:

```
- Configuration validation should be automated, not manual
- Leading indicators (resource utilization) are more valuable than lagging
  indicators (error rates) for catching issues before users are affected
- Rollback procedures should be documented and practiced before they're needed
- Deployment checklists that aren't automatically enforced drift from reality
```

---

## Common Postmortem Anti-Patterns

**The blame postmortem**
"Root cause: engineer forgot to set the config."
Nothing is fixed. Same incident happens again with a different engineer.

**The surface-cause postmortem**
Stops at the first cause: "The config was missing."
Doesn't ask WHY the config was missing or HOW to prevent it.

**The postmortem with no action items**
"We understand what happened." But nothing changes.
Postmortems without action items are documentation, not improvement.

**The postmortem with vague action items**
"Improve monitoring." Who? By when? Monitoring of what?
Every action item must be specific, owned, and time-bound.

**The postmortem that's never read**
Written, filed, forgotten. No sharing, no learning.
Postmortems should be shared with the broader engineering org.

**The postmortem written too late**
If written 2 weeks after the incident, the timeline is incomplete, details are forgotten, and action items never get done.

---

## Postmortem Review Meeting

For SEV 1 incidents and major SEV 2s, hold a postmortem review meeting:

**Agenda:**
1. Walk through the timeline (20 min)
2. Discuss root cause analysis — do we agree? (15 min)
3. Review action items — are they the right ones? (15 min)
4. Assign owners and deadlines (10 min)
5. What else should we share with the broader team? (5 min)

**Rules:**
- No blame, no "you should have" language
- Focus on the system, not the people
- Everyone who was involved attends
- Leadership can attend but should not dominate

---

## Interview Questions on Postmortems

**Q: What is a blameless postmortem and why does it matter?**
A: A blameless postmortem focuses on systems and processes rather than individual mistakes. It matters because blame culture causes engineers to hide mistakes, produces incomplete timelines, and results in no real fixes — the same incident recurs. Blameless culture produces honest timelines, systemic root causes, and action items that prevent recurrence.

**Q: What sections should a good postmortem include?**
A: Summary, impact (quantified), timeline, root cause analysis (using 5 Whys), contributing factors, action items (with owners and deadlines), and lessons learned.

**Q: "Human error" — is that a root cause?**
A: Never. Human error is a symptom of a system that made the mistake easy to make. The real root cause is the system condition that allowed the error. The fix is making the system more robust, not asking humans to be more careful.

**Q: How do you ensure postmortem action items actually get done?**
A: Every action item needs a specific description, a single named owner (not a team), and a deadline. Track them in the team's project management tool, review them in weekly team meetings, and measure the closure rate over time. Unclosed action items from past incidents are a leading indicator of future incidents.
