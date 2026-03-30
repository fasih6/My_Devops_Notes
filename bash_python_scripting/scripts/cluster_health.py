#!/usr/bin/env python3
"""
cluster_health.py — Kubernetes cluster health checker

Usage:
    python cluster_health.py -n production
    python cluster_health.py -n production --slack-webhook $SLACK_WEBHOOK --fail-on-issues
"""
import argparse, json, logging, os, subprocess, sys, time
from dataclasses import dataclass, field

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)


@dataclass
class Issue:
    severity: str   # critical | warning
    where: str
    what: str


@dataclass
class Health:
    namespace: str
    issues: list[Issue] = field(default_factory=list)
    pods_total: int = 0
    pods_running: int = 0

    @property
    def ok(self) -> bool:
        return not any(i.severity == "critical" for i in self.issues)


def kube(cmd: list[str]) -> dict:
    r = subprocess.run(["kubectl"] + cmd, check=True, capture_output=True, text=True)
    return json.loads(r.stdout)


def check(namespace: str) -> Health:
    h = Health(namespace=namespace)

    pods = kube(["get", "pods", "-n", namespace, "-o", "json"])["items"]
    h.pods_total   = len(pods)
    h.pods_running = sum(1 for p in pods if p["status"].get("phase") == "Running")

    for pod in pods:
        name  = pod["metadata"]["name"]
        phase = pod["status"].get("phase", "Unknown")
        if phase not in ("Running", "Succeeded"):
            h.issues.append(Issue("critical", f"pod/{name}", f"phase={phase}"))
        for cs in pod["status"].get("containerStatuses") or []:
            r = cs.get("restartCount", 0)
            if r > 10:
                h.issues.append(Issue("critical", f"pod/{name}", f"{cs['name']}: {r} restarts"))
            elif r > 5:
                h.issues.append(Issue("warning", f"pod/{name}", f"{cs['name']}: {r} restarts"))

    for dep in kube(["get", "deployments", "-n", namespace, "-o", "json"])["items"]:
        name    = dep["metadata"]["name"]
        desired = dep["spec"].get("replicas", 1)
        ready   = dep["status"].get("readyReplicas", 0)
        if ready < desired:
            sev = "critical" if ready == 0 else "warning"
            h.issues.append(Issue(sev, f"deploy/{name}", f"{ready}/{desired} ready"))

    return h


def notify_slack(webhook: str, h: Health) -> None:
    try:
        import urllib.request
        color = "good" if h.ok else "danger"
        summary = (f"OK — {h.pods_running}/{h.pods_total} pods running"
                   if h.ok else f"DEGRADED — {len(h.issues)} issue(s)")
        fields = [{"title": i.where, "value": i.what, "short": False}
                  for i in h.issues[:10]]
        payload = json.dumps({"attachments": [{
            "color": color, "title": f"Cluster Health: {h.namespace}",
            "text": summary, "fields": fields,
            "footer": "cluster_health.py", "ts": int(time.time()),
        }]}).encode()
        req = urllib.request.Request(webhook, data=payload,
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=5)
        log.info("Slack notification sent")
    except Exception as e:
        log.warning("Slack notification failed: %s", e)


def main() -> int:
    parser = argparse.ArgumentParser(description="Kubernetes cluster health check")
    parser.add_argument("-n", "--namespace", default="default")
    parser.add_argument("--slack-webhook", default=os.environ.get("SLACK_WEBHOOK"))
    parser.add_argument("--fail-on-issues", action="store_true")
    args = parser.parse_args()

    h = check(args.namespace)

    for issue in h.issues:
        fn = log.error if issue.severity == "critical" else log.warning
        fn("[%s] %s — %s", issue.severity.upper(), issue.where, issue.what)

    status = f"{h.pods_running}/{h.pods_total} pods running"
    if h.ok:
        log.info("Healthy — %s", status)
    else:
        log.error("DEGRADED — %s — %d issue(s)", status, len(h.issues))

    if args.slack_webhook:
        notify_slack(args.slack_webhook, h)

    return 1 if (args.fail_on_issues and not h.ok) else 0


if __name__ == "__main__":
    sys.exit(main())
