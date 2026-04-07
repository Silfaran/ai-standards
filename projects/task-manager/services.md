# Task Manager — Services

## Architecture

```
ai-standards/             ← global standards and AI configuration
login-service/            ← auth API
login-front/              ← login frontend
board-service/            ← boards and tasks API
board-front/              ← boards and tasks frontend
notification-service/     ← internal notification service (email, SMS...)
```

## Service Responsibilities

| Service | Type | Responsibility |
|---|---|---|
| `login-service` | Backend (Symfony) | User authentication, registration, JWT tokens |
| `login-front` | Frontend (Vue 3) | Login and registration UI |
| `board-service` | Backend (Symfony) | Boards, tasks, members, permissions |
| `board-front` | Frontend (Vue 3) | Boards and tasks UI |
| `notification-service` | Backend (Symfony) | Internal service for sending email, SMS, and other notifications. Called only by other backend services, not exposed to the frontend |
