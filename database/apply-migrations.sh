#!/usr/bin/env bash
#
# Apply pending PostgreSQL migrations in version order.
#
# Every migration that runs is recorded in the schema_migrations table, so the
# next run applies only the files that are not in there yet.
#
#   ./database/apply-migrations.sh
#   ./database/apply-migrations.sh --container some-other-postgres

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="${SCRIPT_DIR}/migrations"
ENV_FILE="$(cd -- "${SCRIPT_DIR}/.." && pwd)/.env"

container="${MIGRATE_CONTAINER:-email-operations-postgres}"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            printf 'Usage: apply-migrations.sh [--container <name>]\n\n'
            printf 'Applies database/migrations/*.sql in filename order and\n'
            printf 'records each one in schema_migrations. Already-applied\n'
            printf 'migrations are skipped.\n'
            exit 0
            ;;
        --container)
            [ $# -ge 2 ] || die "--container needs a name"
            container="$2"; shift 2
            ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

# Read one key from .env without sourcing it — .env is a config file, not a
# script, and may contain characters the shell would act on.
env_value() {
    local line
    [ -f "$ENV_FILE" ] || return 1
    line="$(sed -n "s/^[[:space:]]*$1=//p" "$ENV_FILE" | tail -n 1)"
    [ -n "$line" ] || return 1
    line="${line%$'\r'}"          # .env may be checked out with CRLF endings
    line="${line%\"}"; line="${line#\"}"
    printf '%s' "$line"
}

db_user="$(env_value POSTGRES_USER || printf 'email_operations')"
db_name="$(env_value POSTGRES_DB   || printf 'email_operations')"

docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$container" || die \
"container '${container}' is not running. Start it with:
  docker compose --env-file .env -f docker/docker-compose.yml up -d"

# ON_ERROR_STOP=1 is not optional: without it psql exits 0 after a failed
# statement, and a migration that did not apply would be recorded as applied.
psql_run() {
    docker exec -i "$container" \
        psql -v ON_ERROR_STOP=1 -U "$db_user" -d "$db_name" "$@"
}

psql_run -q </dev/null -c "
    SET client_min_messages TO warning;
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version    text        PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now()
    );" >/dev/null

applied=" $(psql_run -tAq </dev/null \
    -c 'SELECT version FROM schema_migrations;' | tr -d '\r' | tr '\n' ' ')"

pending=()
if [ -d "$MIGRATIONS_DIR" ]; then
    # LC_ALL=C sorts by byte value, so the UTC timestamp prefix gives the
    # correct order regardless of locale.
    while IFS= read -r file; do
        version="$(basename "$file" .sql)"
        case "$applied" in
            *" ${version} "*) ;;
            *) pending+=("$file") ;;
        esac
    done < <(LC_ALL=C find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -type f \
        | LC_ALL=C sort)
fi

if [ "${#pending[@]}" -eq 0 ]; then
    printf 'Up to date — no pending migrations.\n'
    exit 0
fi

# Line number of the final "COMMIT;", or empty if the file has none. Lines that
# are blank or comment-only are ignored when deciding whether it is last.
final_commit_line() {
    grep -niE '^[[:space:]]*commit[[:space:]]*;[[:space:]]*$' "$1" \
        | tail -n 1 | cut -d: -f1
}

# Every migration must own a transaction block: the ledger row is injected into
# it, so without one the schema change and its record could not commit together.
# Checked for all pending files up front, so a malformed migration is caught
# before any of them are applied.
check_transaction_block() {
    local file="$1" meaningful first last
    meaningful="$(grep -vE '^[[:space:]]*(--.*)?$' "$file" || true)"

    [ -n "$meaningful" ] || { printf 'file contains no SQL'; return 1; }

    first="$(printf '%s\n' "$meaningful" | head -n 1)"
    last="$(printf '%s\n' "$meaningful" | tail -n 1)"

    printf '%s' "$first" \
        | grep -qiE '^[[:space:]]*(BEGIN([[:space:]]+TRANSACTION)?|START[[:space:]]+TRANSACTION)[[:space:]]*;[[:space:]]*$' \
        || { printf 'first statement must be BEGIN;'; return 1; }

    printf '%s' "$last" \
        | grep -qiE '^[[:space:]]*COMMIT[[:space:]]*;[[:space:]]*$' \
        || { printf 'last statement must be COMMIT;'; return 1; }

    return 0
}

malformed=0
for file in "${pending[@]}"; do
    if ! reason="$(check_transaction_block "$file")"; then
        printf 'error: %s — %s\n' "$(basename "$file")" "$reason" >&2
        malformed=1
    fi
done
if [ "$malformed" -eq 1 ]; then
    die "every migration must wrap its statements in BEGIN; ... COMMIT;
       Nothing was applied."
fi

printf 'Applying %d migration(s).\n' "${#pending[@]}"

for file in "${pending[@]}"; do
    version="$(basename "$file" .sql)"
    printf '  %s ... ' "$version"

    # The file's own COMMIT is replaced by the ledger INSERT followed by COMMIT,
    # putting the record of the migration inside the migration's transaction.
    # A failure then leaves neither a half-applied schema nor a false record of
    # success. Anything after that COMMIT is comments only — see the check above.
    commit_line="$(final_commit_line "$file")"
    {
        head -n "$((commit_line - 1))" "$file"
        # Leading newline guards against a final line with no line terminator.
        printf '\nINSERT INTO schema_migrations (version) VALUES (%s);\n' \
            "'$(printf '%s' "$version" | sed "s/'/''/g")'"
        printf 'COMMIT;\n'
    } | psql_run -q -f - >/dev/null || {
        printf 'FAILED\n'
        die "${version} rolled back. Nothing was applied or recorded for it, and
       the migrations after it did not run."
    }

    printf 'ok\n'
done

printf 'Done.\n'
