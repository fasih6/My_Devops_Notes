# Incident Management — Severity, Response, and Communication

## What Is an Incident?

An incident is any **unplanned disruption or degradation in service quality** that affects users or risks doing so.

Incidents are not just outages. They include:
- Complete service unavailability (full outage)
- Partial degradation (slow responses, elevated error rates)
- Data integrity issues (wrong data being served)
- Security events (unauthorized access, data exposure)
- Anticipated future failures (a disk at 99% capacity that will fail tonight)

The goal of incident management is not to prevent all incidents — that's impossible. The goal is to **detect fast, respond effectively, restore service quickly, and learn from every failure.**

---

## Severity Levels

Severity levels classify incidents by their user impact and required response urgency. Every organization defines these slightly differently — but the pattern is universal.

### Standard Severity Model

```
SEV 1 — Critical
  Impact:   Complete service outage or critical data loss
  Users:    All or majority affected
  Revenue:  Significant revenue impact
  Response: Immediate — wake up everyone, drop everything
  Example:  Payment API down, login broken for all users

SEV 2 — High
  Impact:   Major functionality degraded, key feature broken
  Users:    Large portion affected or all users have degraded experience
  Revenue:  Moderate revenue impact
  Response: Urgent — respond within 15 minutes during business hours,
            page on-call outside hours
  Example:  Checkout 10x slower than normal, search returning errors

SEV 3 — Medium
  Impact:   Non-critical feature degraded or small user subset affected
  Users:    Some users affected with workaround available
  Revenue:  Minor revenue impact
  Response: During business hours, next available engineer
  Example:  Export feature failing, reports delayed by 2 hours

SEV 4 — Low
  Impact:   Cosmetic issue or very minor degradation
  Users:    Minimal user impact
  Revenue:  Negligible
  Response: Scheduled fix, no urgency
  Example:  UI element misaligned, non-critical metric missing from dashboard
```

### Escalation Rule

When in doubt, **declare a higher severity and downgrade later.** 

It's far better to mobilize for a SEV 2 that turns out to be SEV 3 than to under-respond to a SEV 1 while calling it SEV 2.

---

## Roles in Incident Response

Good incident response requires clear role separation. When everyone is responsible, no one is responsible.

### Incident Commander (IC)

The IC is the **single point of coordination** for the incident. They do NOT fix things themselves — they direct others, manage communication, and make decisions.

Responsibilities:
- Declare the incident and set severity
- Assign roles (responders, comms lead)
- Direct investigation: "We need to rule out the database first"
- Make the call to escalate or downgrade
- Declare the incident resolved
- Ensure postmortem is opened

The IC needs authority. When they say "stop that, focus here" — people listen.

### Responders / Subject Matter Experts

The engineers who actually investigate and fix the problem.

Responsibilities:
- Investigate assigned areas
- Report findings to IC (status updates, not decisions)
- Implement fixes
- Verify the fix worked

Rule: responders should not be deciding what to investigate next — that's the IC's job. Responders go deep; IC keeps perspective.

### Communications Lead (Comms)

Handles all external and internal communication so responders can focus.

Responsibilities:
- Post status page updates
- Write customer-facing notifications
- Update internal stakeholders (support, product, leadership)
- Track timeline for postmortem

### Scribe

Documents everything in real time.

Responsibilities:
- Log every action taken with timestamps
- Record hypotheses and what was ruled out
- Capture all commands run and their outputs
- This becomes the incident timeline for the postmortem

---

## The Incident Response Lifecycle

```
┌──────────────────────────────────────────────────────────────┐
│                   INCIDENT LIFECYCLE                          │
│                                                              │
│  1. DETECT        Alert fires or user reports issue          │
│       ↓                                                      │
│  2. TRIAGE        Assess impact, assign severity, page IC    │
│       ↓                                                      │
│  3. MOBILIZE      Assemble team, open incident channel,      │
│                   start status page update                   │
│       ↓                                                      │
│  4. INVESTIGATE   Form hypotheses, eliminate causes,         │
│                   gather evidence                            │
│       ↓                                                      │
│  5. MITIGATE      Implement temporary fix to restore service │
│       ↓                                                      │
│  6. RESOLVE       Confirm service is back to normal,         │
│                   declare incident closed                    │
│       ↓                                                      │
│  7. FOLLOW-UP     Open postmortem, track action items        │
└──────────────────────────────────────────────────────────────┘
```

### Step 1 — Detect

Detection can come from:
- Automated alerting (PagerDuty, Opsgenie, Alertmanager fires)
- User reports (support ticket, Slack message)
- Proactive monitoring (engineer notices metric anomaly)
- Synthetic monitoring (health check fails)

**MTTD (Mean Time To Detect)** is the key metric here. Good alerting = low MTTD.

### Step 2 — Triage

The first responder quickly assesses:
- Is this real or a false positive?
- What is the user impact?
- What severity level applies?
- Does this need more people?

Triage should take minutes, not hours.

### Step 3 — Mobilize

Once severity is set:
- Page additional responders based on severity
- Open the incident communication channel (e.g. `#incident-2024-11-15-checkout`)
- Create an incident ticket/record
- Post first status page update: "We are investigating reports of..."
- IC takes command

### Step 4 — Investigate

The hardest part. Common approaches:

**Hypothesis-driven debugging:**
```
Form a hypothesis → test it → confirm or eliminate → repeat

"Hypothesis: Database is overloaded"
→ Check DB CPU, connections, slow query log
→ DB looks healthy → eliminate, move on

"Hypothesis: Recent deploy broke something"
→ Check deploy time vs incident start time
→ Deploy at 14:32, alerts fired at 14:35 → strong signal
→ Test: roll back deploy → errors drop → confirmed
```

**Timeline correlation:**
```
When did errors start? 14:35
What changed around that time?
  14:32 — deployment of checkout-service v2.3.1
  14:30 — traffic spike from marketing campaign
  14:28 — DB maintenance window ended

Start with most recent change closest to incident start.
```

**The 5 Whys:**
```
Why did users see errors? → Checkout API returned 500s
Why did the API return 500s? → DB connection pool exhausted
Why was the pool exhausted? → New version opened too many connections
Why did it open too many? → Missing connection limit config in new deploy
Why was config missing? → New environment variable not set in deployment
Root cause: missing environment variable
```

### Step 5 — Mitigate

Mitigation is **restoring service**, not fixing the root cause. These are different.

Common mitigations:
- Roll back the recent deploy
- Increase replica count to handle load
- Restart a stuck process
- Fail over to a backup system
- Reroute traffic away from the broken component
- Disable a broken feature with a feature flag

Document every action taken. An action that mitigates might also cause new problems.

### Step 6 — Resolve

Before declaring resolved:
- Confirm error rates are back to normal
- Confirm latency is back to normal
- Confirm no downstream services are still affected
- Confirm monitoring is healthy

Post the "incident resolved" message to status page and internal channels.

### Step 7 — Follow-Up

- Open the postmortem within 24 hours of resolution
- Create action items for any temporary mitigations that need permanent fixes
- Track MTTR for this incident
- Review: should alerting have caught this faster?

---

## Communication During Incidents

Poor communication is as damaging as the incident itself. Key rules:

### Internal communication

- Use a dedicated incident channel — don't mix incident response with general noise
- Status updates every 15-30 minutes, even if it's "Still investigating, no update"
- Use structured updates: **what you know, what you're doing, what's next**
- Keep the signal-to-noise ratio high — no side conversations in the incident channel

### External communication (status page)

Status page update cadence:
```
First update (within 5-10 min of detection):
  "We are investigating reports of [issue]. We will update in 30 minutes."

Progress update (every 30 min):
  "We have identified [component] as the cause and are implementing a fix."

Resolution:
  "The issue has been resolved as of [time]. [Brief explanation of cause]."
```

Rules for status page updates:
- Don't speculate — only confirm what you know
- Don't minimize — users can see the impact themselves
- Be specific about timing: "resolved at 15:42 UTC" not "earlier today"
- Never go dark — silence is the worst possible communication

### Stakeholder notifications

SEV 1/2 incidents typically require:
- Support team notification (so they can answer user questions)
- Product/business notification (if revenue is impacted)
- Executive notification (for major outages)

---

## Key Incident Metrics

| Metric | What it measures | Formula |
|--------|-----------------|---------|
| **MTTD** | Mean Time To Detect | Avg time from failure start to detection |
| **MTTA** | Mean Time To Acknowledge | Avg time from alert to first human response |
| **MTTM** | Mean Time To Mitigate | Avg time from detection to service restoration |
| **MTTR** | Mean Time To Recover/Resolve | Avg time from detection to full resolution |
| **MTBF** | Mean Time Between Failures | Avg time between incidents of the same type |

```
Incident timeline example:
  14:30 — Failure starts
  14:35 — Alert fires (MTTD = 5 min)
  14:37 — On-call acknowledges (MTTA = 2 min)
  14:55 — Service restored via rollback (MTTM = 20 min from detection)
  16:00 — Root cause fixed and deployed (MTTR = 90 min from detection)
```

Aim to reduce MTTD and MTTM over time through better alerting and runbooks.

---

## Interview Questions on Incident Management

**Q: Walk me through how you'd handle a production outage.**
A: Acknowledge the alert, assess impact and set severity, page additional responders if needed, open an incident channel, assign IC role, investigate using hypothesis-driven debugging (correlate timeline with recent changes), implement a mitigation (often a rollback), confirm resolution, and open a postmortem within 24 hours.

**Q: What's the difference between mitigation and resolution?**
A: Mitigation restores service (e.g. rolling back a deploy to stop errors). Resolution fixes the root cause (e.g. fixing the bug and deploying a proper fix). Often you mitigate quickly to restore service, then resolve properly over hours or days.

**Q: What is the role of an Incident Commander?**
A: The IC coordinates the response without doing the hands-on debugging. They direct who investigates what, make calls on severity, manage external communication, and declare the incident resolved. Having a dedicated IC prevents the "too many cooks" problem and ensures someone maintains the big picture.

**Q: How do you decide when to wake someone up vs wait until morning?**
A: Based on severity level and the error budget policy. A SEV 1 (complete outage) wakes up the on-call immediately at any hour. A SEV 3 (minor feature degraded, workaround available) waits for business hours. Having pre-agreed severity definitions means this is decided by the policy, not the on-call engineer's judgment at 3am.
