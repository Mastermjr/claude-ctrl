#!/usr/bin/env bash
# db-safety-lib.sh — Modular database safety check library for pre-bash.sh
#
# @modality database
#
# This library provides all database CLI detection, environment classification,
# and risk assessment functions. It is loaded on demand via require_db_safety()
# in source-lib.sh — zero overhead when no database CLI is detected.
#
# Architecture: each database CLI has a dedicated handler function. The dispatch
# point in pre-bash.sh calls _db_detect_cli() first; if the result is "none",
# the entire section exits early with zero further overhead. This design allows
# Wave 2 to add per-CLI handlers without touching pre-bash.sh's core logic.
#
# @decision DEC-DBSAFE-001
# @title Modular database check architecture with zero-overhead early exit
# @status accepted
# @rationale Database safety checks need to handle multiple CLI tools (psql, mysql,
#   sqlite3, mongosh, redis-cli, cockroach) with different risk profiles and
#   environment-tiered responses. Embedding all logic in pre-bash.sh would bloat the
#   file and make it harder to add new CLI handlers. Instead, the detection loop in
#   pre-bash.sh provides a single dispatch point: if no DB CLI is detected, the
#   entire database section is skipped with one string comparison. db-safety-lib.sh
#   holds all database-specific logic and is loaded lazily via require_db_safety().
#   This follows the established require_*() pattern from DEC-SPLIT-002.
#
# @decision DEC-DBSAFE-002
# @title Environment-tiered response: production=deny all, staging=deny destructive,
#        dev/local=advisory only
# @status accepted
# @rationale The appropriate response to a risky database command varies by
#   environment. Blocking SELECT on production would be overly aggressive; blocking
#   DROP TABLE on dev would be unnecessarily disruptive. The tiering is:
#   - production/unknown + deny-risk → hard deny (irreversible in prod)
#   - production/unknown + advisory-risk → deny with explanation (data loss risk)
#   - staging + deny-risk → hard deny (shared data, still dangerous)
#   - staging + advisory-risk → log warning, allow (staging mistakes are recoverable)
#   - development/local + deny-risk → log warning, allow (local data is disposable)
#   - development/local + advisory-risk → allow silently (low signal in dev)
#   Unknown environment is treated as production (fail-safe default).

# Guard: prevent re-sourcing
[[ -n "${_DB_SAFETY_LIB_LOADED:-}" ]] && return 0
_DB_SAFETY_LIB_LOADED=1
_DB_SAFETY_LIB_VERSION=2

# ---------------------------------------------------------------------------
# _db_detect_cli COMMAND
#
# Identifies which database CLI tool is being invoked in the given command.
# Returns one of: psql, mysql, sqlite3, mongosh, redis-cli, cockroach, none
#
# Handles:
#   - Bare CLI name at command start (psql ..., mysql ...)
#   - CLI after path prefix (/usr/bin/psql, /usr/local/bin/mysql)
#   - CLI after sudo (sudo psql ..., sudo -u postgres psql ...)
#   - Quoted arguments (psql -c "SELECT ..." )
#   - Chain commands (cmd && psql ...)
#
# Returns "none" for non-database commands — caller exits early on "none".
# ---------------------------------------------------------------------------
_db_detect_cli() {
    local cmd="$1"

    # Strip comments and quotes for pattern matching (same as pre-bash.sh _stripped_cmd)
    local stripped
    stripped=$(printf '%s' "$cmd" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g" | sed -E '/^[[:space:]]*#/d; s/[[:space:]]#.*$//')

    # Pattern: match CLI tools as standalone words, allowing:
    #   - word boundary at start/after spaces/after path separator
    #   - preceding: start of string, whitespace, &&, ||, ;, (, |
    #   - optional path prefix: /path/to/cli or ./cli
    local cli_pattern_prefix='(^|[[:space:]]|&&|\|\|?|;|\(|/)('
    local cli_pattern_suffix=')([[:space:]]|$|;|&&|\|)'

    # Check each CLI in priority order (most specific first)
    local cli
    for cli in psql mysql sqlite3 mongosh redis-cli cockroach; do
        if printf '%s' "$stripped" | grep -qE "${cli_pattern_prefix}${cli}${cli_pattern_suffix}"; then
            printf '%s' "$cli"
            return 0
        fi
    done

    printf 'none'
    return 0
}

# ---------------------------------------------------------------------------
# _db_detect_environment
#
# Identifies the environment type from environment variables and connection strings.
# Returns one of: production, staging, development, local, unknown
#
# Detection priority:
#   1. APP_ENV, RAILS_ENV, NODE_ENV, FLASK_ENV, ENVIRONMENT (explicit env vars)
#   2. DATABASE_URL hostname patterns (prod/staging/dev indicators)
#   3. PGHOST patterns
#   4. Default: unknown (treated as production by tiering logic)
# ---------------------------------------------------------------------------
_db_detect_environment() {
    # Priority 1: explicit environment variables (check in order of specificity)
    local env_val=""
    for env_var in APP_ENV RAILS_ENV NODE_ENV FLASK_ENV ENVIRONMENT; do
        env_val="${!env_var:-}"
        if [[ -n "$env_val" ]]; then
            break
        fi
    done

    if [[ -n "$env_val" ]]; then
        # Normalize to lowercase for case-insensitive matching (bash 3.2 compatible: use tr)
        local env_lower
        env_lower=$(printf '%s' "$env_val" | tr '[:upper:]' '[:lower:]')
        # Normalize to canonical environment names
        case "$env_lower" in
            prod|production)               printf 'production'; return 0 ;;
            staging|stage|preprod|pre-prod) printf 'staging';    return 0 ;;
            dev|development)               printf 'development'; return 0 ;;
            local|test|testing|ci)         printf 'local';       return 0 ;;
            *)
                # Unknown value — fall through to URL detection
                ;;
        esac
    fi

    # Priority 2: DATABASE_URL hostname patterns
    local db_url="${DATABASE_URL:-}"
    if [[ -n "$db_url" ]]; then
        # Extract hostname from URL: protocol://user:pass@hostname:port/db
        local hostname
        hostname=$(printf '%s' "$db_url" | sed -E 's|^[^:]+://([^:@/]+:[^@]+@)?([^/:]+).*|\2|' 2>/dev/null || true)

        if [[ -n "$hostname" ]]; then
            # Production indicators in hostname
            if printf '%s' "$hostname" | grep -qiE '(^|[-_.])prod([-_.]|$)|production|rds\.amazonaws\.com|\.azure\.com|\.gcp\.com|neon\.tech|supabase\.co'; then
                printf 'production'; return 0
            fi
            # Staging indicators
            if printf '%s' "$hostname" | grep -qiE '(^|[-_.])stag([-_.]|$)|staging|preprod|pre-prod'; then
                printf 'staging'; return 0
            fi
            # Development/local indicators
            if printf '%s' "$hostname" | grep -qiE 'localhost|127\.|0\.0\.0\.0|\.local$|(^|[-_.])dev([-_.]|$)'; then
                printf 'development'; return 0
            fi
        fi
    fi

    # Priority 3: PGHOST patterns (PostgreSQL-specific)
    local pghost="${PGHOST:-}"
    if [[ -n "$pghost" ]]; then
        if printf '%s' "$pghost" | grep -qiE '(^|[-_.])prod([-_.]|$)|production|rds\.amazonaws\.com'; then
            printf 'production'; return 0
        fi
        if printf '%s' "$pghost" | grep -qiE 'localhost|127\.|0\.0\.0\.0|/var/run/postgresql|/tmp'; then
            printf 'local'; return 0
        fi
    fi

    # Default: unknown (treated as production by tiering logic — fail-safe)
    printf 'unknown'
    return 0
}

# ---------------------------------------------------------------------------
# _db_classify_risk COMMAND CLI_TYPE
#
# Classifies a database command as: safe, advisory, or deny.
# Returns a string: "<risk_level>:<reason>"
#
# Risk levels:
#   deny     — irreversible data destruction (DROP, TRUNCATE, FLUSHALL, etc.)
#   advisory — risky but potentially reversible (DELETE without WHERE, etc.)
#   safe     — read operations (SELECT, SHOW, EXPLAIN, etc.)
#
# The caller (dispatch in pre-bash.sh) combines risk level with environment tier
# to decide the actual response (hard deny vs. warning vs. silent allow).
# ---------------------------------------------------------------------------
_db_classify_risk() {
    local cmd="$1"
    local cli_type="$2"

    # Normalize to uppercase for SQL pattern matching
    local cmd_upper
    cmd_upper=$(printf '%s' "$cmd" | tr '[:lower:]' '[:upper:]')

    case "$cli_type" in
        psql|mysql|sqlite3|cockroach)
            # --- SQL risk patterns ---
            # DENY: irreversible DDL destruction
            if printf '%s' "$cmd_upper" | grep -qE '\bDROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|SEQUENCE|FUNCTION|PROCEDURE|TRIGGER)\b'; then
                printf 'deny:DROP %s permanently destroys database objects with no built-in rollback' \
                    "$(printf '%s' "$cmd_upper" | grep -oE 'DROP[[:space:]]+[A-Z]+' | head -1)"
                return 0
            fi
            # DENY: TRUNCATE removes all rows, no rollback in most engines
            if printf '%s' "$cmd_upper" | grep -qE '\bTRUNCATE\b'; then
                printf 'deny:TRUNCATE permanently removes all rows from a table with no rollback path'
                return 0
            fi
            # DENY: ALTER TABLE DROP COLUMN is irreversible
            if printf '%s' "$cmd_upper" | grep -qE '\bALTER[[:space:]]+TABLE\b.*\bDROP[[:space:]]+COLUMN\b'; then
                printf 'deny:ALTER TABLE DROP COLUMN permanently removes a column and its data'
                return 0
            fi
            # ADVISORY: DELETE without WHERE affects all rows
            if printf '%s' "$cmd_upper" | grep -qE '\bDELETE[[:space:]]+FROM\b' && \
               ! printf '%s' "$cmd_upper" | grep -qE '\bWHERE\b'; then
                printf 'advisory:DELETE without WHERE clause will remove all rows in the table'
                return 0
            fi
            # ADVISORY: UPDATE without WHERE affects all rows
            if printf '%s' "$cmd_upper" | grep -qE '\bUPDATE\b.*\bSET\b' && \
               ! printf '%s' "$cmd_upper" | grep -qE '\bWHERE\b'; then
                printf 'advisory:UPDATE without WHERE clause will modify all rows in the table'
                return 0
            fi
            ;;

        redis-cli)
            # --- Redis risk patterns ---
            # DENY: FLUSHALL removes ALL keys across all databases
            if printf '%s' "$cmd_upper" | grep -qE '\bFLUSHALL\b'; then
                printf 'deny:FLUSHALL permanently deletes all keys across all Redis databases'
                return 0
            fi
            # DENY: FLUSHDB removes all keys in current database
            if printf '%s' "$cmd_upper" | grep -qE '\bFLUSHDB\b'; then
                printf 'deny:FLUSHDB permanently deletes all keys in the current Redis database'
                return 0
            fi
            # DENY: CONFIG SET can alter running server in dangerous ways
            if printf '%s' "$cmd_upper" | grep -qE '\bCONFIG[[:space:]]+SET\b'; then
                printf 'deny:CONFIG SET modifies live Redis server configuration'
                return 0
            fi
            # DENY: SHUTDOWN stops the Redis server
            if printf '%s' "$cmd_upper" | grep -qE '\bSHUTDOWN\b'; then
                printf 'deny:SHUTDOWN stops the Redis server'
                return 0
            fi
            # ADVISORY: DEL multiple keys
            if printf '%s' "$cmd_upper" | grep -qE '\bDEL\b'; then
                printf 'advisory:DEL removes one or more keys permanently'
                return 0
            fi
            ;;

        mongosh)
            # --- MongoDB risk patterns ---
            # DENY: dropDatabase removes entire database
            if printf '%s' "$cmd" | grep -qE 'dropDatabase\(\s*\)'; then
                printf 'deny:dropDatabase() permanently destroys the entire database'
                return 0
            fi
            # DENY: drop() on a collection
            if printf '%s' "$cmd" | grep -qE '\.(drop|dropCollection)\(\s*\)'; then
                printf 'deny:drop()/dropCollection() permanently destroys a collection and all its documents'
                return 0
            fi
            # DENY: deleteMany with empty filter matches all documents
            if printf '%s' "$cmd" | grep -qE 'deleteMany\(\s*\{\s*\}\s*\)'; then
                printf 'deny:deleteMany({}) deletes all documents in the collection'
                return 0
            fi
            # ADVISORY: deleteMany with non-empty filter
            if printf '%s' "$cmd" | grep -qE 'deleteMany\('; then
                printf 'advisory:deleteMany() will permanently remove matching documents'
                return 0
            fi
            # ADVISORY: deleteOne
            if printf '%s' "$cmd" | grep -qE 'deleteOne\('; then
                printf 'advisory:deleteOne() will permanently remove a document'
                return 0
            fi
            ;;
    esac

    # Default: safe (reads, creates, inserts, etc.)
    printf 'safe:'
    return 0
}

# ---------------------------------------------------------------------------
# _db_format_deny REASON SUGGESTION
#
# Formats a deny message consistently for database safety denials.
# The output is passed to emit_deny() in pre-bash.sh.
# ---------------------------------------------------------------------------
_db_format_deny() {
    local reason="$1"
    local suggestion="${2:-}"

    printf 'DB-SAFETY DENY — %s' "$reason"
    if [[ -n "$suggestion" ]]; then
        printf '\n\nSuggestion: %s' "$suggestion"
    fi
}

# ---------------------------------------------------------------------------
# _db_format_advisory REASON
#
# Formats an advisory message for database safety warnings.
# The output is used in hook advisory emissions.
# ---------------------------------------------------------------------------
_db_format_advisory() {
    local reason="$1"
    printf 'DB-SAFETY ADVISORY — %s' "$reason"
}

# ---------------------------------------------------------------------------
# Per-CLI handler stubs
# These will be populated in Wave 2 with full validation logic.
# For now they delegate to _db_classify_risk for basic classification.
# ---------------------------------------------------------------------------

# _db_check_psql COMMAND ENV
# PostgreSQL-specific handler stub
_db_check_psql() {
    local cmd="$1"
    local env="${2:-unknown}"
    _db_classify_risk "$cmd" "psql"
}

# _db_check_mysql COMMAND ENV
# MySQL/MariaDB-specific handler stub
_db_check_mysql() {
    local cmd="$1"
    local env="${2:-unknown}"
    _db_classify_risk "$cmd" "mysql"
}

# _db_check_sqlite3 COMMAND ENV
# SQLite-specific handler stub
_db_check_sqlite3() {
    local cmd="$1"
    local env="${2:-unknown}"
    _db_classify_risk "$cmd" "sqlite3"
}

# _db_check_redis COMMAND ENV
# Redis-specific handler stub
_db_check_redis() {
    local cmd="$1"
    local env="${2:-unknown}"
    _db_classify_risk "$cmd" "redis-cli"
}

# _db_check_mongo COMMAND ENV
# MongoDB-specific handler stub
_db_check_mongo() {
    local cmd="$1"
    local env="${2:-unknown}"
    _db_classify_risk "$cmd" "mongosh"
}

# =============================================================================
# Wave 2b: Multi-vector database infrastructure safety functions
#
# @decision DEC-DBSAFE-W2B-001
# @title Four-function multi-vector safety layer for non-CLI database infrastructure
# @status accepted
# @rationale Database infrastructure can be destroyed by tools that are NOT database
#   CLIs — migration frameworks that wipe schemas, IaC tools that tear down DB instances,
#   container orchestration that deletes persistent volumes, and ORM patterns that bypass
#   migration management. Wave 2b adds four detectors (B5-B8) that fire in pre-bash.sh
#   BEFORE the existing DB CLI section, catching these vectors early. Each function
#   returns a standardized result string: "allow", "deny:<reason>", or "advisory:<reason>".
#   Migration frameworks (B5) are ALLOWED through — they are intentional schema changes —
#   but advisory flags are emitted for especially dangerous variants (flyway clean,
#   alembic downgrade base, drizzle-kit push --force) and for any migration in production.
#
# @decision DEC-DBSAFE-W2B-002
# @title _db_detect_migration returns framework name, advisory is separate function
# @status accepted
# @rationale Separating detection (returns framework name / "none") from advisory
#   classification (_db_detect_migration_advisory) keeps the detection function
#   pure and testable in isolation. pre-bash.sh can call detection first for the
#   quick-exit gate, then call advisory only when a framework was detected.
#   This matches the pattern established by _db_detect_cli + _db_classify_risk.
# =============================================================================

# ---------------------------------------------------------------------------
# _db_detect_migration COMMAND
#
# Recognizes migration framework commands and returns the framework name.
# Migration commands are ALLOWED through (they are intentional schema changes),
# but callers should also invoke _db_detect_migration_advisory for special-case
# advisory warnings.
#
# Returns: "<framework_name>" if detected, "none" if not.
#
# Supported frameworks:
#   rails    — rails db:migrate, rails db:rollback, rails db:schema:load, rake db:*
#   django   — python/python3 manage.py migrate|makemigrations
#   alembic  — alembic upgrade|downgrade|revision
#   prisma   — prisma migrate deploy|dev, prisma db push
#   flyway   — flyway migrate|repair|clean
#   liquibase — liquibase update|rollback
#   sequelize — npx sequelize-cli db:migrate
#   knex     — npx knex migrate:latest|migrate:rollback
#   typeorm  — typeorm migration:run
#   goose    — goose up|down
#   golang-migrate — migrate -path
#   drizzle-kit — drizzle-kit push|generate|migrate
# ---------------------------------------------------------------------------
_db_detect_migration() {
    local cmd="$1"

    # Rails: rails db:migrate, rails db:rollback, rails db:schema:load
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()rails[[:space:]]+(db:(migrate|rollback|schema:|reset|seed)|db:[a-z])'; then
        printf 'rails'; return 0
    fi
    # Rake: rake db:migrate, rake db:rollback, rake db:*
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()rake[[:space:]]+db:[a-z]'; then
        printf 'rails'; return 0
    fi

    # Django: python/python3 manage.py migrate|makemigrations
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()python3?[[:space:]]+manage\.py[[:space:]]+(migrate|makemigrations)'; then
        printf 'django'; return 0
    fi

    # Alembic: alembic upgrade|downgrade|revision
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()alembic[[:space:]]+(upgrade|downgrade|revision)'; then
        printf 'alembic'; return 0
    fi

    # Prisma: prisma migrate deploy|dev, prisma db push
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()prisma[[:space:]]+(migrate[[:space:]]+(deploy|dev)|db[[:space:]]+push)'; then
        printf 'prisma'; return 0
    fi

    # Flyway: flyway migrate|repair|clean
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()flyway[[:space:]]+(migrate|repair|clean)([[:space:]]|$)'; then
        printf 'flyway'; return 0
    fi

    # Liquibase: liquibase update|rollback
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()liquibase[[:space:]]+(update|rollback)'; then
        printf 'liquibase'; return 0
    fi

    # Sequelize: npx sequelize-cli db:migrate
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()npx[[:space:]]+sequelize-cli[[:space:]]+db:migrate'; then
        printf 'sequelize'; return 0
    fi

    # Knex: npx knex migrate:latest|migrate:rollback
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()npx[[:space:]]+knex[[:space:]]+migrate:(latest|rollback)'; then
        printf 'knex'; return 0
    fi

    # TypeORM: typeorm migration:run
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()typeorm[[:space:]]+migration:run'; then
        printf 'typeorm'; return 0
    fi

    # Goose: goose up|down
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()goose[[:space:]]+(up|down)([[:space:]]|$)'; then
        printf 'goose'; return 0
    fi

    # golang-migrate: migrate -path
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()migrate[[:space:]]+-path'; then
        printf 'golang-migrate'; return 0
    fi

    # Drizzle Kit: drizzle-kit push|generate|migrate
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()drizzle-kit[[:space:]]+(push|generate|migrate)'; then
        printf 'drizzle-kit'; return 0
    fi

    printf 'none'
    return 0
}

# ---------------------------------------------------------------------------
# _db_detect_migration_advisory COMMAND
#
# Returns an advisory message string for especially dangerous migration variants,
# or an empty string if no advisory applies.
#
# Special cases flagged as advisory (not deny — the commands are still allowed):
#   drizzle-kit push --force  → "drizzle-kit push --force skips confirmation"
#   alembic downgrade base    → "alembic downgrade base reverts ALL migrations"
#   flyway clean              → "flyway clean drops all objects in the configured schemas"
#   production env + any migration → "Production migration detected. Ensure this is intentional."
#
# Production check fires after special-case check so both can appear if applicable.
# Callers that need just the advisory string can pipe or capture this output.
# ---------------------------------------------------------------------------
_db_detect_migration_advisory() {
    local cmd="$1"
    local advisory=""

    # Special case: drizzle-kit push --force
    if printf '%s' "$cmd" | grep -qE 'drizzle-kit[[:space:]]+push.*--force'; then
        advisory="drizzle-kit push --force skips confirmation"
    fi

    # Special case: alembic downgrade base
    if printf '%s' "$cmd" | grep -qE 'alembic[[:space:]]+downgrade[[:space:]]+base'; then
        advisory="alembic downgrade base reverts ALL migrations"
    fi

    # Special case: flyway clean (destructive — drops all DB objects)
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()flyway[[:space:]]+clean([[:space:]]|$)'; then
        advisory="flyway clean drops all objects in the configured schemas"
    fi

    # Production environment advisory (appended after special cases)
    local env
    env=$(_db_detect_environment)
    if [[ "$env" == "production" || "$env" == "unknown" ]]; then
        # Only append production advisory when this is actually a migration command
        local framework
        framework=$(_db_detect_migration "$cmd")
        if [[ "$framework" != "none" ]]; then
            if [[ -n "$advisory" ]]; then
                advisory="${advisory}. Production migration detected. Ensure this is intentional."
            else
                advisory="Production migration detected. Ensure this is intentional."
            fi
        fi
    fi

    printf '%s' "$advisory"
    return 0
}

# ---------------------------------------------------------------------------
# _db_detect_iac COMMAND
#
# Detects Infrastructure-as-Code commands that can destroy database infrastructure.
# Returns: "deny:<reason>", "advisory:<reason>", or "allow"
#
# Decision matrix:
#   terraform destroy              → deny (always)
#   terraform apply -auto-approve  → deny (bypasses human review)
#   terraform apply                → allow (terraform prompts interactively)
#   terraform plan                 → allow (read-only)
#   pulumi destroy                 → deny (always)
#   pulumi up --yes                → deny (bypasses confirmation)
#   pulumi up                      → allow (pulumi prompts interactively)
#   aws cloudformation delete-stack → deny (always)
#
# @decision DEC-DBSAFE-W2B-003
# @title terraform apply without -auto-approve is ALLOW (interactive prompt is the gate)
# @status accepted
# @rationale terraform apply prompts "Do you want to perform these actions?" before
#   executing. This human-in-the-loop confirmation is sufficient protection for
#   interactive use. Only -auto-approve bypasses it — that variant is denied.
#   terraform destroy always denies because there is no "selective" destroy;
#   it tears down all resources matching the state file.
# ---------------------------------------------------------------------------
_db_detect_iac() {
    local cmd="$1"

    # terraform destroy — always deny
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()terraform[[:space:]]+destroy'; then
        printf 'deny:terraform destroy tears down all infrastructure defined in the state file'
        return 0
    fi

    # terraform apply -auto-approve — deny (bypasses human review)
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()terraform[[:space:]]+apply.*-auto-approve'; then
        printf 'deny:terraform apply -auto-approve bypasses the human review prompt — infrastructure changes must be reviewed interactively'
        return 0
    fi

    # terraform apply (without -auto-approve) — allow (interactive prompt is the gate)
    # terraform plan — allow (read-only)
    # These are caught by the generic terraform check below only if explicitly denied above.
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()terraform[[:space:]]+(apply|plan)'; then
        printf 'allow'; return 0
    fi

    # pulumi destroy — always deny
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()pulumi[[:space:]]+destroy'; then
        printf 'deny:pulumi destroy tears down all infrastructure in the current stack'
        return 0
    fi

    # pulumi up --yes — deny (bypasses confirmation)
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()pulumi[[:space:]]+up.*--yes'; then
        printf 'deny:pulumi up --yes bypasses the confirmation prompt — infrastructure changes must be reviewed interactively'
        return 0
    fi

    # pulumi up (without --yes) — allow
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()pulumi[[:space:]]+up([[:space:]]|$)'; then
        printf 'allow'; return 0
    fi

    # aws cloudformation delete-stack — always deny
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()aws[[:space:]]+cloudformation[[:space:]]+delete-stack'; then
        printf 'deny:aws cloudformation delete-stack permanently destroys the CloudFormation stack and all its resources'
        return 0
    fi

    printf 'allow'
    return 0
}

# ---------------------------------------------------------------------------
# _db_detect_container COMMAND
#
# Detects container/volume destruction commands that can destroy persistent
# database storage.
#
# Returns: "deny:<reason>", "advisory:<reason>", or "allow"
#
# Decision matrix:
#   docker-compose down -v / --volumes → deny (deletes named volumes)
#   docker compose down -v / --volumes → deny (v2 plugin syntax)
#   docker-compose down (no flag)      → allow (stops containers, keeps volumes)
#   docker compose down (no flag)      → allow
#   docker volume rm                   → deny (always)
#   docker volume prune                → deny (removes ALL unused volumes)
#   docker volume ls/inspect           → allow (read-only)
#   kubectl delete pvc                 → deny (PVC deletion may trigger data loss)
#   kubectl delete pv                  → deny
#
# @decision DEC-DBSAFE-W2B-004
# @title Both docker-compose v1 and docker compose v2 syntax handled
# @status accepted
# @rationale Docker Compose v1 uses the hyphenated binary name (docker-compose).
#   Docker Compose v2 ships as a Docker CLI plugin using space-separated syntax
#   (docker compose). Both are in active use as of 2024. The -v / --volumes flag
#   check must cover both syntaxes. The grep pattern matches both with a single
#   expression by matching "docker[-[:space:]]compose".
# ---------------------------------------------------------------------------
_db_detect_container() {
    local cmd="$1"

    # docker-compose down -v / --volumes (v1 hyphenated binary)
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()docker-compose[[:space:]]+down'; then
        if printf '%s' "$cmd" | grep -qE 'docker-compose[[:space:]]+down.*(-v\b|--volumes\b)'; then
            printf 'deny:docker-compose down -v deletes named volumes, permanently destroying persistent database data'
            return 0
        fi
        printf 'allow'; return 0
    fi

    # docker compose down -v / --volumes (v2 plugin syntax)
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()docker[[:space:]]+compose[[:space:]]+down'; then
        if printf '%s' "$cmd" | grep -qE 'docker[[:space:]]+compose[[:space:]]+down.*(-v\b|--volumes\b)'; then
            printf 'deny:docker compose down -v deletes named volumes, permanently destroying persistent database data'
            return 0
        fi
        printf 'allow'; return 0
    fi

    # docker volume rm — always deny
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()docker[[:space:]]+volume[[:space:]]+rm([[:space:]]|$)'; then
        printf 'deny:docker volume rm permanently deletes the named volume and all data it contains'
        return 0
    fi

    # docker volume prune — always deny
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()docker[[:space:]]+volume[[:space:]]+prune([[:space:]]|$)'; then
        printf 'deny:docker volume prune removes ALL unused volumes — this may delete database volumes that are not currently attached to a running container'
        return 0
    fi

    # kubectl delete pvc — deny
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()kubectl[[:space:]]+delete[[:space:]]+pvc([[:space:]]|$)'; then
        printf 'deny:kubectl delete pvc deletes a PersistentVolumeClaim — data loss depends on the ReclaimPolicy (Retain vs Delete). Verify the PV ReclaimPolicy before proceeding.'
        return 0
    fi

    # kubectl delete pv — deny
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()kubectl[[:space:]]+delete[[:space:]]+pv([[:space:]]|$)'; then
        printf 'deny:kubectl delete pv deletes a PersistentVolume — this may permanently destroy the underlying storage'
        return 0
    fi

    printf 'allow'
    return 0
}

# ---------------------------------------------------------------------------
# _db_detect_orm COMMAND
#
# Detects ORM destructive patterns in bash command strings.
# Best-effort detection — catches what is visible in the command string.
#
# Returns: "deny:<reason>", "advisory:<reason>", or "allow"
#
# Patterns detected:
#   sequelize.sync({ force: true })  → advisory (drops+recreates all tables)
#   db.metadata.drop_all()           → advisory (SQLAlchemy drops all tables)
#   npm run seed                     → advisory if production environment
#   python seed.py                   → advisory if production environment
#
# @decision DEC-DBSAFE-W2B-005
# @title ORM detection is advisory-only (not deny) due to best-effort nature
# @status accepted
# @rationale ORM patterns are embedded in application code invoked via CLI.
#   We can only inspect the command string, not the code being executed.
#   False positives (a "seed" script that is read-only, a sync with force
#   that is intentional in dev) would create friction without clear benefit.
#   Advisory is appropriate: the user sees the warning and can confirm intent.
#   Seed scripts in production are the highest-risk detected pattern — they
#   can populate unexpected data or truncate existing data depending on
#   implementation. Production-env gating is the primary useful signal.
# ---------------------------------------------------------------------------
_db_detect_orm() {
    local cmd="$1"

    # sequelize.sync({ force: true }) — drops and recreates all tables
    if printf '%s' "$cmd" | grep -qE 'sequelize\.sync\(\s*\{[^}]*force\s*:\s*true'; then
        printf 'advisory:sequelize.sync({ force: true }) drops and recreates all tables, permanently destroying existing data'
        return 0
    fi

    # db.metadata.drop_all() — SQLAlchemy drops all tables
    if printf '%s' "$cmd" | grep -qE 'drop_all\s*\('; then
        printf 'advisory:drop_all() drops all tables defined in the SQLAlchemy metadata — permanent data loss'
        return 0
    fi

    # Seed scripts in production — advisory
    local env
    env=$(_db_detect_environment)
    if [[ "$env" == "production" || "$env" == "unknown" ]]; then
        # npm run seed
        if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()npm[[:space:]]+run[[:space:]]+seed([[:space:]]|$)'; then
            printf 'advisory:Running a seed script in production may overwrite or corrupt existing data. Verify this is intentional.'
            return 0
        fi
        # python seed.py (or python3 seed.py)
        if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|&&|\|\|?|;|\()python3?[[:space:]]+seed\.py([[:space:]]|$)'; then
            printf 'advisory:Running a seed script in production may overwrite or corrupt existing data. Verify this is intentional.'
            return 0
        fi
    fi

    printf 'allow'
    return 0
}
