# SRE vs DevOps — Origins, Philosophy, and Relationship

## Where SRE Came From

SRE was invented at Google around 2003 by Ben Treynor Sloss. The problem Google faced: as systems scaled massively, traditional sysadmin/ops teams couldn't keep up. Manual operations didn't scale. Reliability became a hard engineering problem.

Treynor's answer: **hire software engineers to do operations, and give them the charter to automate themselves out of operational work.**

The first SRE teams wrote software to manage infrastructure, defined quantitative reliability targets, and treated every operational task as an engineering problem to be solved — not just a ticket to be closed.

## Where DevOps Came From

DevOps emerged around 2008–2009 from the agile community — Patrick Debois, Gene Kim, and others recognized that the wall between Dev and Ops was causing slow, painful deployments.

DevOps is a **cultural and organizational movement**, not a specific job title or methodology. Its core idea: break down silos between development and operations so software can be delivered faster and more reliably.

## The Key Difference

```
DevOps                              SRE
──────────────────────────────────────────────────────
Philosophy / culture               Specific implementation
"Break the wall between Dev & Ops" "Here is how Google does it"
Broad, many implementations        Prescriptive, opinionated
Focus: collaboration & flow        Focus: reliability as engineering
No standard tooling or process     Concrete practices: SLOs, error budgets, toil
Job title varies widely            Defined role with specific responsibilities
```

Google's own framing: **"SRE is what you get when you ask a software engineer to design an operations team."** And: **"SRE is a specific implementation of DevOps."**

They are not competing — SRE is one way to do DevOps well.

## Shared Values

Both SRE and DevOps agree on:

| Value | DevOps framing | SRE framing |
|-------|---------------|-------------|
| Automation | Automate the pipeline | Eliminate toil through code |
| Fast feedback | CI/CD, short cycles | Error budgets, SLO alerting |
| Shared ownership | Devs own operations | Developers share on-call |
| Continuous improvement | Retrospectives | Postmortems |
| Measurement | Metrics, dashboards | SLIs, SLOs, SLAs |

## Where They Differ in Practice

### Reliability targets
- **DevOps**: "We want high availability" — vague, often unmeasured
- **SRE**: "We target 99.9% SLO on our checkout API" — quantified, tracked, budgeted

### Velocity vs reliability tension
- **DevOps**: Assumes fast deployment = good; speed is the goal
- **SRE**: Explicitly manages the tradeoff. Error budgets define HOW FAST you can ship based on current reliability

### Operations work
- **DevOps**: Operations is a shared responsibility; not always quantified
- **SRE**: Toil is explicitly measured and bounded to <50% of time

### Team structure
- **DevOps**: Often means "devs do ops" or "ops learns CI/CD"
- **SRE**: Dedicated SRE team that embeds with product teams, with clear engagement model

## SRE Team Responsibilities

A typical SRE team owns:

```
┌────────────────────────────────────────────┐
│           SRE Responsibilities              │
│                                            │
│  1. Define and track SLOs for services     │
│  2. Own the on-call rotation               │
│  3. Lead incident response                 │
│  4. Conduct postmortems                    │
│  5. Reduce toil through automation         │
│  6. Consult on production readiness        │
│  7. Manage error budget policy             │
│  8. Capacity planning                      │
└────────────────────────────────────────────┘
```

## The SRE Engagement Model

SRE teams don't just take over services blindly. Google defined a model:

**Production Readiness Review (PRR)**
Before a new service gets SRE support, it must pass a PRR:
- Does it have SLIs and SLOs defined?
- Is it observable (metrics, logs, traces)?
- Does it have runbooks for common failure modes?
- Is it automatable (no manual steps to deploy/scale/recover)?

If a service consumes too much SRE time (toil exceeds budget), the SRE team can hand it back to the dev team until reliability improves.

## SRE in the Real World (Outside Google)

At most companies that are not Google scale:
- The "SRE team" is often 2-10 people
- Pure SRE roles are senior (3-5+ years experience expected)
- Many DevOps/Platform roles borrow SRE practices without the full model
- Knowing SRE principles makes you stand out even in DevOps roles

**Common hybrid titles you'll see:**
- Platform Engineer (builds internal platforms, borrows SRE practices)
- DevOps Engineer with SRE responsibilities
- Cloud Infrastructure Engineer + on-call ownership
- Reliability Engineer (same as SRE, different branding)

## The Five Key SRE Concepts (Know These Cold)

| Concept | Why it matters |
|---------|---------------|
| SLI / SLO / SLA | How reliability is defined and measured |
| Error budgets | How reliability and velocity are balanced |
| Toil | What SREs are trying to eliminate |
| Postmortems | How SREs learn from failure without blame |
| On-call | How SREs run sustainable operations |

Each of these has its own file in this folder. Master all five and you can answer almost any SRE interview question.
