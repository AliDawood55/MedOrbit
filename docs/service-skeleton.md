# Service Skeleton

## Overview

The **Service Skeleton** is the foundation of the MedOrbit backend application. It provides the basic infrastructure required before implementing any business features such as authentication, user management, appointments, clinics, or AI services.

Instead of immediately writing business logic, the Service Skeleton prepares the application by configuring the Express server, loading environment variables, initializing logging, registering routes, and handling errors consistently.

The main objectives of this module are:

- Initialize the Express application.
- Load application configuration from environment variables.
- Provide a centralized logging system.
- Expose a Health Check endpoint.
- Handle unknown routes.
- Prepare the application for future modules.

---

# File: `src/config/env.js`

## Purpose

The `env.js` file is responsible for loading and centralizing all environment variables used throughout the backend.

Instead of directly accessing `process.env` in every file, this module exports a single configuration object that can be imported anywhere in the application.

This approach keeps the codebase clean, maintainable, and easier to configure across different environments (development, testing, production).

---

## Responsibilities

- Load the `.env` file.
- Read application configuration.
- Read database configuration.
- Read JWT configuration.
- Export a centralized configuration object.
- Prevent repeated access to `process.env`.

---

## Used By

- `server.js`
- `app.js`
- `database.js`
- Authentication module
- Any future service that requires configuration values

---

## Benefits

- Centralized configuration management.
- Easier environment switching.
- Cleaner source code.
- Simplifies testing and deployment.

---

# File: `src/utils/logger.js`

## Purpose

The `logger.js` file creates and exports a single application logger using **Pino**.

Professional applications should avoid using `console.log()` because it provides no structure, timestamps, or log levels.

The logger records application events in a consistent and structured format.

---

## Responsibilities

- Create the application logger.
- Configure log levels.
- Add timestamps.
- Format log output for development.
- Export the logger instance.

---

## Used By

- Express application
- Controllers
- Services
- Database module
- Authentication module
- Error handler

---

## Benefits

- Structured logging.
- Easier debugging.
- Production-ready logging.
- Better monitoring support.
- Compatible with Docker and cloud platforms.

---

# Health endpoint

## Purpose

The canonical health endpoint is defined directly in `backend/src/app.js`. The old unmounted `src/routes/health.routes.js` file was removed during backend-surface cleanup.

It does not perform any business logic and does not require authentication.

This endpoint is commonly used by Docker, Kubernetes, monitoring systems, and load balancers.

---

## Responsibilities

- Respond to Health Check requests.
- Return server status.
- Return current timestamp.
- Return the application version.

---

## Endpoint

```
GET /api/health
```

---

## Example Response

```json
{
    "success": true,
    "data": {
        "status": "healthy",
        "version": "2.0.0",
        "timestamp": "2026-08-25T00:00:00.000Z"
    }
}
```

---

## Benefits

- Confirms the API is running.
- Useful for monitoring.
- Useful for automated deployment.
- Helps identify server availability.

---

# File: `src/middleware/notFound.js`

## Purpose

The `notFound.js` middleware handles requests for routes that do not exist.

Instead of returning Express's default HTML error page, the middleware returns a standardized JSON response.

This ensures that every API response follows a consistent format.

---

## Responsibilities

- Catch unknown routes.
- Return HTTP 404.
- Return a JSON error response.
- Prevent unexpected HTML responses.

---

## Example

Request:

```
GET /unknown-route
```

Response:

```json
{
    "success": false,
    "message": "Route not found.",
    "path": "/unknown-route"
}
```

---

## Benefits

- Consistent API responses.
- Easier frontend integration.
- Improved debugging.
- Better developer experience.

---

# Service Skeleton Flow

The following diagram illustrates how a request passes through the Service Skeleton.

```
Client Request
       │
       ▼
Express Server
       │
       ▼
Environment Configuration (env.js)
       │
       ▼
Logger (logger.js)
       │
       ▼
Application Routes
       │
       ├── Health Route (/health)
       │
       └── Other Routes
               │
               ▼
        Route Found?
          │        │
         Yes       No
          │        │
          ▼        ▼
     Controller  notFound.js
          │        │
          ▼        ▼
      JSON Response
```

---

# Summary

The Service Skeleton serves as the foundation of the MedOrbit backend. It establishes the application's core infrastructure before implementing any business features.

By separating configuration, logging, routing, and middleware into dedicated modules, the backend becomes easier to maintain, test, and extend.

Future modules such as Authentication, User Management, Clinics, Doctors, Appointments, Notifications, and the AI Chatbot will all build upon this foundation.

--------------------------------------------------------------------------------------------
- # Testing using Postman:
       - ## Test Health Endpoint:
              - ### Collection Name: Service
                     - #### Request Name: `GET /api/health`
                            - #### Status: the test #success.
                     - #### Request Name:[notFound.js](https://oa0922592-3317435.postman.co/workspace/omar-abdallah's-Workspace~2e3179c7-ad31-47b2-82e7-7082c5718687/request/49494101-c594109f-9c73-42f2-bf79-3e6cc83fdca7?action=share&source=copy-link&creator=49494101):
                            - #### Status: the test #success.
