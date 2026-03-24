# 🔭 Tracing Deep Dive

Follow requests across microservices and find exactly where things slow down or break.

> **Prerequisites:** Completed [02-tooling-setup.md](./02-tooling-setup.md). A running Kubernetes cluster with `helm` available.

---

## 📚 Table of Contents

- [The Big Picture](#the-big-picture)
- [1. Tracing Concepts](#1-tracing-concepts)
- [2. OpenTelemetry — The Standard](#2-opentelemetry--the-standard)
- [3. Jaeger — The Backend](#3-jaeger--the-backend)
- [4. Instrument Your App](#4-instrument-your-app)
- [5. View Traces in Jaeger](#5-view-traces-in-jaeger)
- [6. Connect Traces to Grafana](#6-connect-traces-to-grafana)
- [Tracing Cheatsheet](#tracing-cheatsheet)

---

## The Big Picture

Metrics tell you *something is slow*. Logs tell you *an error happened*. Traces tell you *exactly which service, in which call, took how long*.

```
User Request
     │
     ▼
 [API Gateway]  ──── span: 120ms
     │
     ▼
 [Auth Service] ──── span: 8ms
     │
     ▼
 [Order Service] ─── span: 95ms   ← bottleneck
     │
     ▼
 [Database]      ──── span: 90ms  ← root cause
```

Each step in the chain is a **span**. All spans for a single request together form a **trace**.

---

## 1. Tracing Concepts

| Term | What it means |
|------|--------------|
| **Trace** | The full journey of one request through your system |
| **Span** | A single unit of work within a trace (one service call, one DB query) |
| **Trace ID** | A unique ID shared by all spans in the same request |
| **Span ID** | A unique ID for one specific span |
| **Parent span** | The span that triggered the current one |
| **Context propagation** | Passing the Trace ID between services (via HTTP headers) |
| **Instrumentation** | The code you add to your app to create spans |
| **Sampling** | Only recording a % of traces to reduce overhead |

### How context propagation works

```
Service A calls Service B:

  HTTP Request Headers:
    traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
                     │                │                    │
                  version          trace-id              span-id
```

Every service reads this header, creates a child span, and passes the header on. This is how one trace ID links spans across many services.

---

## 2. OpenTelemetry — The Standard

OpenTelemetry (OTel) is the open-source standard for generating traces, metrics, and logs. It's vendor-neutral — you instrument your app once, then send data to any backend (Jaeger, Grafana Tempo, Datadog, etc.).

### Key components

```
Your App
  │
  │  OTel SDK (in your code)
  │  generates spans
  ▼
OTel Collector (runs as a pod)
  │  receives, processes, exports
  ▼
Jaeger (or any backend)
```

### Install the OTel Collector

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  --set mode=deployment
```

### Basic OTel Collector config

```yaml
# otel-collector-config.yaml
config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317    # apps send traces here
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:                           # batch spans before exporting (saves resources)
      timeout: 1s
      send_batch_size: 1024

  exporters:
    jaeger:
      endpoint: jaeger-collector:14250
      tls:
        insecure: true

  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [jaeger]
```

Apply it:

```bash
helm upgrade otel-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  -f otel-collector-config.yaml
```

---

## 3. Jaeger — The Backend

Jaeger stores traces and gives you a UI to search, filter, and visualize them.

### Install Jaeger

```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo update

helm install jaeger jaegertracing/jaeger \
  --namespace monitoring \
  --set provisionDataStore.cassandra=false \
  --set allInOne.enabled=true \
  --set storage.type=memory        # fine for dev/learning, use Elasticsearch in prod
```

> 💡 `allInOne` mode runs the collector, query, and UI in a single pod. Perfect for local learning. In production you'd run these separately with persistent storage.

### Verify it's running

```bash
kubectl get pods -n monitoring | grep jaeger
```

### Access the Jaeger UI

```bash
kubectl port-forward svc/jaeger-query 16686:16686 -n monitoring
```

Open [http://localhost:16686](http://localhost:16686)

You'll see a search UI — once your app is sending traces, they'll appear here.

---

## 4. Instrument Your App

This is where traces actually come from — your application code. OTel SDKs are available for most languages.

### Go

```go
package main

import (
    "context"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
)

func initTracer() (*trace.TracerProvider, error) {
    exporter, err := otlptracegrpc.New(context.Background(),
        otlptracegrpc.WithEndpoint("otel-collector:4317"),
        otlptracegrpc.WithInsecure(),
    )
    if err != nil {
        return nil, err
    }

    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),
        trace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceNameKey.String("my-service"),
        )),
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}

// Create a span in your handler
func handleRequest(ctx context.Context) {
    tracer := otel.Tracer("my-service")
    ctx, span := tracer.Start(ctx, "handleRequest")
    defer span.End()

    // your logic here
    callDatabase(ctx)  // child spans will attach to this one automatically
}
```

### Python

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Setup
provider = TracerProvider()
exporter = OTLPSpanExporter(endpoint="otel-collector:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer("my-service")

# Use in your code
def handle_request():
    with tracer.start_as_current_span("handle_request") as span:
        span.set_attribute("user.id", "42")
        span.set_attribute("http.method", "GET")
        call_database()   # child spans attach automatically
```

### Auto-instrumentation (no code changes needed)

OTel supports auto-instrumentation for common frameworks — it patches libraries automatically so you get traces without touching your app code.

```bash
# Python example with auto-instrumentation
pip install opentelemetry-distro opentelemetry-exporter-otlp
opentelemetry-bootstrap --action=install

# Run your app with auto-instrumentation
opentelemetry-instrument \
  --traces-exporter otlp \
  --exporter-otlp-endpoint http://otel-collector:4318 \
  python app.py
```

For Kubernetes, use the **OTel Operator** to inject auto-instrumentation via annotations — no code changes at all:

```yaml
# Add this annotation to your Deployment pod spec
annotations:
  instrumentation.opentelemetry.io/inject-python: "true"
  # or: inject-go, inject-java, inject-nodejs
```

---

## 5. View Traces in Jaeger

Once your app is sending traces, go to [http://localhost:16686](http://localhost:16686).

### Search for traces

1. Select your **Service** from the dropdown
2. Set a time range
3. Click **Find Traces**

### Reading a trace

```
Trace: handleRequest  (total: 120ms)
├── handleRequest           [API Gateway]     120ms
│   ├── authenticateUser    [Auth Service]      8ms
│   └── processOrder        [Order Service]    95ms
│       └── db.query        [PostgreSQL]       90ms  ← slowest span
```

Click any span to see:
- **Duration** — how long it took
- **Tags** — attributes you set (user ID, HTTP method, status code)
- **Logs** — events within the span (errors, checkpoints)
- **Process** — which service/host produced it

### What to look for

| Symptom | What it tells you |
|---------|------------------|
| One span much longer than others | Bottleneck in that service |
| Many sequential DB spans | N+1 query problem |
| Span ends with error tag | Where the failure actually occurred |
| Large gap between spans | Network latency or queuing delay |
| Trace stops mid-chain | A service isn't instrumented or propagating context |

---

## 6. Connect Traces to Grafana

Grafana can display Jaeger traces directly — and link between metrics, logs, and traces in one view.

### Add Jaeger as a data source

1. Go to **Connections → Data Sources → Add data source**
2. Select **Jaeger**
3. Set URL to: `http://jaeger-query:16686`
4. Click **Save & Test** ✅

### Link Loki logs to traces

Add this to your Loki data source config in Grafana to make log lines clickable — opening the related trace:

```yaml
derivedFields:
  - name: TraceID
    matcherRegex: "traceID=(\\w+)"   # matches traceID in your log lines
    url: "$${__value.raw}"
    datasourceUid: jaeger            # your Jaeger data source UID
```

Now when you see a log line like `traceID=4bf92f3577b34da6`, you can click it and jump straight to the trace in Jaeger.

### Link Prometheus metrics to traces (Exemplars)

Exemplars attach a trace ID to a specific metric data point — so you can go from a spike on a graph directly to the trace that caused it.

```go
// In your Go app, record an exemplar
histogram.With(prometheus.Labels{"method": "GET"}).
    ObserveWithExemplar(duration, prometheus.Labels{
        "traceID": span.SpanContext().TraceID().String(),
    })
```

In Grafana, enable exemplars on your Prometheus data source and they'll appear as dots on your graphs — click one to open the trace.

---

## Tracing Cheatsheet

```bash
# Port-forward Jaeger UI
kubectl port-forward svc/jaeger-query 16686:16686 -n monitoring

# Port-forward OTel Collector (for local app testing)
kubectl port-forward svc/otel-collector 4317:4317 -n monitoring

# Check OTel Collector logs
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Check Jaeger logs
kubectl logs -n monitoring -l app.kubernetes.io/name=jaeger

# Verify OTel Collector is receiving spans
kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector | grep "TracesExporter"

# List all OTel instrumentation resources (if using OTel Operator)
kubectl get instrumentation -A
```

### Sampling strategies

Don't record 100% of traces in production — it's expensive. Common strategies:

| Strategy | How it works | When to use |
|----------|-------------|-------------|
| **Head sampling** | Decide at the start of a request | Simple, low overhead |
| **Tail sampling** | Decide after the trace completes | Keeps slow/error traces, drops fast ones |
| **Rate limiting** | Record max N traces/second | Predictable volume |

```yaml
# Tail sampling in OTel Collector — keep errors and slow requests
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: keep-errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: keep-slow
        type: latency
        latency: { threshold_ms: 500 }
      - name: sample-rest
        type: probabilistic
        probabilistic: { sampling_percentage: 10 }
```

---
