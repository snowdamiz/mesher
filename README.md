# Mesher

Mesher is organized as a two-app repository:

- `server/`: Mesh backend runtime, migrations, and server-owned spikes.
- `client/`: Vite/Streem frontend application.

## Repository Structure

```text
.
├── server/
│   ├── main.mpl
│   ├── src/
│   ├── migrations/
│   └── Dockerfile
├── client/
│   ├── src/
│   └── package.json
├── docker-compose.yml
└── package.json
```

## Root Commands

Use root wrapper scripts for day-to-day work:

- `npm run dev:server`
- `npm run build:server`
- `npm run test:server`
- `npm run migrate:status`
- `npm run migrate:up`
- `npm run dev:client`
- `npm run build:client`
- `npm run test:client`

Direct build commands remain valid:

- `meshc build server`
- `npm --prefix client run build`

## Docker Compose Services

`docker-compose.yml` defines exactly:

- `server`
- `timescaledb`
- `valkey`

## API Contract

The client calls backend routes with relative `/api` paths (for example `/api/auth/login`), so local proxying and compose networking stay behavior-compatible across environments.
