# ecs-fargate-terragrunt

A containerized web app ([podinfo](https://github.com/stefanprodan/podinfo)) on ECS Fargate, for two
environments (dev and prod), managed with Terragrunt.

The app sits behind an Application Load Balancer and reads one secret from Secrets Manager. Before it
starts, a check in the same task proves that the task can reach and log in to an ElastiCache Redis
replication group. The service scales on request rate.

Both environments can be planned with nothing applied.

```mermaid
flowchart LR
  client([Client]) -->|HTTP 80| alb[ALB<br/>public subnets]
  alb -->|9898, allowed paths only| tasks[podinfo tasks<br/>private subnets]
  tasks -->|6379 over TLS, with AUTH| redis[(Redis<br/>data subnets)]
  tasks -->|443 through NAT| outside[Image registries<br/>Secrets Manager<br/>CloudWatch Logs]
```

## What is provided

```
live/
  root.hcl                # state backend, provider, tool version constraints
  dev/   env.hcl  network/  redis/  secret/  platform/  service/
  prod/  env.hcl  network/  redis/  secret/  platform/  service/
modules/
  redis/                  # replication group, its AUTH token, subnet group, security groups
  secret/                 # one Secrets Manager secret with a generated value
  platform/               # ECS cluster and the shared load balancer
  ecs-service/            # the reusable service module
```

Each environment has five units. Each unit has its own state file.

| Unit | Depends on | Creates | Resources (dev / prod) |
|---|---|---|---|
| `network` | nothing | VPC with public, private and data subnets, NAT, routes. Uses the public [`terraform-aws-modules/vpc`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) module, pinned to 6.7.3. | 30 / 38 |
| `secret` | nothing | The secret podinfo signs its tokens with. | 2 / 2 |
| `redis` | `network` | Redis replication group, its AUTH token in a secret of its own, the two security groups that control access to it, and its engine and slow logs. | 11 / 11 |
| `platform` | `network` | What every service shares: the ECS cluster and the load balancer with its listener, and the logs of both. | 19 / 19 |
| `service` | all four | Everything that belongs to one service: target group, listener rule, task definition, ECS service, IAM roles, security group, log group, autoscaling. | 15 / 15 |

`ecs-service` has a test,
[`modules/ecs-service/tests/ecs_service.tftest.hcl`](modules/ecs-service/tests/ecs_service.tftest.hcl).
Its nine runs cover the optional inputs (Redis, a private image, further security groups), the target
group's name, and the inputs the module refuses. The AWS provider is mocked, so it needs no credentials
and creates nothing:

```
cd modules/ecs-service
cp ../../live/dev/service/.terraform.lock.hcl .   # the same provider version the units use
terraform init -backend=false
terraform test
```

## How to plan it

You need Terraform, Terragrunt and AWS credentials for any account. It was written and tested with
Terraform 1.15.2, Terragrunt 1.1.2 and AWS provider 6.68.0. Its version constraints require at least
Terraform 1.11 and Terragrunt 1.0. The repo is pinned to Terraform, so that is what runs even where
OpenTofu is installed.

If you only have OpenTofu, set `TG_TF_PATH=tofu` in your shell, which overrides the pin. OpenTofu 1.13.1
plans both environments with the same result. It rewrites the `.terraform.lock.hcl` files to name its
own registry, at the same provider versions.

The region is `us-east-1`, and the three zones are chosen by zone ID. Both are set in
[`live/root.hcl`](live/root.hcl).

**1. Choose a state bucket.** A plan has to read the state, even an empty one, so it needs an S3 bucket
before it can start. There are two ways to give it one. Pick either:

- **Option A:** let Terragrunt create a new bucket for this repo.
- **Option B:** use a bucket you already have.

**Option A: a new bucket.** Run this once:

```
terragrunt --non-interactive --working-dir live/dev/network backend bootstrap
```

It creates `tfstate-<your account id>-<region>` with versioning, encryption, public access blocked and a
TLS-only bucket policy. The region is `us-east-1` unless you change it, and the account ID is looked up
from your credentials, so there is nothing to edit. It is the only thing this repo creates in your
account.

**Option B: your own bucket.** Name it in your shell, in every shell you run Terragrunt from:

```
export STATE_BUCKET=<your bucket>
export STATE_BUCKET_REGION=<its region>   # only if it is not us-east-1
```

Every state key starts with `ecs-fargate/`, so nothing else in that bucket is touched.

Without one of the two, every unit fails at `init` with `S3 bucket "..." does not exist`: Terragrunt 1.x
does not create a bucket by itself.

**2. Plan an environment.**

```
terragrunt --working-dir live/dev run --all -- plan
terragrunt --working-dir live/prod run --all -- plan
```

Each run should end with `Run Summary  5 units ... Succeeded 5`, adding 77 resources in dev and 85 in prod.
A single unit can be planned on its own, for example `terragrunt --working-dir live/dev/redis plan`.

Two things to know when reading the output:

- **Placeholder values are expected.** With nothing applied, a unit cannot read real outputs from the
  units it depends on. Each `dependency` block therefore has `mock_outputs`, which Terragrunt uses for
  `init`, `validate` and `plan` only. You will see six warnings saying so, and values such as
  `vpc-00000000000000000`, `mock-redis.invalid` and mock secret ARNs in the `redis`, `platform` and
  `service` plans. An `apply` does not accept mocks; it fails until the unit it depends on exists.
- **`--provider-cache` saves time.** Added after `run --all`, it downloads each provider once instead of
  once per unit.

To remove the bucket from option A afterwards, empty it and delete it in the S3 console. It is versioned,
so `aws s3 rb --force` alone may not be enough.

## Design decisions

**One state per unit.** The network, Redis, the secret, the shared platform and the service change at
different rates and have different owners. A service deploy cannot touch the VPC or Redis, and plans stay
small. The cost is the mock outputs described above.

**Dev and prod are plain copies with different inputs.** There is no shared include layer between them,
so `diff -r -x .terragrunt-cache live/dev live/prod` shows exactly how the environments differ.

**A public module for the VPC, hand-written modules for the rest.** The VPC is a commodity and not what
this repo is about. Redis, the secret and the service are small, and they are the parts worth
justifying, so every resource in them is one I chose.

**`platform` is separate from `ecs-service`.** The cluster and load balancer are shared by every service
in an environment. Adding a second service is one more unit that uses `ecs-service` with its own name,
image, paths and listener rule priority. It does not need a second load balancer, and it does not have
to use Redis: the module's `redis` input is optional. Its image can be a public one or one in private
ECR, named in `ecr_repository_arns`. If it calls something other than Redis, a database for example,
`additional_security_group_ids` attaches that thing's client security group to its tasks.

**`ecs-service` takes its surroundings as inputs.** It creates no VPC, cluster, load balancer or secret.
It receives their IDs and ARNs, which is what makes it reusable.

**Zones are chosen by ID.** A name such as `us-east-1a` is an alias AWS assigns per account, so it can
be a different physical zone for each reader. The three zone IDs in `root.hcl` are the same zones for
everyone.

**State backend.** S3: by default one bucket per account and region, or a bucket you name. There is
one key per unit, and every key starts with `ecs-fargate/`, so the state can share a bucket with other
projects. Locking uses S3 itself (`use_lockfile`), so there is no DynamoDB table.

**Lock files are committed.** Each unit's `.terraform.lock.hcl` pins the provider versions, so you plan
with the same versions I did. They hold hashes for macOS and Linux, on both Intel and ARM.

## Why the task can reach Redis

1. **Network path.** The tasks are in the private subnets and the Redis nodes are in the data subnets of
   the same VPC. Traffic between them uses the VPC's local route and never leaves it. The data subnets
   have no other route, so Redis cannot reach the internet or be reached from it.
2. **Security groups.** The group on the Redis nodes accepts port 6379 from one source only: a
   `redis-client` security group. The service attaches that client group to its tasks, and the client
   group carries the matching outbound rule. Being a member of the client group is the permission.
   Both groups live in the `redis` unit, so the service never edits another unit's security group.
3. **Name resolution.** The task is given the replication group's primary endpoint. That name always
   resolves to the current primary, including after a failover.
4. **Encryption.** In transit (TLS) and at rest, in both environments.
5. **Authentication.** Redis requires an AUTH token. The `redis` unit generates it and keeps it in a
   Secrets Manager secret of its own.
6. **Proof at startup.** The task definition has a `redis-check` container. It receives the token, runs
   `redis-cli --tls -h <endpoint> -p 6379 ping`, and succeeds only if the reply is `PONG`. It compares
   the reply because `redis-cli` exits 0 even when Redis refuses the token. The application container
   depends on it with condition `SUCCESS`, so podinfo only starts if Redis was reached and accepted the
   token. If not, the task fails, and the deployment circuit breaker rolls the service back.

The connection is made by `redis-check` and not by podinfo, because podinfo's built-in Redis client does
not support TLS.

A task can otherwise only receive traffic from the load balancer on port 9898 and send on port 443,
which image pulls, Secrets Manager and CloudWatch Logs need.

**Where to see this in a plan**

- In the `redis` unit: `aws_vpc_security_group_ingress_rule.redis_from_client` and
  `aws_vpc_security_group_egress_rule.client_to_redis`, the two rules that tie the groups together.
- In the `service` unit, inside `aws_ecs_task_definition.this`: the `redis-check` container with its
  command and its `REDISCLI_AUTH` secret, and the `dependsOn` entry of the `app` container with
  condition `SUCCESS`.
- One thing a first plan cannot show: the two security groups on the tasks. The plan prints that list as
  `(known after apply)`, because the service's own group does not exist yet. It is set in
  `network_configuration` in [`modules/ecs-service/main.tf`](modules/ecs-service/main.tf).

## Secrets

The application reads one secret. The setup holds a second one, the Redis AUTH token, which the
application never sees: only the startup check reads it.

**The application's secret** is the key podinfo signs its JWTs with. podinfo reads it from
`PODINFO_JWT_SECRET`; without it, it falls back to a default that is hardcoded in its public source.
`POST /token` shows the key is in use. It is the one secret the application reads, and it has its own
unit so that it outlives the service.

**The Redis AUTH token** is read only by the `redis-check` container, as `REDISCLI_AUTH`. podinfo never
sees it. It is created in the `redis` unit, because it has to be given to the secret and to ElastiCache
in the same run.

What both have in common:

- **The value is never in the plan or the state.** It is generated as an ephemeral `random_password` and
  written through a write-only argument. Raising a version number generates a new one.
- **Secrets Manager holds the only copy of the Redis token.** ElastiCache is given the value read back
  from the secret, not the generated one, so a re-run after a failed apply still uses the stored token.
- **The task definition holds ARNs, not values.** ECS fetches the values when a task starts, so running
  tasks need a new deployment to pick up a new value.
- **Least privilege.** The task execution role can read exactly these two secrets and write to the
  service's own log group. The task role, which the application runs as, has no permissions.

## How it is exposed

The load balancer is the only public entry point. Its listener answers 404 by default, and each service
adds a rule that forwards only the paths it owns. For podinfo those are `/`, `/version`, `/api/*` and
`/token*`.

This matters because podinfo is a demo app: `GET /env` prints its environment, which includes its
signing key, and `GET /panic` kills the process. Neither path is forwarded.

Dev is not open to the internet. Its load balancer admits only the ranges in `ingress_cidrs`. The
committed value, `203.0.113.0/24`, is a reserved documentation range, so dev stays closed until it is
replaced with a real VPN or office range. Setting `DEV_INGRESS_CIDR` in your shell, for example
`export DEV_INGRESS_CIDR=198.51.100.7/32`, lets one address in without editing a file. Only
`live/dev/platform` reads it.

The listener is HTTP only. HTTPS needs a certificate for a domain, which a blank account does not have.

## Autoscaling

podinfo is a stateless HTTP API. Its handlers are cheap, so a task serves many requests before its CPU
is busy. The service uses two target tracking policies:

- **Requests per task per minute** (`ALBRequestCountPerTarget`) is the main signal. It measures the load
  directly, and it rises as soon as traffic does, before the tasks are short of CPU.
- **Average CPU at 60%** is the backstop. CPU is what a task finally runs out of, and this policy catches
  what the request count cannot see, such as requests that become more expensive.

AWS adds tasks when either policy asks for more and removes them only when both agree. After a change it
waits 60 seconds before adding more tasks and 300 seconds before removing any, so a short dip does not
cause flapping.

There is no memory policy. podinfo's memory hardly moves with the load, so a memory policy would have
nothing to act on.

The request targets are placeholders, and dev's is set low so that scaling can be shown with a small
load generator. No test has measured how much one task can serve. The method would be to find the rate
at which one task's latency starts to degrade and set the target at about two thirds of it.

## Logs

Everything is in CloudWatch Logs. The log groups this repo creates keep 7 days in dev and 90 in prod.

| Log | What it answers |
|---|---|
| Container logs | What the application and the Redis check printed |
| Load balancer access logs | Who requested what, and with what result. It is the only record of requests the listener rejects, such as `/env`, because those never reach a task |
| ECS events | Why a task stopped. ECS itself only shows this for about an hour |
| ECS action logs | What ECS did on the account's behalf, such as each step of a deployment |
| Redis engine log and slow log | Restarts, failovers and slow commands |

The load balancer and ECS logs are delivered through the CloudWatch Logs integration.

## Hardening and operations

- **Containers:** both have a read-only root filesystem and all Linux capabilities dropped. The Redis
  check runs as the `redis` user, and podinfo's image runs as a non-root user of its own.
- **Logging cannot stall the app:** log delivery is non-blocking, with a buffer.
- **`apply` waits for the tasks:** it succeeds only when the new tasks are running and healthy, so a
  pipeline sees a failed Redis check as a failed deploy.
- **Zone rebalancing:** ECS evens tasks out across zones again after a zone problem or a scale-in.
- **Tags reach the tasks:** tasks inherit the service's tags, so their cost can be attributed.
- **Redis in prod:** the daily snapshot and the weekly maintenance have explicit, non-overlapping times.

## Dev versus prod

Both environments have the same shape: three zones, each with a public, a private and a data subnet.
Subnets cost nothing, so dev exercises the same layout as prod. What dev lacks is the redundancy.

| | dev | prod |
|---|---|---|
| VPC range | `10.0.0.0/16` | `10.1.0.0/16` |
| NAT gateways | 1, shared | 3, one per zone |
| Redis | 1 × `cache.t4g.micro`, no failover | primary + replica on `cache.m7g.large`, automatic failover, Multi-AZ |
| Redis backups | none | 7 daily snapshots, final snapshot on deletion |
| Redis changes | applied immediately | held for the maintenance window |
| Redis snapshot and maintenance times | chosen by AWS | 01:00 to 02:00 UTC daily, Sundays 03:00 to 04:00 UTC |
| Recovery window, both secrets | 0 days | 30 days |
| Load balancer | source allow-list, no deletion protection | open to the internet, deletion protection |
| Container Insights | off | on |
| Fargate capacity, for the service and as the cluster default | Spot | on-demand |
| Task size | 0.25 vCPU / 512 MiB | 0.5 vCPU / 1 GiB |
| Tasks, min to max | 1 to 3 | 3 to 12 |
| Requests per task per minute | 600 | 3000 |
| Log retention | 7 days | 90 days |

Prod never runs fewer than three tasks. ECS spreads them across the three zones and evens them out
again after a change, so losing a zone should leave two.

**What losing a zone does**

- **In prod,** the tasks in the other two zones keep serving, and the NAT gateways of those zones keep
  working. If the Redis primary was in that zone, the replica takes over.
- **In dev,** it depends on the zone. The one NAT gateway and the one Redis node each sit in a single
  zone. If that zone is lost, outbound access or Redis goes with it, and no new task can start.

**What they cost**

Roughly $80 a month for dev and $430 for prod while they run, by my estimate from list prices, with no
traffic. About three quarters of prod's cost is its two Redis nodes and three NAT gateways, which is the
price of the redundancy above.

## Trade-offs

The ones that matter most come first.

- **One AWS account for both environments.** Everything here runs in a single account, so dev and
  prod are separated by name prefix and by VPC. In practice each environment would have its own account.
  The bucket name already includes the account ID, and the two VPC ranges do not overlap.
- **HTTP only, and a public load balancer.** See [How it is exposed](#how-it-is-exposed) and the target
  design under [What I would add later](#what-i-would-add-later).
- **The Redis check blocks startup.** That is its purpose here, but it also means new tasks cannot start
  during a Redis outage, so scale-out is blocked while running tasks carry on. For a cache in production
  I would let the application connect lazily and degrade.
- **A Redis token, not IAM authentication.** IAM authentication stores no credential, which is better.
  But the client has to sign its own short-lived tokens, and `redis-cli` cannot, so the check would need
  a purpose-built image.
- **Token rotation is manual.** Raising `auth_token_version` generates a new token and writes it to the
  secret and to ElastiCache. Nothing does that on a schedule, and tasks read the new value only when
  they start.
- **Planning the `redis` unit reads the token.** Once the secret exists, each plan reads it into memory
  to hand to ElastiCache. It is not stored, but whoever plans needs permission to read that secret.
- **Modules are local paths.** Both environments always use the same module code. Modules in their own
  repository, referenced by version tag, would let prod stay on a version while dev tries the next.
- **Images are public and pinned by tag.** podinfo `6.15.0` comes from GitHub's registry and
  `redis:7.4-alpine` from ECR Public. A tag can be moved; a digest cannot. Every task start pulls both,
  so starting a task depends on those two registries and on a NAT gateway.
- **Private images from ECR only.** `ecr_repository_arns` lets the execution role pull from the
  repositories it names. A registry that wants a user name and password is not supported: the module has
  no input for the credentials.
- **Changing a service's port interrupts it.** The listener rule moves to the new target group before
  any task is in it, so the load balancer answers 503 until the first new task has registered there.
  Avoiding that means keeping both target groups behind the rule for a while, as a blue/green
  deployment does.
- **NAT gateways for outbound access.** Simple, but a fixed cost per gateway, and prod has three.
- **`engine = "redis"`.** Valkey is the cheaper drop-in AWS now recommends.
- **Logs go to CloudWatch, which charges per gigabyte delivered.** That is negligible here. At high
  traffic the same load balancer delivery can point at S3 instead.
- **Two CloudWatch Logs resource policies per environment.** An account may have ten per region, so
  many environments in one account would need a single shared policy.
- **The state bucket is created by Terragrunt's bootstrap,** not managed as code. S3 is the only
  backend: there is no local-state mode, so the path you plan with is the one that would be used.

## What I would add later

**What I would do first**

1. **HTTPS and an edge in front.** A domain and certificate, then CloudFront and WAF with the load
   balancer made internal.
2. **An account per environment, and a pipeline.**
3. **Alarms, and a load test.**

The rest, by area. The first three appear again in their groups, with the detail.

**Exposure and access**
- Production behind CloudFront and WAF, with the load balancer made internal and attached as a VPC
  origin, so nothing can bypass the edge. TLS terminates at CloudFront. The path allow-list moves to WAF.
- Dev reachable only over a VPN such as Tailscale, with an internal load balancer.
- A domain, certificate and DNS records.
- Encryption in transit on every hop: HTTPS from CloudFront to the load balancer, and from the load
  balancer to the tasks.

**Accounts and delivery**
- One account per environment under an AWS organization, with an account level in the directory layout
  and `allowed_account_ids` on the provider.
- CI that plans on pull requests and applies on merge, assuming a role per account.
- `tflint`, a policy scanner and the module test in that pipeline.
- Modules in their own repository, versioned by tag.

**Security**
- IAM authentication for Redis with named users in a user group, which removes the stored token.
- A network ACL on the data subnets as a second layer behind the security groups.
- Customer-managed KMS keys for the secrets, Redis, logs and state.
- Scheduled rotation of both secrets, with a forced deployment so tasks pick up the new values.
- Images mirrored to private ECR and pinned by digest.
- VPC endpoints for AWS APIs, so that traffic does not go through NAT.
- VPC flow logs.

**Operations and cost**
- Alarms and a dashboard: 5xx rate, target response time, unhealthy targets, Redis memory and evictions.
- A load test to calibrate the scaling targets.
- ECS Exec for debugging in dev, with its own audit logging.
- Deployments that roll back when an error-rate alarm fires, and blue/green deployments.
- A mix of on-demand and Spot capacity in prod: on-demand for the minimum, Spot for scale-out.
- Least-outstanding-requests routing on the target group, and a tracing sidecar.
- Service Connect, once there is a second service to call.
- The enhanced level of Container Insights in prod.
- ARM64 tasks, which are cheaper on Fargate; both images support it.
- Scheduled scaling to zero for dev outside working hours.
- The state bucket managed as code, with a lifecycle rule for old object versions.
