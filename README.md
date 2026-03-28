# VirtualBench Cloud API

Backend server for hosting and managing cloud VMs on Apple Silicon instances. Built with **Vapor 4** (Swift), **Fluent** (PostgreSQL), and **JWT** authentication.

## Architecture

```
┌──────────────────┐      ┌──────────────────┐
│   iOS Client     │──────│  VirtualBench    │
│  (VBRemote App)  │ HTTPS│  Cloud API       │
└──────────────────┘  WSS │  (Vapor 4)       │
                          ├──────────────────┤
                          │  PostgreSQL 16   │
                          │  Redis 7         │
                          └──────────────────┘
                                  │
                          ┌───────┴───────┐
                          │ Orchestrator  │ (simulated)
                          │ Apple Silicon │
                          │ Host Pool     │
                          └───────────────┘
```

## Quick Start

### Prerequisites

- Docker & Docker Compose **or**
- Swift 6.0+ and PostgreSQL 16

### Option 1: Docker Compose (Recommended)

```bash
# Clone and start all services
cd VirtualBenchCloud
docker compose up -d

# API available at http://localhost:8080
curl http://localhost:8080/health
```

### Option 2: Local Development

```bash
# Start PostgreSQL
docker run -d --name vb-postgres \
  -e POSTGRES_USER=virtualbench \
  -e POSTGRES_PASSWORD=virtualbench \
  -e POSTGRES_DB=virtualbench \
  -p 5432:5432 \
  postgres:16-alpine

# Build and run
cd VirtualBenchCloud
swift run Run serve --hostname 0.0.0.0 --port 8080
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `localhost` | PostgreSQL hostname |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `virtualbench` | Database username |
| `DB_PASSWORD` | `virtualbench` | Database password |
| `DB_NAME` | `virtualbench` | Database name |
| `DATABASE_URL` | — | Full PostgreSQL URL (overrides individual DB vars) |
| `JWT_SECRET` | `dev-secret-...` | HMAC-SHA256 signing key for JWTs |
| `LOG_LEVEL` | `info` | Logging verbosity |

## API Documentation

### Authentication

All endpoints except `/auth/*` and `/health` require a Bearer token in the `Authorization` header.

#### Sign In with Apple

```
POST /auth/signin
Content-Type: application/json

{
  "identityToken": "<Apple identity token>"
}

Response 200:
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ...",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "displayName": "User",
    "tier": "free"
  }
}
```

#### Refresh Token

```
POST /auth/refresh
Content-Type: application/json

{
  "refreshToken": "eyJ..."
}

Response 200:
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ..."
}
```

### Cloud VMs

#### List VMs

```
GET /vms
Authorization: Bearer <token>

Response 200: [CloudVMDTO]
```

#### Create VM

```
POST /vms
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "My Linux Server",
  "guestOS": "linux",        // linux | macOS | windows
  "instanceType": "starter", // starter | pro | max | ultra
  "region": "us-west-1",
  "displayWidth": 1920,      // optional
  "displayHeight": 1080      // optional
}

Response 200: CloudVMDTO
```

#### Get VM

```
GET /vms/:id
Authorization: Bearer <token>

Response 200: CloudVMDTO
```

#### Delete (Terminate) VM

```
DELETE /vms/:id
Authorization: Bearer <token>

Response 204
```

#### Start / Stop / Pause VM

```
POST /vms/:id/start
POST /vms/:id/stop
POST /vms/:id/pause
Authorization: Bearer <token>

Response 200: CloudVMDTO
```

### Provisioning

#### Get Provision Status

```
GET /vms/:id/provision
Authorization: Bearer <token>

Response 200:
{
  "id": "uuid",
  "vmID": "uuid",
  "status": "configuring",
  "progress": 80,
  "message": "Configuring VM environment...",
  "startedAt": "2026-03-28T12:00:00Z",
  "completedAt": null
}
```

#### Provision Stream (WebSocket)

```
WS /vms/:id/provision/stream?token=<jwt>

Receives JSON messages:
{
  "status": "installing_os",
  "progress": 50,
  "message": "Installing guest operating system..."
}
```

### Display & Control (WebSocket)

```
WS /vms/:id/display?token=<jwt>   — Binary frames (display stream)
WS /vms/:id/control?token=<jwt>   — Text frames (input/control)
```

Authenticate via `?token=` query parameter or send JWT as the first text message.

### Metrics

#### Current Metrics

```
GET /vms/:id/metrics
Authorization: Bearer <token>

Response 200:
{
  "vmID": "uuid",
  "timestamp": "2026-03-28T12:00:00Z",
  "cpuUsagePercent": 12.5,
  "memoryUsedMB": 4096,
  "memoryTotalMB": 8192,
  "diskUsedMB": 32768,
  "diskTotalMB": 131072,
  "networkInBytesPerSec": 25000,
  "networkOutBytesPerSec": 12000
}
```

#### Historical Metrics

```
GET /vms/:id/metrics/history?period=1h
Authorization: Bearer <token>

Supported periods: 5m, 15m, 1h, 6h, 24h, 7d

Response 200: [VMMetricsDTO]
```

### Billing

#### Current Usage

```
GET /billing/usage
Authorization: Bearer <token>

Response 200:
{
  "periodStart": "2026-03-01T00:00:00Z",
  "periodEnd": "2026-04-01T00:00:00Z",
  "totalCostCents": 1250,
  "totalMinutes": 7500,
  "records": [UsageRecordDTO]
}
```

#### Billing History

```
GET /billing/history
Authorization: Bearer <token>

Response 200: [BillingPeriodDTO]
```

#### Cost Estimate

```
GET /billing/estimate
Authorization: Bearer <token>

Response 200:
{
  "estimatedMonthlyCostCents": 3500
}
```

### Reference Data

#### Regions

```
GET /regions
Authorization: Bearer <token>

Response 200:
[
  { "id": "us-west-1", "name": "US West (California)", "available": true },
  { "id": "us-east-1", "name": "US East (Virginia)", "available": true },
  { "id": "eu-west-1", "name": "Europe (Ireland)", "available": true },
  { "id": "ap-southeast-1", "name": "Asia Pacific (Singapore)", "available": true }
]
```

#### Instance Types

```
GET /instance-types
Authorization: Bearer <token>

Response 200:
[
  { "id": "starter", "cpuCount": 2, "memoryMB": 8192, "diskSizeMB": 131072, "centsPerHour": 5 },
  { "id": "pro", "cpuCount": 4, "memoryMB": 16384, "diskSizeMB": 262144, "centsPerHour": 10 },
  { "id": "max", "cpuCount": 8, "memoryMB": 32768, "diskSizeMB": 524288, "centsPerHour": 20 },
  { "id": "ultra", "cpuCount": 16, "memoryMB": 65536, "diskSizeMB": 1048576, "centsPerHour": 40 }
]
```

### Health Check

```
GET /health

Response 200:
{
  "status": "ok",
  "service": "VirtualBenchCloud"
}
```

## Tier Limits

| Tier | Max VMs |
|------|---------|
| Free | 1 |
| Pro | 5 |
| Enterprise | 20 |

## Pricing

| Instance Type | CPU | RAM | Storage | Price |
|---------------|-----|-----|---------|-------|
| Starter | 2 | 8 GB | 128 GB SSD | $0.05/hr |
| Pro | 4 | 16 GB | 256 GB SSD | $0.10/hr |
| Max | 8 | 32 GB | 512 GB SSD | $0.20/hr |
| Ultra | 16 | 64 GB | 1 TB SSD | $0.40/hr |

## Rate Limiting

- **100 requests/minute** per authenticated user (per IP for unauthenticated)
- Returns `429 Too Many Requests` with `Retry-After` header
- Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`

## Running Tests

```bash
swift test
```

Tests use an in-memory SQLite configuration via the `.testing` environment. Ensure PostgreSQL is available or configure a test database.

## Project Structure

```
VirtualBenchCloud/
├── Package.swift
├── Sources/
│   ├── Run/main.swift                    # @main entrypoint
│   └── App/
│       ├── configure.swift               # DB, JWT, middleware, services
│       ├── routes.swift                  # Route registration
│       ├── Controllers/
│       │   ├── AuthController.swift      # Sign in with Apple + JWT
│       │   ├── VMController.swift        # VM CRUD + lifecycle
│       │   ├── ProvisionController.swift # Provision status + WS stream
│       │   ├── DisplayProxyController.swift # Display/control WS relay
│       │   ├── MetricsController.swift   # Real-time + historical metrics
│       │   └── BillingController.swift   # Usage, history, estimates
│       ├── Models/
│       │   ├── User.swift                # Fluent model
│       │   ├── CloudVM.swift             # Fluent model
│       │   ├── ProvisionJob.swift        # Fluent model
│       │   ├── UsageRecord.swift         # Fluent model
│       │   └── DTOs.swift                # Request/Response types
│       ├── Migrations/
│       │   ├── CreateUser.swift
│       │   ├── CreateCloudVM.swift
│       │   ├── CreateProvisionJob.swift
│       │   └── CreateUsageRecord.swift
│       ├── Services/
│       │   ├── OrchestratorService.swift # Simulated host pool
│       │   ├── InstanceManager.swift     # Simulated VM lifecycle
│       │   ├── DisplayProxyService.swift # WebSocket frame relay
│       │   └── BillingService.swift      # Cost calculation
│       └── Middleware/
│           ├── JWTAuthMiddleware.swift    # JWT verification
│           └── RateLimitMiddleware.swift  # In-memory rate limiting
├── Tests/AppTests/
│   ├── AuthTests.swift
│   ├── VMControllerTests.swift
│   └── BillingTests.swift
├── Dockerfile                            # Multi-stage Swift 6.0 build
├── docker-compose.yml                    # App + PostgreSQL + Redis
└── README.md
```

## Simulated Services

The **OrchestratorService** and **InstanceManager** use in-memory state to simulate Apple Silicon cloud hosts. They expose production-grade interfaces that can be swapped for real infrastructure providers (MacStadium, AWS Mac instances, etc.) without changing the controller layer.

Each region is seeded with 3 simulated hosts (M2 Ultra-class: 24 CPU, 192 GB RAM each).

## License

Proprietary — VirtualBench © 2026
