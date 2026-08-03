# Migrations

Ordered PostgreSQL schema changes. This is the mechanism for schema change once
the schema has stabilized; `database/init/` only bootstraps a fresh data volume
(see `docker/README.md`).

## Create

```bash
./database/new-migration.sh                     # prompts for the name
./database/new-migration.sh "create mailboxes"  # name as an argument
./database/new-migration.sh --list              # existing migrations, in order
```

Files are named:

```
<YYYYMMDDHHMMSS>_<slug>.sql
```

The timestamp is **UTC**, so a plain lexical sort of this directory is the
correct execution order regardless of who created the file or where they were.
The name you type is slugified — lowercased, with each run of non-alphanumeric
characters collapsed to a single underscore.

## Apply

```bash
./database/apply-migrations.sh
```

Runs the pending migrations in filename order against the running
`email-operations-postgres` container and records each in `schema_migrations`.
Running it again applies only what is new.

## How the tracking works

```sql
CREATE TABLE schema_migrations (
    version    text        PRIMARY KEY,   -- the filename without .sql
    applied_at timestamptz NOT NULL DEFAULT now()
);
```

Every migration owns a transaction block. The runner replaces the file's final
`COMMIT;` with the ledger insert followed by `COMMIT;`, so what actually reaches
`psql` is:

```sql
BEGIN;
  <your statements>
  INSERT INTO schema_migrations (version) VALUES ('20260802101530_create_mailboxes');
COMMIT;
```

The schema change and the record of it therefore commit together, or neither
does. A failure rolls back both, and the run stops rather than continuing with
later migrations.

## Rules

- **Every migration must wrap its statements in `BEGIN;` … `COMMIT;`.** The
  generated template already does. The runner checks every pending file before
  applying any of them and refuses to run if one is missing the block — there
  would be nowhere to put the ledger row.
- **Nothing but comments after the final `COMMIT;`.** That line is where the
  ledger insert goes; anything below it is dropped.
- **Applied migrations are immutable.** Editing one does not re-run it: the
  version is already in `schema_migrations` and will be skipped. Add a new
  migration instead.
- **One logical change per migration**, so the history stays readable.
- **`CREATE INDEX CONCURRENTLY` will not work here**, because the transaction
  block is mandatory. Apply it by hand and insert the `schema_migrations` row
  yourself.
- **Adding an enum value is fine.** `ALTER TYPE ... ADD VALUE` has been allowed
  inside a transaction since PostgreSQL 12; the only restriction is that the new
  value cannot be *used* until that transaction commits. So add the value in one
  migration and backfill rows with it in the next.

## Starting over locally

There is no rollback. To reset a development database:

```bash
docker compose --env-file .env -f docker/docker-compose.yml down -v
docker compose --env-file .env -f docker/docker-compose.yml up -d
./database/apply-migrations.sh
```

This destroys all local data.
