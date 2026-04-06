# SRE (Site Reliability Engineering) — Index

## What Is SRE?

Site Reliability Engineering is a discipline that applies **software engineering principles to infrastructure and operations problems**. Coined at Google, SRE treats reliability as a feature — one that must be designed, measured, budgeted, and continuously improved.

The core idea: **reliability is not binary**. A system is not simply "up" or "down" — it has a measurable reliability level, and the job of an SRE is to define, track, and protect that level.

## How This Folder Is Organized

| File | Topic | What You'll Learn |
|------|-------|-------------------|
| `01-sre-vs-devops.md` | SRE vs DevOps | Origins, philosophy, how they relate and differ |
| `02-sli-slo-sla.md` | SLI / SLO / SLA | How reliability is measured and contracted |
| `03-error-budgets.md` | Error Budgets | How to balance reliability with velocity |
| `04-toil.md` | Toil | What it is, why it matters, how to eliminate it |
| `05-incident-management.md` | Incident Management | Severity levels, response, communication |
| `06-postmortems.md` | Postmortems | Blameless culture, root cause analysis, follow-ups |
| `07-oncall-runbooks.md` | On-Call & Runbooks | Sustainable on-call, writing good runbooks |
| `08-reliability-patterns.md` | Reliability Patterns | Circuit breakers, canary, chaos engineering |
| `09-sre-with-kubernetes.md` | SRE + Kubernetes | SLOs on K8s, PodDisruptionBudgets, HPA, probes |
| `10-sre-with-azure.md` | SRE + Azure | Azure Monitor, SLOs, availability zones, chaos |
| `11-interview-qa.md` | Interview Q&A | Common SRE interview questions with full answers |

## The SRE Mental Model in One Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    THE SRE LOOP                         │
│                                                         │
│  Define reliability          Measure it                 │
│  (SLI / SLO / SLA)    →     (metrics, dashboards)      │
│          ↑                          ↓                   │
│  Improve systems         React when it breaks           │
│  (reduce toil,      ←    (incidents, postmortems,       │
│   reliability patterns)   on-call, runbooks)            │
│                                                         │
│  Error budget sits in the middle:                       │
│  it decides HOW MUCH you can ship vs stabilize          │
└─────────────────────────────────────────────────────────┘
```

## Key Terms at a Glance

| Term | One-line definition |
|------|---------------------|
| **SLI** | A metric that measures reliability (e.g. request success rate) |
| **SLO** | A target for that metric (e.g. 99.9% success rate) |
| **SLA** | A contract with consequences if SLO is breached |
| **Error budget** | The allowed amount of unreliability within an SLO |
| **Toil** | Manual, repetitive operational work that doesn't improve the system |
| **Incident** | An unplanned disruption to a service |
| **Postmortem** | A blameless analysis of what went wrong and why |
| **Runbook** | Step-by-step operational guide for a known scenario |
| **MTTR** | Mean Time To Recovery — how fast you recover from incidents |
| **MTBF** | Mean Time Between Failures — how often failures happen |
| **Chaos engineering** | Deliberately injecting failures to find weaknesses |
| **Toil budget** | SRE teams aim to keep toil below 50% of working time |

## Why SRE Matters in Interviews

SRE knowledge signals that you:
- Think **quantitatively** about reliability, not just operationally
- Understand the **tension between shipping fast and staying stable**
- Can **communicate reliability** to engineers and business stakeholders
- Know how to **run production** sustainably — on-call without burnout

Even for pure DevOps or Cloud Engineer roles, interviewers increasingly expect SRE fluency.
