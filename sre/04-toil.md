# Toil — What It Is, Why It Matters, How to Eliminate It

## What Is Toil?

Toil is the kind of work tied to running a production service that has the following characteristics:

| Property | Explanation |
|----------|-------------|
| **Manual** | A human does it by hand, not a machine |
| **Repetitive** | You do it again and again, the same way |
| **Automatable** | A machine could do it instead |
| **Tactical** | Reactive, not strategic — triggered by events |
| **No enduring value** | Doing it doesn't improve the system — it just keeps it running |
| **Scales with traffic** | As your service grows, the work grows proportionally |

The last property is critical. If your operational work grows linearly with your service load, you'll eventually need to hire humans as fast as you add users — which doesn't scale.

**Google's definition:** *"Toil is the work that tends to be manual, repetitive, automatable, tactical, devoid of enduring value, and that scales linearly as a service grows."*

---

## Toil vs Overhead vs Engineering Work

These three types of work are often confused:

```
Toil                        Overhead                   Engineering Work
────────────────────────    ─────────────────────────   ──────────────────────
Running services manually   Admin that can't be         Permanent improvements
                            automated away
e.g. restarting pods        e.g. team meetings          e.g. building autoscaler
e.g. manual deploys         e.g. hiring interviews      e.g. writing runbooks
e.g. resizing disks         e.g. expense reports        e.g. improving alerting
e.g. rotating secrets       e.g. performance reviews    e.g. capacity planning

Bad: scales with load       Unavoidable, manage it      Good: reduces future toil
Goal: automate it away      Keep it reasonable          Goal: maximize this
```

**Overhead is not toil.** You can't automate your way out of team meetings. Toil specifically refers to operational work that *can* be automated but hasn't been yet.

---

## Why Toil Is a Problem

### It's a trap

Toil feels productive — you're responding, fixing, keeping the lights on. But it provides no lasting value. Every hour spent on toil is an hour not spent on engineering work that would reduce future toil.

```
High toil team:
  Week 1: 20 hours toil, 20 hours engineering
  Week 2: 20 hours toil, 20 hours engineering  ← same toil, no improvement
  Month 6: still 20 hours toil/week — it never got better

Low toil team:
  Week 1: 20 hours toil, 20 hours engineering (building autoscaler)
  Week 4: 10 hours toil, 30 hours engineering (autoscaler shipped)
  Month 6: 3 hours toil/week — compounding improvement
```

### It causes burnout

On-call engineers drowning in toil have no time to fix the systems causing the toil. This creates a vicious cycle: toil → no time to fix → more toil → burnout → attrition.

### It masks real problems

If engineers are manually restarting pods 10 times a day, they get numb to it. The real problem (why does this pod keep crashing?) never gets investigated.

### It doesn't scale

If your service grows 10x, manual operations work grows 10x. You cannot hire your way out of this.

---

## The 50% Rule

**SRE teams at Google aim to spend no more than 50% of their time on toil.**

The other 50% must be engineering work — projects that improve reliability, reduce toil, or add new capabilities.

Why 50%? Because:
- Below 50% toil: team can make meaningful progress on reliability improvements
- Above 50% toil: team is in "survival mode", improvements never happen, burnout follows

If an SRE team consistently exceeds 50% toil, this is a management signal:
1. The service is not production-ready
2. The team is understaffed
3. Engineering work is being deprioritized

In practice, the 50% number requires measurement — which means tracking time spent on toil vs engineering work explicitly.

---

## How to Identify Toil

Ask these questions about any recurring task:

1. **Would a machine do this the same way every time?** → Toil candidate
2. **Does doing this once make it less likely you'll need to do it again?** → If no, it's toil
3. **Does this work grow when your service load grows?** → Toil
4. **Is this triggered by a page or ticket, not a human decision?** → Likely toil
5. **Could you write a runbook for this, and then automate the runbook?** → Definitely toil

### Common Examples of Toil in DevOps/SRE

**Kubernetes/Infrastructure:**
- Manually restarting crashed pods
- Manually scaling deployments when load spikes
- Manually rotating TLS certificates
- Manually provisioning new namespaces with the same boilerplate
- Manually adjusting resource limits on pods

**CI/CD:**
- Manually triggering deploys that could be automated
- Manually approving pipeline stages that have no real review
- Manually cleaning up old image tags from a registry

**Secrets management:**
- Manually rotating database passwords
- Manually copying secrets between environments
- Manually distributing API keys to new services

**Monitoring:**
- Manually acknowledging the same alert every morning
- Manually looking up the same dashboard for every incident
- Manually correlating logs from three different systems

**User requests:**
- Manually provisioning cloud resources for developers
- Manually creating service accounts
- Manually resetting user permissions

---

## How to Eliminate Toil

### The Toil Elimination Ladder

```
Level 0: Toil exists, no documentation
Level 1: Toil is documented (runbook written)
Level 2: Toil is partially automated (runbook is a script)
Level 3: Toil is fully automated (script runs automatically)
Level 4: The underlying cause is fixed (no toil at all)
```

Most teams stop at Level 1 or 2. The goal is Level 3 or 4.

### Strategies

**1. Automate the runbook**
Every runbook is a candidate for automation. If you can write the steps down, you can write a script.

**2. Self-healing systems**
Use Kubernetes liveness/readiness probes to restart failing pods automatically.
Use autoscalers to handle load spikes without human intervention.

**3. Self-service platforms**
Instead of handling manual requests (create namespace, provision DB), build a platform that developers can use themselves.
This eliminates an entire class of toil: the ticket-based request.

**4. Fix the root cause**
If you're restarting a pod 10x/day, the real fix is fixing the pod.
Automation is a band-aid; root cause elimination is the cure.

**5. Push toil back to developers**
If a service is generating so much toil that it consumes SRE capacity, the SRE team can hand it back to the dev team (with the Google model).
This creates the right incentive: developers who feel operational pain will fix reliability.

**6. Eliminate unnecessary alerting**
Alerts that fire for things you can't act on or that resolve themselves are toil.
Every alert should require a human decision. If it doesn't, it should be automatic or deleted.

---

## Measuring Toil

You can't manage what you don't measure. Track:

```
Weekly:
  - Hours spent on toil (by category)
  - Number of tickets that are toil
  - Number of pages that are toil (vs actionable alerts)

Monthly:
  - % of team time spent on toil
  - Toil trend (is it growing or shrinking?)
  - Top 3 toil sources

Quarterly:
  - Toil projects completed
  - Estimated hours saved by automation
  - Remaining toil backlog
```

### Toil Tracking Template

| Task | Category | Time spent | Frequency | Automatable? | Priority |
|------|----------|-----------|-----------|-------------|----------|
| Restart crashing pods | K8s | 30 min/day | Daily | Yes | High |
| Rotate DB password | Secrets | 2 hr/quarter | Quarterly | Yes | Medium |
| Provision new dev env | Platform | 3 hr/request | 2x/week | Yes | High |
| Attend incident bridge | Incident | Varies | On-call | No (overhead) | N/A |

---

## Interview Questions on Toil

**Q: What is toil in SRE?**
A: Toil is manual, repetitive, automatable operational work that scales with service load and provides no enduring value. Examples: manually restarting pods, manually rotating certificates, manually provisioning environments. SRE teams aim to keep toil below 50% of their time.

**Q: What's the difference between toil and overhead?**
A: Toil can be automated (it's operational work done manually). Overhead is necessary non-engineering work like meetings and reviews — it can't be automated away, but it also doesn't scale with service load. Both take time, but toil is the one you can eliminate.

**Q: How do you prioritize which toil to eliminate first?**
A: By impact: frequency × time per occurrence. High-frequency tasks that each take little time can add up to more total toil than rare but lengthy ones. Also prioritize toil that causes on-call pages or directly impacts reliability, since that has the highest cost.

**Q: What happens if an SRE team's toil exceeds 50%?**
A: It's a red flag that requires management attention. Either the service is not production-ready (SRE should require reliability improvements from the dev team), the team is understaffed, or engineering work is being systematically de-prioritized. Left unaddressed, it leads to burnout and attrition.
