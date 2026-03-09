#!/usr/bin/env bash
# test-db-safety-w2b.sh — Unit tests for db-safety-lib.sh Wave 2b
#
# Tests Wave 2b additions:
#   B5: _db_detect_migration() — migration framework allowlist (12 frameworks)
#   B6: _db_detect_iac() — IaC destructive command interception
#   B7: _db_detect_container() — container/volume destruction interception
#   B8: _db_detect_orm() — ORM destructive pattern detection
#
# Usage: bash tests/test-db-safety-w2b.sh
#
# @decision DEC-DBSAFE-W2B-TEST-001
# @title Test-first unit tests for db-safety-lib.sh Wave 2b functions
# @status accepted
# @rationale All tests source db-safety-lib.sh directly and call functions in
#   isolation. No mocks needed — the library has no external dependencies beyond
#   bash builtins and standard POSIX utilities. Environment variable state is
#   saved/restored around each test to ensure test isolation. Results format
#   matches Wave 1b (PASS/FAIL prefix) for run-hooks.sh aggregation compatibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/hooks"

# Source the library under test
source "$HOOKS_DIR/source-lib.sh"
require_db_safety

# --- Test harness ---
_T_PASSED=0
_T_FAILED=0

pass() { echo "  PASS: $1"; _T_PASSED=$((_T_PASSED + 1)); }
fail() { echo "  FAIL: $1 — $2"; _T_FAILED=$((_T_FAILED + 1)); }

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        pass "$test_name"
    else
        fail "$test_name" "expected to contain '$needle', got '$haystack'"
    fi
}

assert_starts_with() {
    local test_name="$1"
    local prefix="$2"
    local actual="$3"
    if [[ "$actual" == "$prefix"* ]]; then
        pass "$test_name"
    else
        fail "$test_name" "expected to start with '$prefix', got '$actual'"
    fi
}

# Save and restore environment around tests that set env vars
_save_env() {
    _SAVED_APP_ENV="${APP_ENV:-__UNSET__}"
    _SAVED_RAILS_ENV="${RAILS_ENV:-__UNSET__}"
    _SAVED_NODE_ENV="${NODE_ENV:-__UNSET__}"
    _SAVED_FLASK_ENV="${FLASK_ENV:-__UNSET__}"
    _SAVED_DATABASE_URL="${DATABASE_URL:-__UNSET__}"
    _SAVED_PGHOST="${PGHOST:-__UNSET__}"
    _SAVED_ENVIRONMENT="${ENVIRONMENT:-__UNSET__}"
}

_restore_env() {
    [[ "$_SAVED_APP_ENV" == "__UNSET__" ]] && unset APP_ENV || export APP_ENV="$_SAVED_APP_ENV"
    [[ "$_SAVED_RAILS_ENV" == "__UNSET__" ]] && unset RAILS_ENV || export RAILS_ENV="$_SAVED_RAILS_ENV"
    [[ "$_SAVED_NODE_ENV" == "__UNSET__" ]] && unset NODE_ENV || export NODE_ENV="$_SAVED_NODE_ENV"
    [[ "$_SAVED_FLASK_ENV" == "__UNSET__" ]] && unset FLASK_ENV || export FLASK_ENV="$_SAVED_FLASK_ENV"
    [[ "$_SAVED_DATABASE_URL" == "__UNSET__" ]] && unset DATABASE_URL || export DATABASE_URL="$_SAVED_DATABASE_URL"
    [[ "$_SAVED_PGHOST" == "__UNSET__" ]] && unset PGHOST || export PGHOST="$_SAVED_PGHOST"
    [[ "$_SAVED_ENVIRONMENT" == "__UNSET__" ]] && unset ENVIRONMENT || export ENVIRONMENT="$_SAVED_ENVIRONMENT"
}

echo "=== db-safety-lib.sh unit tests (Wave 2b) ==="
echo ""

# =============================================================================
# B5: _db_detect_migration — 12 frameworks
# =============================================================================
echo "--- B5: _db_detect_migration: framework detection ---"

# T01: Rails db:migrate
assert_eq "T01: rails db:migrate" "rails" "$(_db_detect_migration "rails db:migrate")"

# T02: Rails db:rollback
assert_eq "T02: rails db:rollback" "rails" "$(_db_detect_migration "rails db:rollback STEP=1")"

# T03: Rails db:schema:load
assert_eq "T03: rails db:schema:load" "rails" "$(_db_detect_migration "rails db:schema:load")"

# T04: rake db:migrate
assert_eq "T04: rake db:migrate" "rails" "$(_db_detect_migration "rake db:migrate")"

# T05: Django migrate
assert_eq "T05: python manage.py migrate" "django" "$(_db_detect_migration "python manage.py migrate")"

# T06: Django makemigrations
assert_eq "T06: python manage.py makemigrations" "django" "$(_db_detect_migration "python manage.py makemigrations myapp")"

# T07: Alembic upgrade
assert_eq "T07: alembic upgrade" "alembic" "$(_db_detect_migration "alembic upgrade head")"

# T08: Alembic downgrade
assert_eq "T08: alembic downgrade" "alembic" "$(_db_detect_migration "alembic downgrade -1")"

# T09: Alembic revision
assert_eq "T09: alembic revision" "alembic" "$(_db_detect_migration "alembic revision --autogenerate -m 'add users'")"

# T10: Prisma migrate deploy
assert_eq "T10: prisma migrate deploy" "prisma" "$(_db_detect_migration "prisma migrate deploy")"

# T11: Prisma migrate dev
assert_eq "T11: prisma migrate dev" "prisma" "$(_db_detect_migration "prisma migrate dev --name add_users")"

# T12: Prisma db push
assert_eq "T12: prisma db push" "prisma" "$(_db_detect_migration "prisma db push")"

# T13: Flyway migrate
assert_eq "T13: flyway migrate" "flyway" "$(_db_detect_migration "flyway migrate")"

# T14: Flyway repair
assert_eq "T14: flyway repair" "flyway" "$(_db_detect_migration "flyway repair")"

# T15: Flyway clean
assert_eq "T15: flyway clean" "flyway" "$(_db_detect_migration "flyway clean")"

# T16: Liquibase update
assert_eq "T16: liquibase update" "liquibase" "$(_db_detect_migration "liquibase update")"

# T17: Liquibase rollback
assert_eq "T17: liquibase rollback" "liquibase" "$(_db_detect_migration "liquibase rollback v1.0")"

# T18: Sequelize CLI
assert_eq "T18: npx sequelize-cli db:migrate" "sequelize" "$(_db_detect_migration "npx sequelize-cli db:migrate")"

# T19: Knex migrate latest
assert_eq "T19: npx knex migrate:latest" "knex" "$(_db_detect_migration "npx knex migrate:latest")"

# T20: Knex migrate rollback
assert_eq "T20: npx knex migrate:rollback" "knex" "$(_db_detect_migration "npx knex migrate:rollback")"

# T21: TypeORM migration run
assert_eq "T21: typeorm migration:run" "typeorm" "$(_db_detect_migration "typeorm migration:run")"

# T22: Goose up
assert_eq "T22: goose up" "goose" "$(_db_detect_migration "goose up")"

# T23: Goose down
assert_eq "T23: goose down" "goose" "$(_db_detect_migration "goose down")"

# T24: golang-migrate
assert_eq "T24: migrate -path" "golang-migrate" "$(_db_detect_migration "migrate -path ./migrations -database postgresql://localhost/mydb up")"

# T25: Drizzle Kit push
assert_eq "T25: drizzle-kit push" "drizzle-kit" "$(_db_detect_migration "drizzle-kit push")"

# T26: Drizzle Kit generate
assert_eq "T26: drizzle-kit generate" "drizzle-kit" "$(_db_detect_migration "drizzle-kit generate")"

# T27: Drizzle Kit migrate
assert_eq "T27: drizzle-kit migrate" "drizzle-kit" "$(_db_detect_migration "drizzle-kit migrate")"

# T28: non-migration command returns "none"
assert_eq "T28: non-migration returns none" "none" "$(_db_detect_migration "npm install")"

# T29: git push is not a migration
assert_eq "T29: git push is not migration" "none" "$(_db_detect_migration "git push origin main")"

echo ""

# =============================================================================
# B5 special cases — advisory flags
# =============================================================================
echo "--- B5: _db_detect_migration: special case advisories ---"

# T30: drizzle-kit push --force → advisory about skipping confirmation
_result=$(_db_detect_migration_advisory "drizzle-kit push --force")
assert_contains "T30: drizzle-kit push --force advisory" "skips confirmation" "$_result"

# T31: alembic downgrade base → advisory about reverting ALL migrations
_result=$(_db_detect_migration_advisory "alembic downgrade base")
assert_contains "T31: alembic downgrade base advisory" "reverts ALL migrations" "$_result"

# T32: flyway clean → advisory about dropping all objects
_result=$(_db_detect_migration_advisory "flyway clean")
assert_contains "T32: flyway clean advisory" "drops all objects" "$_result"

# T33: Normal migration in unknown/unset env gets production advisory (unknown = prod per spec)
# The spec: "Production environment + any migration → advisory". Default env = unknown = prod.
_save_env
unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV DATABASE_URL PGHOST ENVIRONMENT 2>/dev/null || true
_result=$(_db_detect_migration_advisory "rails db:migrate")
assert_contains "T33: normal migration in unknown env gets production advisory" "Production migration detected" "$_result"
_restore_env

echo ""

# =============================================================================
# B5 production environment advisory
# =============================================================================
echo "--- B5: _db_detect_migration: production advisory ---"

_save_env
unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV DATABASE_URL PGHOST ENVIRONMENT 2>/dev/null || true

# T34: production env + any migration → advisory
export APP_ENV=production
_result=$(_db_detect_migration_advisory "rails db:migrate")
assert_contains "T34: production migration advisory" "Production migration detected" "$_result"
unset APP_ENV

# T35: development env + migration → no production advisory
export APP_ENV=development
_result=$(_db_detect_migration_advisory "rails db:migrate")
if echo "$_result" | grep -qF "Production migration detected"; then
    fail "T35: dev migration no production advisory" "should not contain production advisory"
else
    pass "T35: dev migration no production advisory"
fi
unset APP_ENV

_restore_env
echo ""

# =============================================================================
# B6: _db_detect_iac — IaC command detection
# =============================================================================
echo "--- B6: _db_detect_iac: terraform ---"

# T36: terraform destroy → deny
_result=$(_db_detect_iac "terraform destroy")
assert_starts_with "T36: terraform destroy → deny" "deny:" "$_result"

# T37: terraform apply -auto-approve → deny (bypasses review)
_result=$(_db_detect_iac "terraform apply -auto-approve")
assert_starts_with "T37: terraform apply -auto-approve → deny" "deny:" "$_result"

# T38: terraform apply (interactive) → allow
_result=$(_db_detect_iac "terraform apply")
assert_eq "T38: terraform apply (interactive) → allow" "allow" "$_result"

# T39: terraform plan → allow (read-only)
_result=$(_db_detect_iac "terraform plan")
assert_eq "T39: terraform plan → allow" "allow" "$_result"

# T40: terraform apply -var 'foo=bar' (no -auto-approve) → allow
_result=$(_db_detect_iac "terraform apply -var 'foo=bar'")
assert_eq "T40: terraform apply with vars no -auto-approve → allow" "allow" "$_result"

echo ""
echo "--- B6: _db_detect_iac: pulumi ---"

# T41: pulumi destroy → deny
_result=$(_db_detect_iac "pulumi destroy")
assert_starts_with "T41: pulumi destroy → deny" "deny:" "$_result"

# T42: pulumi up --yes → deny (bypasses confirmation)
_result=$(_db_detect_iac "pulumi up --yes")
assert_starts_with "T42: pulumi up --yes → deny" "deny:" "$_result"

# T43: pulumi up (interactive) → allow
_result=$(_db_detect_iac "pulumi up")
assert_eq "T43: pulumi up (interactive) → allow" "allow" "$_result"

echo ""
echo "--- B6: _db_detect_iac: cloudformation ---"

# T44: aws cloudformation delete-stack → deny
_result=$(_db_detect_iac "aws cloudformation delete-stack --stack-name mystack")
assert_starts_with "T44: aws cloudformation delete-stack → deny" "deny:" "$_result"

# T45: non-IaC command returns allow
_result=$(_db_detect_iac "npm install")
assert_eq "T45: non-IaC command → allow" "allow" "$_result"

echo ""

# =============================================================================
# B7: _db_detect_container — container/volume destruction
# =============================================================================
echo "--- B7: _db_detect_container: docker-compose ---"

# T46: docker-compose down -v → deny (deletes named volumes)
_result=$(_db_detect_container "docker-compose down -v")
assert_starts_with "T46: docker-compose down -v → deny" "deny:" "$_result"

# T47: docker compose down -v (v2 plugin syntax) → deny
_result=$(_db_detect_container "docker compose down -v")
assert_starts_with "T47: docker compose down -v → deny" "deny:" "$_result"

# T48: docker-compose down (no -v) → allow
_result=$(_db_detect_container "docker-compose down")
assert_eq "T48: docker-compose down (no -v) → allow" "allow" "$_result"

# T49: docker compose down (v2, no -v) → allow
_result=$(_db_detect_container "docker compose down")
assert_eq "T49: docker compose down (no -v) → allow" "allow" "$_result"

echo ""
echo "--- B7: _db_detect_container: docker volume ---"

# T50: docker volume rm → deny
_result=$(_db_detect_container "docker volume rm myvolume")
assert_starts_with "T50: docker volume rm → deny" "deny:" "$_result"

# T51: docker volume prune → deny (removes ALL unused volumes)
_result=$(_db_detect_container "docker volume prune")
assert_starts_with "T51: docker volume prune → deny" "deny:" "$_result"

# T52: docker volume ls → allow (read-only)
_result=$(_db_detect_container "docker volume ls")
assert_eq "T52: docker volume ls → allow" "allow" "$_result"

echo ""
echo "--- B7: _db_detect_container: kubectl ---"

# T53: kubectl delete pvc → deny
_result=$(_db_detect_container "kubectl delete pvc my-claim")
assert_starts_with "T53: kubectl delete pvc → deny" "deny:" "$_result"

# T54: kubectl delete pv → deny
_result=$(_db_detect_container "kubectl delete pv my-volume")
assert_starts_with "T54: kubectl delete pv → deny" "deny:" "$_result"

# T55: kubectl get pvc → allow
_result=$(_db_detect_container "kubectl get pvc")
assert_eq "T55: kubectl get pvc → allow" "allow" "$_result"

# T56: non-container command returns allow
_result=$(_db_detect_container "ls -la")
assert_eq "T56: non-container command → allow" "allow" "$_result"

echo ""

# =============================================================================
# B8: _db_detect_orm — ORM destructive patterns
# =============================================================================
echo "--- B8: _db_detect_orm: ORM patterns ---"

# T57: sequelize sync force → advisory
_result=$(_db_detect_orm "node -e \"sequelize.sync({ force: true })\"")
assert_starts_with "T57: sequelize sync force → advisory" "advisory:" "$_result"

# T58: db.metadata.drop_all() → advisory
_result=$(_db_detect_orm "python3 -c 'db.metadata.drop_all(engine)'")
assert_starts_with "T58: db.metadata.drop_all() → advisory" "advisory:" "$_result"

# T59: npm run seed in non-production → allow
_save_env
unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV DATABASE_URL PGHOST ENVIRONMENT 2>/dev/null || true
export APP_ENV=development
_result=$(_db_detect_orm "npm run seed")
assert_eq "T59: npm run seed in development → allow" "allow" "$_result"
unset APP_ENV

# T60: npm run seed in production → advisory
export APP_ENV=production
_result=$(_db_detect_orm "npm run seed")
assert_starts_with "T60: npm run seed in production → advisory" "advisory:" "$_result"
unset APP_ENV

# T61: python seed.py in production → advisory
export APP_ENV=production
_result=$(_db_detect_orm "python seed.py")
assert_starts_with "T61: python seed.py in production → advisory" "advisory:" "$_result"
unset APP_ENV

# T62: python seed.py in development → allow
export APP_ENV=development
_result=$(_db_detect_orm "python seed.py")
assert_eq "T62: python seed.py in development → allow" "allow" "$_result"
unset APP_ENV
_restore_env

# T63: non-ORM command returns allow
_result=$(_db_detect_orm "rails server")
assert_eq "T63: non-ORM command → allow" "allow" "$_result"

echo ""

# =============================================================================
# Edge cases and compound commands
# =============================================================================
echo "--- Edge cases ---"

# T64: migration framework in subshell
assert_eq "T64: rails migrate in subshell" "rails" \
    "$(_db_detect_migration "(cd /app && rails db:migrate)")"

# T65: python3 manage.py migrate (python3 variant)
assert_eq "T65: python3 manage.py migrate" "django" \
    "$(_db_detect_migration "python3 manage.py migrate")"

# T66: rake db:create is a Rails framework command (rake db:* pattern per spec)
# The PRD allowlist includes "rake db:*" generically for the Rails framework.
_result=$(_db_detect_migration "rake db:create")
assert_eq "T66: rake db:create → rails (rake db:* is Rails framework per spec)" "rails" "$_result"

# T67: rake db:migrate:status matches rails
assert_eq "T67: rake db:migrate:status" "rails" \
    "$(_db_detect_migration "rake db:migrate:status")"

# T68: docker compose down --volumes (long flag) → deny
_result=$(_db_detect_container "docker compose down --volumes")
assert_starts_with "T68: docker compose down --volumes → deny" "deny:" "$_result"

# T69: docker-compose down --volumes (long flag, v1) → deny
_result=$(_db_detect_container "docker-compose down --volumes")
assert_starts_with "T69: docker-compose down --volumes (v1) → deny" "deny:" "$_result"

# T70: terraform destroy -auto-approve → deny
_result=$(_db_detect_iac "terraform destroy -auto-approve")
assert_starts_with "T70: terraform destroy -auto-approve → deny" "deny:" "$_result"

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "==========================="
echo "Results: $((_T_PASSED + _T_FAILED)) total | Passed: $_T_PASSED | Failed: $_T_FAILED"
echo ""

if [[ $_T_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
