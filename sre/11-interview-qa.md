# SRE Interview Q&A — Common Questions with Full Answers

## How to Use This File

These questions span junior to senior level. For each answer:
- The **short answer** is what you say in the first 30 seconds
- The **depth** is what you add if they probe further
- The **signal** is what the interviewer is actually assessing

---

## Section 1: Core Concepts

### Q1: What is SRE and how does it differ from DevOps?

**Short answer:**
SRE is a specific implementation of DevOps principles, invented at Google. DevOps is a cultural philosophy — break the wall between dev and ops. SRE is the concrete implementation: hire software engineers to do operations, give them SLOs, error budgets, and a charter to automate operational work away.

**Key differences:**
- DevOps is broad and cultural; SRE is prescriptive with specific practices
- DevOps says "collaborate and move fast"; SRE adds quantitative reliability management via SLOs and error budgets
- SRE explicitly caps toil at 50% of team time; DevOps has no equivalent constraint
- Google frames it as: "SRE is what you get when you treat operations as a software problem"

**Signal:** Interviewer is checking if you understand SRE is not just a rebranding of DevOps, and that you know the specific mechanisms (SLOs, error budgets, toil) that make SRE distinctive.

---

### Q2: Explain SLI, SLO, and SLA. What's the relationship between them?

**Short answer:**
SLI is the metric (e.g. % of successful HTTP requests). SLO is the internal target for that metric (e.g. 99.9% over 28 days). SLA is the external contract with consequences (e.g. promise 99.5% to customers, refund if breached).

**The relationship:**
```
SLI: what you measure
SLO: what you aim for (tighter than SLA)
SLA: what you promise externally (looser than SLO, with consequences)

SLO must be more aggressive than SLA to give a buffer.
If SLO = 99.95%, SLA can safely promise 99.9%.
If SLO is breached but SLA isn't yet → engineering urgency, no customer impact.
If SLA is breached → customer compensation, serious business event.
```

**Signal:** Tests foundational SRE knowledge. Many people mix up SLO and SLA. Getting the buffer relationship right (SLO tighter than SLA) signals you've thought about this in practice.

---

### Q3: What is an error budget and why does it matter?

**Short answer:**
An error budget is the allowed unreliability derived from the SLO: `error budget = 1 - SLO`. A 99.9% SLO has a 0.1% error budget — about 43 minutes/month of allowed downtime.

**Why it matters:**
It resolves the eternal dev vs ops conflict. Instead of developers wanting to ship fast and ops wanting stability, both teams look at the same number. Budget remaining → ship freely. Budget nearly exhausted → slow down and focus on reliability. Budget gone → feature freeze, reliability work only. The math decides, not politics.

**Signal:** Interviewer wants to know if you understand the cultural/organizational value of error budgets, not just the math. The "resolves dev vs ops conflict" framing signals maturity.

---

### Q4: Why shouldn't you target 100% availability?

**Short answer:**
Because it's unachievable and creates perverse incentives. No system is 100% reliable. Chasing 100% would mean never deploying (deployments risk errors), which contradicts the purpose of engineering. A meaningful error budget (e.g. 0.1%) allows controlled risk-taking.

**Additionally:**
99.99% and 100% are indistinguishable to users. Users don't notice sub-second outages or single failed requests. Setting an SLO too high just creates anxiety without delivering real user value.

**The math argument:** Going from 99.9% to 99.99% requires massive engineering investment. Going from 99.99% to 99.999% requires even more. The marginal reliability improvement shrinks while the cost grows exponentially.

---

### Q5: What is toil? Give examples.

**Short answer:**
Toil is manual, repetitive, automatable operational work that scales with service load and provides no lasting value. Key property: doing it once doesn't reduce the chance you'll need to do it again.

**Examples:**
- Manually restarting crashed pods
- Rotating TLS certificates by hand
- Provisioning new dev environments via ticket
- Manually scaling deployments during load spikes
- Acknowledging the same alert every morning that always resolves itself

**The 50% rule:** SRE teams target no more than 50% of time on toil. Above that, no engineering work happens, reliability doesn't improve, and the team burns out.

**What's NOT toil:** Team meetings, performance reviews, hiring interviews — that's overhead. It can't be automated away, but it doesn't scale with load either.

---

## Section 2: Incident Management

### Q6: Walk me through how you'd handle a production outage.

**Short answer (structured response):**

1. **Acknowledge** — respond to the alert within the on-call SLA (e.g. 5 minutes)
2. **Triage** — assess impact quickly: how many users? what's broken? set severity
3. **Mobilize** — open incident channel, declare IC, add responders based on severity
4. **Communicate** — post first status page update ("investigating"), notify support team
5. **Investigate** — hypothesis-driven: what changed recently? correlate with timeline
6. **Mitigate** — restore service (often: rollback recent deploy)
7. **Confirm resolution** — verify metrics back to baseline, update status page
8. **Follow up** — open postmortem within 24 hours

**Key signal to give:** Separate mitigation from resolution. Mitigation = restore service fast (rollback). Resolution = fix root cause properly (may take hours or days).

---

### Q7: What is a blameless postmortem?

**Short answer:**
A postmortem that focuses on systems and processes rather than individual mistakes. The core belief: "human error" is never a root cause — it's a symptom of a system that made the mistake easy to make.

**Why blameless:**
Blame culture causes engineers to hide mistakes, produces incomplete timelines, and results in no real systemic fixes. The same incident recurs. Blameless culture produces honest timelines, systemic root causes, and action items that actually improve the system.

**In practice:**
"Engineer ran the wrong command" → bad root cause (nothing fixed).
"No safeguard existed to prevent destructive commands in production" → good root cause (add the safeguard, all future engineers protected).

**Signal:** Interviewers love this question because it reveals whether you think about systems or people. Always frame root cause analysis as finding system conditions, not assigning blame.

---

### Q8: What's the difference between MTTR and MTBF?

**Short answer:**
- **MTTR** (Mean Time To Recovery): average time from incident detection to service restoration. Measures how fast you recover.
- **MTBF** (Mean Time Between Failures): average time between incidents. Measures how often you fail.

**The SRE tradeoff:**
- Reduce MTBF (make failures less frequent) → reliability engineering, fewer bugs, better testing
- Reduce MTTR (recover faster) → better alerting, runbooks, automation, DR rehearsals

For high-reliability systems, work on both — but MTTR is often more actionable in the short term. You can't prevent all failures, but you can always get faster at recovering.

---

### Q9: What is alert fatigue and how do you fix it?

**Short answer:**
Alert fatigue is when engineers stop taking alerts seriously because too many alerts fire for non-actionable or auto-resolving conditions. Result: real incidents get ignored, response is slow.

**Fix:**
Audit every alert with these questions:
- Does this require a human decision? (if no → automate or delete)
- Is this actionable right now? (if no → not an alert)
- Does this resolve by itself? (if yes → tune or delete)
- Has this alert fired more than once in 30 days without any action? → review

**Target:** >80% of alerts should be actionable. Track "alert noise ratio" over time.

**The deeper principle:** Every alert that fires at 3am must be worth waking someone up. If it's not, it shouldn't fire at 3am. Use business hours routing for lower severity alerts.

---

## Section 3: Reliability Patterns

### Q10: What is a circuit breaker? When would you use one?

**Short answer:**
A circuit breaker monitors calls to a dependency. When failure rate exceeds a threshold, it trips to OPEN state and immediately returns errors without calling the dependency — protecting the caller from cascading failures. After a timeout it moves to HALF-OPEN to test recovery.

**States:**
- CLOSED: normal, requests pass through
- OPEN: dependency failing, fail fast without calling it
- HALF-OPEN: test if dependency recovered

**Use it when:** Service A calls Service B, and B going slow/down could exhaust A's threads or connections, causing A to fail too. The circuit breaker contains the failure to B without taking down A.

---

### Q11: What is chaos engineering? Give an example experiment.

**Short answer:**
Deliberately injecting failures into systems to find weaknesses before they cause real incidents. The premise: production will eventually fail in these ways — better to find out during a controlled experiment.

**Example experiment:**
Hypothesis: "If one replica of the checkout service is killed, the system will self-heal within 30 seconds and SLO will be maintained."
Experiment: `kubectl delete pod checkout-api-<random-suffix>`
Observe: Does traffic reroute immediately? Does HPA spin up a replacement? Does error rate spike above SLO threshold?
If yes → hypothesis confirmed, system is resilient.
If no → fix the gap (tune PDB, fix HPA response time, improve readiness probe).

**Safety rules:** Start in staging. Have a kill switch. Run during business hours. Small blast radius first.

---

### Q12: What is the difference between a canary and blue-green deployment?

**Short answer:**
- **Blue-green:** full switch from old (blue) to new (green) all at once. Rollback = switch back.
- **Canary:** gradually increase traffic to new version (1% → 10% → 50% → 100%). Data-driven decision to proceed or rollback at each step.

**When to use which:**
- Blue-green: need instant full rollback capability, simpler to implement, good when you have confidence in the new version
- Canary: risky changes, need to validate on real traffic before full rollout, want SLO-based automatic rollback

**Risk difference:**
Blue-green has binary blast radius (0% or 100%). Canary has gradual blast radius (start at 1%). For high-risk deploys, canary is safer.

---

## Section 4: Kubernetes and Cloud

### Q13: What is a PodDisruptionBudget and why does it matter for SLOs?

**Short answer:**
A PDB sets the minimum number of pods that must remain available during voluntary disruptions (node drains, cluster upgrades). Without a PDB, Kubernetes can evict all pods of a deployment simultaneously during maintenance, causing a complete outage.

**SLO relevance:**
If you have 3 replicas and a node drain evicts all 3 at once, you burn your entire monthly error budget in minutes. A PDB with `minAvailable: 2` ensures Kubernetes drains one pod at a time — maintaining availability and protecting the SLO.

**Rule:** Every production service with multiple replicas needs a PDB.

---

### Q14: How do you implement SLO alerting in Prometheus?

**Short answer:**
Use burn rate alerting rather than raw SLO breach alerting.

**Why:** If your SLO is 99.9% over 28 days and you have a slow error leak of 0.11%, it takes weeks before the 28-day SLO is breached — but you're burning budget the whole time. By then it's too late.

**Burn rate alerting:**
- Fast burn (burn rate > 14x): page immediately — you'll exhaust the budget in < 2 days
- Slow burn (burn rate > 3x sustained): create a warning ticket

```promql
# Fast burn alert
sum(rate(http_requests_total{status=~"5..", job="checkout"}[1h]))
/
sum(rate(http_requests_total{job="checkout"}[1h]))
> (14 * 0.001)   # 14x the 0.1% error budget
```

---

## Section 5: Culture and Process

### Q15: How do you build a culture of reliability without slowing down delivery?

**Short answer:**
With error budgets. The error budget is the mechanism that makes the tradeoff explicit. When budget is healthy, ship fast. When budget is low, slow down. Neither dev nor ops "wins" — the number decides.

**Supporting practices:**
- Production readiness reviews before new services get SRE support
- Automated canary deployments with SLO-based rollback
- Postmortems that produce systemic fixes (not blame)
- Runbooks and chaos testing that give teams confidence to ship

**The framing:** Reliability is not the enemy of velocity. Unreliability is. An unreliable system causes incidents that consume more engineering time than careful deployment practices.

---

### Q16: A service is burning its error budget faster than expected. What do you do?

**Short answer:**

1. **Immediately:** check if there's an active incident. Is this burn from one event or a slow leak?
2. **If active incident:** follow incident response process, page on-call
3. **If slow burn:** investigate root cause — what's causing the elevated error rate?
4. **Error budget policy:** check what the policy says at the current budget level (feature freeze? caution zone?)
5. **Communication:** inform product team of budget status
6. **Action:** fix the root cause. If budget < 10%, enforce freeze until root cause is fixed
7. **Postmortem:** once resolved, document what caused the burn and what was fixed

**Signal:** Interviewers want to see structured thinking: detect → assess → communicate → fix → learn. Not just "fix the bug."

---

### Q17: How do you prioritize reliability work vs feature work?

**Short answer:**
With the error budget. The error budget makes this an engineering decision, not a political one.

**Framework:**
- Error budget healthy (> 50%): feature work takes priority, reliability work scheduled
- Error budget low (10-25%): reliability work and features share priority
- Error budget near-exhausted (< 10%): reliability work takes priority, features paused
- Budget exhausted: feature freeze, 100% reliability focus

**For systemic reliability investments** (not incident-driven):
Use the 50% toil cap: if toil > 50%, reliability engineering is mandatory, not optional.

**The conversation with stakeholders:**
"Our checkout SLO budget is at 12%. Per our error budget policy, we're pausing new features until we identify and fix the source of the budget burn. This protects us from breaching the SLA and triggering customer credits."

---

## Quick Reference: SRE Terminology Cheat Sheet

| Term | Definition |
|------|-----------|
| SLI | Metric measuring reliability (e.g. % successful requests) |
| SLO | Internal reliability target (e.g. 99.9%) |
| SLA | External contract with consequences if SLO breached |
| Error budget | Allowed unreliability = 1 - SLO |
| Burn rate | How fast error budget is consumed vs expected rate |
| Toil | Manual, repetitive, automatable operational work |
| Postmortem | Blameless analysis of incident cause and prevention |
| MTTR | Mean Time To Recovery |
| MTBF | Mean Time Between Failures |
| MTTD | Mean Time To Detect |
| Circuit breaker | Pattern to stop calls to a failing dependency |
| Canary | Gradual traffic shift to new version for safe deploys |
| Chaos engineering | Deliberate failure injection to find weaknesses |
| PDB | PodDisruptionBudget — minimum available pods during disruptions |
| HPA | HorizontalPodAutoscaler — auto-scale based on metrics |
| RTO | Recovery Time Objective — how fast to restore service |
| RPO | Recovery Point Objective — maximum acceptable data loss |
