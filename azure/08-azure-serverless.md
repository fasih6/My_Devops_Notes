# Azure Serverless — Functions, Logic Apps, Service Bus & More ⚡

> Part of my DevOps journey — azure folder

---

## Azure Functions (≈ AWS Lambda)

Run code without managing servers. Triggered by events. Supports: C#, JavaScript/TypeScript, Python, Java, PowerShell, custom handlers.

### Hosting Plans

| Plan | Cold start | Scale | Cost |
|------|-----------|-------|------|
| **Consumption** | Yes | Auto, pay per execution | Cheapest |
| **Flex Consumption** | Reduced | Auto with pre-provisioned instances | Mid |
| **Premium** | No | Pre-warmed, VNet support | Fixed + per-execution |
| **Dedicated (App Service)** | No | Manual/auto-scale | Fixed (App Service) |

```bash
# Create Function App
az functionapp create \
  --name myapp-functions \
  --resource-group myapp-prod-rg \
  --storage-account myappstorageprod \
  --consumption-plan-location eastus \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --os-type Linux

# Or Premium plan (VNet, no cold start)
az functionapp plan create \
  --name myapp-func-plan \
  --resource-group myapp-prod-rg \
  --location eastus \
  --sku EP1 \
  --is-linux

az functionapp create \
  --name myapp-functions \
  --resource-group myapp-prod-rg \
  --plan myapp-func-plan \
  --storage-account myappstorageprod \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4

# Configure app settings
az functionapp config appsettings set \
  --name myapp-functions \
  --resource-group myapp-prod-rg \
  --settings "DATABASE_URL=@Microsoft.KeyVault(SecretUri=...)" \
             "NODE_ENV=production"

# Deploy code (via zip deploy)
func azure functionapp publish myapp-functions

# View logs
az functionapp log tail \
  --name myapp-functions \
  --resource-group myapp-prod-rg

# Enable managed identity
az functionapp identity assign \
  --name myapp-functions \
  --resource-group myapp-prod-rg
```

### Function Example (Python)

```python
# function_app.py
import azure.functions as func
import logging
import json

app = func.FunctionApp()

# HTTP trigger
@app.route(route="hello", methods=["GET", "POST"])
def hello(req: func.HttpRequest) -> func.HttpResponse:
    name = req.params.get('name') or req.get_json().get('name', 'World')
    return func.HttpResponse(f"Hello, {name}!", status_code=200)

# Timer trigger (runs every 5 minutes)
@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer")
def cleanup_job(timer: func.TimerRequest) -> None:
    logging.info("Running scheduled cleanup...")

# Blob trigger (runs when file uploaded to storage)
@app.blob_trigger(arg_name="blob", path="uploads/{name}", connection="AzureWebJobsStorage")
def process_upload(blob: func.InputStream) -> None:
    logging.info(f"Processing blob: {blob.name}, size: {blob.length}")

# Service Bus trigger
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="orders",
    connection="ServiceBusConnection"
)
def process_order(msg: func.ServiceBusMessage) -> None:
    order = json.loads(msg.get_body().decode('utf-8'))
    logging.info(f"Processing order: {order['id']}")
```

### Common Triggers & Bindings

```
Triggers (input):
  HTTP           → REST API / webhook
  Timer          → cron schedule
  Blob Storage   → file uploaded/modified
  Queue Storage  → message in queue
  Service Bus    → Service Bus queue/topic message
  Event Grid     → events from any Azure service
  Event Hub      → streaming data
  Cosmos DB      → document changed (change feed)

Output bindings:
  Blob Storage   → write file to storage
  Table Storage  → write to table
  Service Bus    → send message
  Event Hub      → send event
  Cosmos DB      → write document
  SignalR        → push to connected clients
```

### Durable Functions

Stateful function workflows — long-running, fan-out/fan-in, human interaction.

```python
import azure.durable_functions as df

# Orchestrator function
def orchestrator_function(context: df.DurableOrchestrationContext):
    # Fan-out: run parallel activities
    tasks = [context.call_activity("ProcessItem", item) for item in ["a", "b", "c"]]
    results = yield context.task_all(tasks)

    # Sequential with wait
    approval = yield context.wait_for_external_event("approval_event")
    if approval:
        yield context.call_activity("Finalise", results)

main = df.Orchestrator.create(orchestrator_function)
```

---

## Logic Apps

**Low-code/no-code workflow automation** — connect 1000+ services with a visual designer. Equivalent to AWS Step Functions + EventBridge but drag-and-drop.

```bash
# Create Logic App (Standard)
az logicapp create \
  --name myapp-logic \
  --resource-group myapp-prod-rg \
  --storage-account myappstorageprod \
  --plan myapp-logic-plan \
  --location eastus

# Logic App workflow (JSON definition)
az logicapp deployment source config-zip \
  --name myapp-logic \
  --resource-group myapp-prod-rg \
  --src ./logic-app.zip
```

**Common use cases:**
- Receive email → extract data → insert into database
- New Blob uploaded → call AI service → store results → send Teams notification
- HTTP webhook → transform data → call REST API → log to storage
- Scheduled data export → format → email as attachment

---

## Event Grid (≈ AWS EventBridge)

**Fully managed event routing** — publish events from any source, route to any handler.

```bash
# Create custom Event Grid topic
az eventgrid topic create \
  --name myapp-events \
  --resource-group myapp-prod-rg \
  --location eastus

# Subscribe to Storage Account events (blob created)
az eventgrid event-subscription create \
  --name process-uploads \
  --source-resource-id $(az storage account show \
    --name myappstorageprod -g myapp-prod-rg --query id -o tsv) \
  --included-event-types Microsoft.Storage.BlobCreated \
  --endpoint-type azurefunction \
  --endpoint $(az functionapp function show \
    --name myapp-functions -g myapp-prod-rg \
    --function-name ProcessUpload --query invokeUrlTemplate -o tsv)

# Publish custom event
az eventgrid event publish \
  --topic-endpoint https://myapp-events.eastus-1.eventgrid.azure.net/api/events \
  --aeg-sas-key <key> \
  --events '[{
    "id": "1",
    "subject": "orders/123",
    "eventType": "OrderPlaced",
    "dataVersion": "1.0",
    "data": {"orderId": "123", "customer": "Alice"}
  }]'
```

**Event Grid system topics** — built-in topics for Azure services (Storage, ACR, Service Bus, Resource Manager, etc.). No setup needed — just subscribe.

---

## Service Bus (≈ AWS SQS + SNS)

**Enterprise messaging** — reliable, ordered, transactional message delivery for decoupled microservices.

```bash
# Create Service Bus namespace
az servicebus namespace create \
  --name myapp-servicebus \
  --resource-group myapp-prod-rg \
  --location eastus \
  --sku Premium \
  --zone-redundant true

# Create queue
az servicebus queue create \
  --name orders-queue \
  --namespace-name myapp-servicebus \
  --resource-group myapp-prod-rg \
  --max-size 5120 \
  --default-message-time-to-live P14D \
  --lock-duration PT30S \
  --dead-lettering-on-message-expiration true

# Create topic + subscriptions (pub/sub)
az servicebus topic create \
  --name order-events \
  --namespace-name myapp-servicebus \
  --resource-group myapp-prod-rg

az servicebus topic subscription create \
  --name payments-sub \
  --topic-name order-events \
  --namespace-name myapp-servicebus \
  --resource-group myapp-prod-rg

az servicebus topic subscription create \
  --name inventory-sub \
  --topic-name order-events \
  --namespace-name myapp-servicebus \
  --resource-group myapp-prod-rg

# Get connection string
az servicebus namespace authorization-rule keys list \
  --namespace-name myapp-servicebus \
  --resource-group myapp-prod-rg \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv
```

**Queue vs Topic:**
- **Queue** — point-to-point (one producer, one consumer, competitive consumers)
- **Topic** — pub/sub (one producer, multiple subscribers each get their own copy)

**Service Bus features:**
- FIFO (sessions) — guaranteed ordering per session
- Dead-letter queue — failed messages go here automatically
- Message deferral — defer processing and come back later
- Scheduled messages — send at a future time
- Transactions — atomic send/receive/complete across multiple messages
- Message lock duration — prevents duplicate processing

---

## Event Hubs (≈ AWS Kinesis)

**Big data streaming** — ingest millions of events per second. Think: telemetry, logs, IoT, clickstreams.

```bash
# Create Event Hub namespace
az eventhubs namespace create \
  --name myapp-eventhubs \
  --resource-group myapp-prod-rg \
  --location eastus \
  --sku Standard \
  --capacity 2  # throughput units

# Create Event Hub
az eventhubs eventhub create \
  --name telemetry \
  --namespace-name myapp-eventhubs \
  --resource-group myapp-prod-rg \
  --partition-count 8 \
  --retention-time-in-hours 24

# Get connection string
az eventhubs namespace authorization-rule keys list \
  --namespace-name myapp-eventhubs \
  --resource-group myapp-prod-rg \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv
```

**Event Hubs Capture** — automatically archive events to Azure Blob Storage or Azure Data Lake.

---

## Quick Reference

```bash
# Functions
az functionapp create --name x --consumption-plan-location eastus --runtime python
az functionapp config appsettings set --settings KEY=VALUE
func azure functionapp publish x    # deploy with Core Tools
az functionapp log tail --name x

# Event Grid
az eventgrid topic create --name x
az eventgrid event-subscription create --name x --source-resource-id <id> --endpoint <url>

# Service Bus
az servicebus namespace create --name x --sku Premium
az servicebus queue create --name x --namespace-name x
az servicebus topic create --name x --namespace-name x
az servicebus topic subscription create --name x --topic-name x

# Event Hubs
az eventhubs namespace create --name x --sku Standard
az eventhubs eventhub create --name x --namespace-name x --partition-count 8

Key differences from AWS:
  Functions ≈ Lambda           (event-driven, serverless)
  Logic Apps ≈ Step Functions  (visual workflows, low-code)
  Event Grid ≈ EventBridge     (event routing, 1000+ connectors)
  Service Bus ≈ SQS+SNS        (enterprise messaging, queues+topics)
  Event Hubs ≈ Kinesis         (big data streaming, high throughput)
```
