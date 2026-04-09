# Task Manager — Services

## Documentation
Specs, plans and tasks: `task-manager-docs/specs/{Aggregate}/`

## Architecture

```
ai-standards/             ← global standards and AI configuration
login-service/            ← auth API
login-front/              ← login frontend
task-service/             ← tasks, boards and members API
task-front/               ← main task manager frontend
notification-service/     ← internal notification service (email, SMS...)
```

## Service Responsibilities

| Service | Type | Responsibility |
|---|---|---|
| `login-service` | Backend (Symfony) | User authentication, registration, JWT tokens |
| `login-front` | Frontend (Vue 3) | Login and registration UI |
| `task-service` | Backend (Symfony) | Boards, tasks, members, permissions |
| `task-front` | Frontend (Vue 3) | Main task manager UI — entry point of the application |
| `notification-service` | Backend (Symfony) | Internal service for sending email, SMS, and other notifications. Called only by other backend services, not exposed to the frontend |
