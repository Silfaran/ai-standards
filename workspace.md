# Workspace

project: task-manager
services: task-manager-docs/services.md
specs: task-manager-docs/specs/
decisions: task-manager-docs/decisions.md
design-decisions: task-manager-docs/design-decisions.md
handoffs: handoffs/

## Service Ports

| Service | Port | Type |
|---|---|---|
| login-service | 8080 | Backend HTTP |
| task-service | 8081 | Backend HTTP |
| notification-service | 8082 | Backend HTTP |
| login-front | 3001 | Frontend dev |
| task-front | 3002 | Frontend dev |

When configuring CORS on a backend service, use the frontend port from this table — do not assume default framework ports (e.g. Vite's 5173).
