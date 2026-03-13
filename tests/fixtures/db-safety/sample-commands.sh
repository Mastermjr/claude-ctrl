#!/usr/bin/env bash
# tests/fixtures/db-safety/sample-commands.sh — Catalog of test commands for db-safety testing.
#
# Provides arrays of commands organized by expected behavior:
#   DB_CMDS_DESTRUCTIVE   — SQL/NoSQL commands that destroy data (should be blocked/warned)
#   DB_CMDS_SAFE          — Read-only or benign commands (should pass through)
#   DB_CMDS_IAC_DESTRUCTIVE — Infrastructure-as-Code commands that destroy volumes/DBs
#   DB_CMDS_MIGRATIONS    — Migration framework commands (legitimate schema changes, allowed)
#
# Usage (source this file in test scripts):
#   source "$FIXTURES_DIR/db-safety/sample-commands.sh"
#   for cmd in "${DB_CMDS_DESTRUCTIVE[@]}"; do
#     # assert hook blocks the command
#   done
#
# @decision DEC-DBSAFE-CATALOG-001
# @title Centralize command catalogs for consistent Wave 2+ test coverage
# @status accepted
# @rationale Without a canonical command list, each Wave 2 test author must invent
#   their own test cases, leading to coverage gaps and inconsistent edge cases.
#   This catalog is the single source of truth for "what the hook must block" and
#   "what it must allow." It is intentionally separate from setup-test-env.sh so
#   tests can source just the catalog without triggering full env setup.
#
# MAINTENANCE: When adding new destructive command patterns to hooks/db-safety.sh,
#   add corresponding test cases here. The Wave 2 tests iterate this catalog.

# =============================================================================
# Destructive SQL/NoSQL commands — hook MUST block or warn on these
# =============================================================================
DB_CMDS_DESTRUCTIVE=(
    # PostgreSQL
    'psql -c "DROP TABLE users"'
    'psql -c "DROP TABLE users CASCADE"'
    'psql -c "DROP DATABASE production"'
    'psql -c "TRUNCATE TABLE orders"'
    'psql -c "TRUNCATE TABLE orders RESTART IDENTITY CASCADE"'
    'psql -c "DELETE FROM sessions"'
    'psql -c "DELETE FROM users WHERE 1=1"'
    'psql -c "ALTER TABLE users DROP COLUMN email"'
    'psql production -c "DROP SCHEMA public CASCADE"'

    # MySQL
    'mysql -e "TRUNCATE TABLE orders"'
    'mysql -e "DROP TABLE users"'
    'mysql -e "DROP DATABASE myapp"'
    'mysql -e "DELETE FROM sessions WHERE 1=1"'
    'mysql -e "ALTER TABLE users DROP COLUMN email"'

    # Redis
    'redis-cli FLUSHALL'
    'redis-cli FLUSHDB'
    'redis-cli -n 0 FLUSHDB'

    # MongoDB
    'mongosh --eval "db.users.drop()"'
    'mongosh --eval "db.dropDatabase()"'
    'mongosh myapp --eval "db.orders.drop()"'

    # SQLite
    'sqlite3 app.db "DELETE FROM sessions"'
    'sqlite3 app.db "DROP TABLE users"'
    'sqlite3 app.db "TRUNCATE TABLE orders"'
)

# =============================================================================
# Safe SQL/NoSQL commands — hook MUST allow these through
# =============================================================================
DB_CMDS_SAFE=(
    # PostgreSQL read-only
    'psql -c "SELECT * FROM users LIMIT 10"'
    'psql -c "SELECT count(*) FROM orders"'
    'psql -c "\dt"'
    'psql -c "SELECT version()"'
    'psql -c "EXPLAIN SELECT * FROM users WHERE id = 1"'
    'psql -c "SHOW search_path"'

    # MySQL read-only
    'mysql -e "SHOW TABLES"'
    'mysql -e "SELECT * FROM users LIMIT 10"'
    'mysql -e "DESCRIBE users"'
    'mysql -e "SHOW STATUS"'

    # Redis read-only
    'redis-cli GET session:123'
    'redis-cli KEYS "cache:*"'
    'redis-cli INFO'
    'redis-cli DBSIZE'
    'redis-cli EXISTS session:123'

    # MongoDB read-only
    'mongosh --eval "db.users.find({})"'
    'mongosh --eval "db.users.find({}).limit(10)"'
    'mongosh --eval "db.getCollectionNames()"'
    'mongosh --eval "db.stats()"'

    # SQLite read-only
    'sqlite3 app.db "SELECT count(*) FROM users"'
    'sqlite3 app.db ".tables"'
    'sqlite3 app.db "SELECT * FROM sessions LIMIT 5"'
    'sqlite3 app.db "PRAGMA integrity_check"'
)

# =============================================================================
# Infrastructure-as-Code destructive commands — future Wave 2 scope
# These destroy volumes, databases, or infrastructure that may contain data.
# =============================================================================
DB_CMDS_IAC_DESTRUCTIVE=(
    # Terraform
    'terraform destroy'
    'terraform apply -destroy'
    'terraform destroy -auto-approve'

    # Pulumi
    'pulumi destroy'
    'pulumi destroy --yes'

    # Docker Compose (destroys named volumes with data)
    'docker-compose down -v'
    'docker-compose down --volumes'
    'docker compose down -v'

    # Docker volumes
    'docker volume rm pgdata'
    'docker volume rm myapp_postgres_data'
    'docker volume prune -f'

    # Kubernetes PVCs
    'kubectl delete pvc postgres-data'
    'kubectl delete pvc --all'
    'kubectl delete namespace production'
)

# =============================================================================
# Migration framework commands — MUST be allowed (legitimate schema changes)
# These use versioned, reversible migration systems — not raw destructive SQL.
# =============================================================================
DB_CMDS_MIGRATIONS=(
    # Rails ActiveRecord
    'rails db:migrate'
    'rake db:migrate'
    'rails db:migrate:up VERSION=20231015000001'

    # Alembic (Python/SQLAlchemy)
    'alembic upgrade head'
    'alembic upgrade +1'
    'alembic downgrade -1'

    # Prisma
    'prisma migrate deploy'
    'prisma migrate dev --name add_users_table'
    'npx prisma migrate deploy'

    # Flyway
    'flyway migrate'
    'flyway -url=jdbc:postgresql://localhost/myapp migrate'

    # Django
    'django-admin migrate'
    'python manage.py migrate'
    'python manage.py migrate --run-syncdb'

    # Liquibase
    'liquibase update'
    'liquibase --url=jdbc:postgresql://localhost/myapp update'

    # Knex.js
    'knex migrate:latest'
    'npx knex migrate:latest'

    # Sequelize
    'sequelize db:migrate'
    'npx sequelize-cli db:migrate'
)

# =============================================================================
# Convenience: all categories as a single array for comprehensive coverage
# =============================================================================
DB_CMDS_ALL_DESTRUCTIVE=("${DB_CMDS_DESTRUCTIVE[@]}" "${DB_CMDS_IAC_DESTRUCTIVE[@]}")

# =============================================================================
# Describe functions for test output readability
# =============================================================================

# dbcmds_describe CMD_STRING
#   Extract a short description from a command string for test labels.
dbcmds_describe() {
    local cmd="$1"
    # Extract the CLI name + first meaningful arg
    echo "$cmd" | sed 's/^[[:space:]]*//' | cut -c1-60
}

# dbcmds_get_cli CMD_STRING
#   Extract the CLI name from a command string (first word).
dbcmds_get_cli() {
    local cmd="$1"
    echo "$cmd" | awk '{print $1}'
}
