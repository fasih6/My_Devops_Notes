# 📝 HCL Language Deep Dive

Syntax, expressions, types, functions, and advanced HCL patterns for real-world Terraform.

---

## 📚 Table of Contents

- [1. HCL Basics](#1-hcl-basics)
- [2. Types & Values](#2-types--values)
- [3. Expressions](#3-expressions)
- [4. Built-in Functions](#4-built-in-functions)
- [5. Meta-Arguments](#5-meta-arguments)
- [6. Dynamic Blocks](#6-dynamic-blocks)
- [7. Conditionals & Loops](#7-conditionals--loops)
- [8. String Templates](#8-string-templates)
- [Cheatsheet](#cheatsheet)

---

## 1. HCL Basics

### Block types

```hcl
# Block syntax
block_type "label1" "label2" {
  argument = value
  nested_block {
    argument = value
  }
}

# Examples
resource "aws_instance" "web" { ... }    # type="resource", labels=["aws_instance","web"]
data "aws_ami" "ubuntu" { ... }          # type="data", labels=["aws_ami","ubuntu"]
module "vpc" { ... }                     # type="module", label=["vpc"]
variable "region" { ... }                # type="variable", label=["region"]
output "instance_ip" { ... }             # type="output", label=["instance_ip"]
locals { ... }                           # type="locals", no label
terraform { ... }                        # type="terraform", no label
provider "aws" { ... }                   # type="provider", label=["aws"]
```

### Comments

```hcl
# Single-line comment

// Also single-line comment

/*
  Multi-line
  comment
*/
```

### References

```hcl
# Reference another resource
resource "aws_subnet" "private" {
  vpc_id = aws_vpc.main.id          # resource_type.resource_name.attribute
}

# Reference a variable
var.region                           # input variable
local.common_tags                    # local value
module.vpc.vpc_id                    # module output
data.aws_ami.ubuntu.id              # data source attribute
path.module                          # path to module directory
path.root                            # path to root module
terraform.workspace                  # current workspace name
```

---

## 2. Types & Values

### Primitive types

```hcl
# string
name = "hello"
name = "hello ${var.suffix}"         # interpolation
name = <<-EOT
  multiline
  string
EOT

# number
port     = 8080
ratio    = 3.14
negative = -5

# bool
enabled  = true
disabled = false
```

### Collection types

```hcl
# list — ordered, same type
availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]

# set — unordered, same type, no duplicates
availability_zones = toset(["eu-central-1a", "eu-central-1b"])

# map — key-value pairs, same value type
tags = {
  Environment = "production"
  Team        = "platform"
  ManagedBy   = "Terraform"
}

# object — key-value pairs, mixed value types
settings = {
  name    = "my-app"
  enabled = true
  count   = 3
  tags    = { env = "prod" }
}

# tuple — ordered, mixed types
mixed = ["name", 42, true]
```

### Type constraints (in variable blocks)

```hcl
variable "port" {
  type = number
}

variable "tags" {
  type = map(string)
}

variable "subnets" {
  type = list(string)
}

variable "config" {
  type = object({
    name    = string
    enabled = bool
    count   = optional(number, 1)   # optional with default
    tags    = optional(map(string), {})
  })
}

variable "cidr_blocks" {
  type = set(string)
}

# Any type
variable "anything" {
  type = any
}
```

---

## 3. Expressions

### References and operators

```hcl
# Arithmetic
total = var.base_count * 2
price = var.price + var.tax

# Comparison
is_prod   = var.environment == "production"
not_prod  = var.environment != "production"
large     = var.count > 10
at_least  = var.count >= 5

# Logical
both   = var.a && var.b
either = var.a || var.b
not    = !var.enabled

# Conditional (ternary)
instance_type = var.environment == "production" ? "t3.large" : "t3.micro"
count_value   = var.enabled ? 1 : 0

# Null coalescing
name = coalesce(var.name, local.default_name)    # first non-null value
```

### Collection expressions

```hcl
# Index access
first_az = var.availability_zones[0]
last_az  = var.availability_zones[length(var.availability_zones) - 1]
tag_env  = var.tags["Environment"]

# Splat expression — get attribute from all items in a list
all_ids = aws_instance.servers[*].id
all_ips = aws_instance.servers[*].private_ip

# For expression — transform a collection
upper_tags = { for k, v in var.tags : k => upper(v) }
ids_list   = [for subnet in aws_subnet.private : subnet.id]
prod_tags  = { for k, v in var.tags : k => v if k != "Temp" }

# Filter a list
public_subnets = [for s in var.subnets : s if s.public]

# Convert list to map
subnet_map = { for s in aws_subnet.all : s.availability_zone => s.id }
```

---

## 4. Built-in Functions

### String functions

```hcl
# Case
lower("HELLO")              # "hello"
upper("hello")              # "HELLO"
title("hello world")        # "Hello World"

# Manipulation
trim("  hello  ", " ")     # "hello"
trimspace("  hello  ")     # "hello"
replace("a-b-c", "-", "_") # "a_b_c"
substr("hello world", 0, 5) # "hello"
split(",", "a,b,c")         # ["a", "b", "c"]
join("-", ["a", "b", "c"])  # "a-b-c"
format("%-10s%5d", "Name", 42)  # "Name           42"

# Checks
startswith("hello", "hel")  # true
endswith("hello", "llo")    # true
strcontains("hello", "ell") # true
length("hello")             # 5

# Encoding
base64encode("hello")       # "aGVsbG8="
base64decode("aGVsbG8=")    # "hello"
urlencode("hello world")    # "hello+world"
jsonencode({ key = "val" }) # "{\"key\":\"val\"}"
jsondecode("{\"key\":\"val\"}") # {key = "val"}
yamlencode({ key = "val" }) # "key: val\n"
yamldecode("key: val")      # {key = "val"}

# Hashing
md5("hello")                # "5d41402abc4b2a76b9719d911017c592"
sha256("hello")             # "2cf24dba..."
```

### Numeric functions

```hcl
abs(-5)           # 5
ceil(1.5)         # 2
floor(1.5)        # 1
max(1, 2, 3)      # 3
min(1, 2, 3)      # 1
parseint("42", 10) # 42
pow(2, 8)         # 256
```

### Collection functions

```hcl
# List functions
length(["a", "b", "c"])         # 3
element(["a", "b", "c"], 1)     # "b" (index wraps around)
index(["a", "b", "c"], "b")     # 1
contains(["a", "b"], "a")       # true
flatten([["a", "b"], ["c"]])    # ["a", "b", "c"]
compact(["a", "", "b", null])   # ["a", "b"]
distinct(["a", "b", "a"])       # ["a", "b"]
concat(["a"], ["b", "c"])       # ["a", "b", "c"]
slice(["a","b","c","d"], 1, 3)  # ["b", "c"]
sort(["c", "a", "b"])           # ["a", "b", "c"]
reverse(["a", "b", "c"])        # ["c", "b", "a"]
toset(["a", "b", "a"])          # toset(["a", "b"])

# Map functions
keys({a = 1, b = 2})            # ["a", "b"]
values({a = 1, b = 2})          # [1, 2]
lookup(var.map, "key", "default") # get key or default
merge({a = 1}, {b = 2})         # {a = 1, b = 2}
zipmap(["a", "b"], [1, 2])      # {a = 1, b = 2}
tomap({a = "1", b = "2"})       # convert to map

# Type conversions
tolist(toset(["a", "b"]))       # convert set to list
toset(["a", "b", "a"])          # remove duplicates
tonumber("42")                  # 42
tostring(42)                    # "42"
tobool("true")                  # true
```

### Filesystem functions

```hcl
# Read files
file("${path.module}/scripts/init.sh")  # read file as string
filebase64("${path.module}/cert.pem")   # read as base64
templatefile("${path.module}/user_data.sh.tpl", {
  hostname = var.hostname
  db_host  = var.db_host
})

# Path manipulation
basename("/path/to/file.txt")   # "file.txt"
dirname("/path/to/file.txt")    # "/path/to"
abspath("../relative/path")     # absolute path
pathexpand("~/mydir")           # expand ~ to home dir
```

### Network functions

```hcl
cidrhost("10.0.0.0/24", 4)      # "10.0.0.4"
cidrnetmask("10.0.0.0/24")      # "255.255.255.0"
cidrsubnet("10.0.0.0/16", 8, 1) # "10.0.1.0/24"
cidrsubnets("10.0.0.0/16", 8, 8, 8)  # ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
```

### Date/time functions

```hcl
timestamp()                       # current time in RFC3339
formatdate("YYYY-MM-DD", timestamp()) # "2024-01-15"
timeadd(timestamp(), "24h")       # timestamp + 24 hours
```

---

## 5. Meta-Arguments

Meta-arguments apply to any resource block and control Terraform's behavior.

### count

```hcl
# Create multiple resources
resource "aws_instance" "servers" {
  count         = 3
  ami           = "ami-12345678"
  instance_type = "t3.micro"

  tags = {
    Name = "server-${count.index}"    # count.index = 0, 1, 2
  }
}

# Conditional creation
resource "aws_instance" "web" {
  count = var.create_web_server ? 1 : 0
  # ...
}

# Reference counted resources
output "server_ids" {
  value = aws_instance.servers[*].id     # list of all IDs
}
output "first_server" {
  value = aws_instance.servers[0].id     # first one
}
```

### for_each

```hcl
# Iterate over a map (preferred over count for named resources)
resource "aws_iam_user" "users" {
  for_each = toset(["alice", "bob", "carol"])   # set of strings
  name     = each.key                            # each.key = each.value for sets
}

# Iterate over a map
locals {
  users = {
    alice = { email = "alice@example.com", admin = true }
    bob   = { email = "bob@example.com",   admin = false }
  }
}

resource "aws_iam_user" "users" {
  for_each = local.users
  name     = each.key              # "alice", "bob"
  tags     = {
    Email = each.value.email       # "alice@example.com"
    Admin = tostring(each.value.admin)
  }
}

# Reference for_each resources
output "user_arns" {
  value = { for k, v in aws_iam_user.users : k => v.arn }
}
```

### depends_on

```hcl
# Explicit dependency (usually not needed — Terraform infers from references)
resource "aws_s3_object" "config" {
  bucket = aws_s3_bucket.config.bucket
  key    = "app.conf"
  content = "config content"

  depends_on = [
    aws_s3_bucket_policy.config,  # must exist before uploading object
  ]
}
```

### provider

```hcl
# Use a specific provider alias
resource "aws_s3_bucket" "cdn" {
  provider = aws.us-east-1
  bucket   = "my-global-cdn"
}
```

---

## 6. Dynamic Blocks

Generate repeated nested blocks dynamically from a collection.

```hcl
# Without dynamic — repetitive
resource "aws_security_group" "web" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# With dynamic — DRY
locals {
  ingress_rules = [
    { port = 80,  protocol = "tcp", cidr = "0.0.0.0/0" },
    { port = 443, protocol = "tcp", cidr = "0.0.0.0/0" },
    { port = 22,  protocol = "tcp", cidr = "10.0.0.0/8" },
  ]
}

resource "aws_security_group" "web" {
  dynamic "ingress" {
    for_each = local.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = [ingress.value.cidr]
    }
  }
}
```

---

## 7. Conditionals & Loops

### Conditional expressions

```hcl
# Ternary
instance_type = var.env == "prod" ? "t3.large" : "t3.micro"

# Conditional resource creation (count)
resource "aws_cloudwatch_log_group" "app" {
  count = var.enable_logging ? 1 : 0
  name  = "/app/logs"
}

# Conditional output
output "log_group_name" {
  value = var.enable_logging ? aws_cloudwatch_log_group.app[0].name : null
}
```

### for expressions

```hcl
# List transformation
upper_names = [for name in var.names : upper(name)]

# Map transformation
tag_map = { for k, v in var.raw_tags : lower(k) => trimspace(v) }

# Filter with if
prod_instances = [for i in aws_instance.all : i.id if i.tags["Env"] == "prod"]

# Create map from list
subnet_by_az = {
  for subnet in aws_subnet.private :
    subnet.availability_zone => subnet.id
}

# Create map with grouping
# All subnets grouped by AZ
subnets_by_az = {
  for subnet in aws_subnet.all :
    subnet.availability_zone => subnet.id...   # ... groups into list
}
```

---

## 8. String Templates

```hcl
# Interpolation
name = "server-${var.environment}-${count.index}"
arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.role_name}"

# Multi-line with heredoc
user_data = <<-EOT
  #!/bin/bash
  echo "Environment: ${var.environment}" >> /etc/app.conf
  echo "DB_HOST: ${aws_db_instance.main.endpoint}" >> /etc/app.conf
  systemctl start myapp
EOT

# templatefile function (preferred for complex templates)
# scripts/user_data.sh.tpl
# #!/bin/bash
# DB_HOST="${db_host}"
# APP_ENV="${environment}"

user_data = templatefile("${path.module}/scripts/user_data.sh.tpl", {
  db_host     = aws_db_instance.main.endpoint
  environment = var.environment
})

# String directives (template loops and conditionals)
user_data = <<-EOT
  #!/bin/bash
  %{ for server in var.servers ~}
  echo "Adding server: ${server}"
  %{ endfor ~}
  %{ if var.debug ~}
  set -x
  %{ endif ~}
EOT
```

---

## Cheatsheet

```hcl
# Types
string  = "value"
number  = 42
bool    = true
list    = ["a", "b"]
map     = { key = "value" }
object  = { name = "x", count = 1 }
set     = toset(["a", "b"])

# References
var.name                    # variable
local.name                  # local
module.name.output          # module output
resource_type.name.attr     # resource attribute
data.type.name.attr         # data source
each.key / each.value       # for_each iteration
count.index                 # count iteration

# Essential functions
length()  upper()  lower()  format()
join()    split()  trim()   replace()
merge()   lookup() keys()   values()
flatten() compact() distinct() concat()
toset()   tolist()  tomap()  tostring()
file()    templatefile()
cidrsubnet()  cidrhost()
jsonencode()  jsondecode()
coalesce()    try()

# Meta-arguments
count     = 3
for_each  = toset(["a", "b"])
depends_on = [resource.name]
provider  = aws.alias
lifecycle { prevent_destroy = true }
```

---

*Next: [Resources & Data Sources →](./03-resources-data-sources.md)*
