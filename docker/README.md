# Local Docker environment

Version 1 runs PostgreSQL only. n8n and the API service are added to the same
compose file as they are implemented.

## Prerequisites

- Docker Engine with the Compose plugin (`docker compose`, not `docker-compose`)
- A `.env` file at the repository root — copy `.env.example` and set `POSTGRES_PASSWORD`

## Commands

All commands are run **from the repository root**, so that `.env` is used for
variable substitution.

```bash
# Start
docker compose --env-file .env -f docker/docker-compose.yml up -d

# Status and health
docker compose --env-file .env -f docker/docker-compose.yml ps

# Logs
docker compose --env-file .env -f docker/docker-compose.yml logs -f postgres

# psql shell
docker exec -it email-operations-postgres psql -U email_operations -d email_operations

# Stop, keeping data
docker compose --env-file .env -f docker/docker-compose.yml down

# Stop and DELETE the data volume — irreversible
docker compose --env-file .env -f docker/docker-compose.yml down -v
```

## Configuration

Read from the root `.env`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `POSTGRES_DB` | `email_operations` | Database name |
| `POSTGRES_USER` | `email_operations` | Role name |
| `POSTGRES_PASSWORD` | *(required)* | No default; startup fails if unset |
| `POSTGRES_PORT` | `5432` | Host port, bound to `127.0.0.1` only |

`DATABASE_URL` in `.env` must stay consistent with these values — it is what the
API service connects with, and nothing validates that the two agree.

## Initialization scripts

Files in `database/init/` are executed once, in filename order, the **first**
time the data volume is created. They do not run again on an existing volume.

To re-run them after a schema change during development:

```bash
docker compose --env-file .env -f docker/docker-compose.yml down -v
docker compose --env-file .env -f docker/docker-compose.yml up -d
```

This destroys all local data. Once the schema stabilizes, migrations in
`database/` become the mechanism for change, and this directory is used only to
bootstrap a fresh database.

## Notes

- The image tag is pinned to `postgres:16.4-alpine`. Changing the major version
  under an existing volume will not work — dump, recreate, and restore instead.
- The database is published on loopback only. It is not reachable from other
  machines on the network.
- `--locale=C` is set at initialization so index and sort ordering does not vary
  with the host locale. It cannot be changed after the volume is created.
