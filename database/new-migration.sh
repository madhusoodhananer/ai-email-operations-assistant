#!/usr/bin/env bash
#
# Create a new, version-controlled PostgreSQL migration file.
#
# Migrations are named  <UTC timestamp>_<slug>.sql  so that a plain lexical
# sort of the directory is the correct execution order. Timestamps are UTC on
# purpose: local time would produce files that sort differently depending on
# who created them.
#
#   ./database/new-migration.sh                       # prompts for the name
#   ./database/new-migration.sh "add email messages"  # name as an argument
#   ./database/new-migration.sh --list                # show migrations in order
#
# Apply them with database/apply-migrations.sh.

set -euo pipefail

# Paths are resolved from the script's own location, so the script works no
# matter which directory it is invoked from.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="${SCRIPT_DIR}/migrations"

MAX_SLUG_LENGTH=80

usage() {
    cat <<'EOF'
Create a new PostgreSQL migration file.

Usage:
  new-migration.sh [options] [migration name]

If no name is given, the script prompts for one.

Options:
  -l, --list   List existing migrations in execution order and exit
  -h, --help   Show this help and exit

The name is slugified: lowercased, and any run of characters outside
[a-z0-9] becomes a single underscore. "Add Email Messages!" becomes
"add_email_messages".

Example:
  new-migration.sh "create mailboxes table"
      -> database/migrations/20260802101530_create_mailboxes_table.sql
EOF
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Lowercase, collapse every run of non-alphanumeric characters into one
# underscore, then trim leading/trailing underscores.
slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9' '_' \
        | sed -e 's/^_*//' -e 's/_*$//'
}

list_migrations() {
    if [ ! -d "$MIGRATIONS_DIR" ]; then
        printf 'No migrations directory yet (%s).\n' "$MIGRATIONS_DIR"
        return 0
    fi

    local found=0
    local file
    # LC_ALL=C keeps the sort byte-ordered and locale-independent, matching the
    # order apply-migrations.sh uses.
    while IFS= read -r file; do
        found=1
        printf '  %s\n' "$(basename "$file")"
    done < <(LC_ALL=C find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -type f \
        | LC_ALL=C sort)

    if [ "$found" -eq 0 ]; then
        printf 'No migrations yet.\n'
    fi
}

# Prefer a path relative to the current directory — easier to paste into a
# psql or git command. Falls back to absolute if realpath cannot do it, which
# is what happens under Git Bash when the drive prefixes disagree.
display_path() {
    realpath --relative-to=. -- "$1" 2>/dev/null || printf '%s' "$1"
}

# Best-effort author attribution for the file header.
migration_author() {
    local name
    name="$(git -C "$SCRIPT_DIR" config user.name 2>/dev/null || true)"
    if [ -n "$name" ]; then
        printf '%s' "$name"
        return
    fi
    printf '%s' "${USER:-${USERNAME:-unknown}}"
}

raw_name=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--list)
            list_migrations
            exit 0
            ;;
        --)
            shift
            raw_name="${raw_name}${raw_name:+ }$*"
            break
            ;;
        -*)
            die "unknown option: $1 (try --help)"
            ;;
        *)
            # Accept an unquoted multi-word name: "add email messages".
            raw_name="${raw_name}${raw_name:+ }$1"
            shift
            ;;
    esac
done

if [ -z "$raw_name" ]; then
    printf 'Migration name (e.g. "create mailboxes table"): '
    IFS= read -r raw_name || die "no name entered"
fi

# Tolerate a name typed with the extension already on it.
raw_name="${raw_name%.sql}"

slug="$(slugify "$raw_name")"
[ -n "$slug" ] || die "name '${raw_name}' contains no usable characters"
[ "${#slug}" -le "$MAX_SLUG_LENGTH" ] \
    || die "name is too long (${#slug} chars, max ${MAX_SLUG_LENGTH})"

timestamp="$(date -u +%Y%m%d%H%M%S)"
human_time="$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
author="$(migration_author)"

migration_file="${MIGRATIONS_DIR}/${timestamp}_${slug}.sql"

mkdir -p "$MIGRATIONS_DIR"

# Never clobber. An existing file at this exact path means the same name was
# generated within the same second.
[ ! -e "$migration_file" ] || die "$(basename "$migration_file") already exists"

# A duplicate slug under a different timestamp is legal but usually a mistake,
# so warn rather than fail.
existing_same_slug="$(LC_ALL=C find "$MIGRATIONS_DIR" -maxdepth 1 \
    -name "*_${slug}.sql" -type f | LC_ALL=C sort || true)"
if [ -n "$existing_same_slug" ]; then
    printf 'warning: a migration with this name already exists:\n' >&2
    printf '%s\n' "$existing_same_slug" | while IFS= read -r f; do
        printf '  %s\n' "$(basename "$f")" >&2
    done
fi

cat > "$migration_file" <<EOF
-- Migration: ${timestamp}_${slug}
-- Created:   ${human_time}
-- Author:    ${author}
--
-- Purpose:
--   <what this migration changes, and why>
--
-- The BEGIN/COMMIT block is required. database/apply-migrations.sh inserts the
-- schema_migrations row just before the COMMIT, so the schema change and the
-- record of it commit together — or neither does.
--
-- Once applied anywhere other than a local database, treat this file as
-- immutable — editing it will not re-run it. Correct mistakes with a new
-- migration.

BEGIN;

-- Write the schema change here.

COMMIT;
EOF

printf 'Created:\n  %s\n' "$(display_path "$migration_file")"
