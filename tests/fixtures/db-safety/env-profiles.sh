#!/usr/bin/env bash
# tests/fixtures/db-safety/env-profiles.sh — Environment test profiles for db-safety testing.
#
# Provides functions to set up different environment contexts that the db-safety
# hook uses to determine behavior (production = block, dev = warn, unknown = warn).
#
# Usage (source this file in test scripts):
#   source "$FIXTURES_DIR/db-safety/env-profiles.sh"
#   setup_prod_env
#   # run test expecting production-level blocking behavior
#   teardown_env
#
# Environment detection mirrors hooks/db-safety.sh logic:
#   - APP_ENV / RAILS_ENV / NODE_ENV / FLASK_ENV / DJANGO_ENV
#   - DATABASE_URL hostname pattern (prod-db, production, etc.)
#
# @decision DEC-DBSAFE-ENVPROFILE-001
# @title Env profiles mirror hooks/db-safety.sh detection logic exactly
# @status accepted
# @rationale The hook detects environment from multiple variables. Test profiles
#   must set the exact same variables the hook reads so tests are authoritative.
#   If the hook's detection logic changes, update env-profiles.sh to match.
#   DATABASE_URL is set to realistic hostnames so hostname-based detection works.

# ---------------------------------------------------------------------------
# Core profile setup functions
# ---------------------------------------------------------------------------

# setup_prod_env — simulate a production environment
# Hook behavior: block destructive commands (require explicit --force flag)
setup_prod_env() {
    export APP_ENV=production
    export RAILS_ENV=production
    export NODE_ENV=production
    export DATABASE_URL="postgresql://app_user:app_pass@prod-db.company.com:5432/myapp_production"
    unset FLASK_ENV DJANGO_ENV
}

# setup_staging_env — simulate a staging environment
# Hook behavior: warn on destructive commands but allow with confirmation
setup_staging_env() {
    export APP_ENV=staging
    export RAILS_ENV=staging
    export NODE_ENV=staging
    export DATABASE_URL="postgresql://app_user:app_pass@staging-db.company.com:5432/myapp_staging"
    unset FLASK_ENV DJANGO_ENV
}

# setup_dev_env — simulate a local development environment
# Hook behavior: warn only, allow through (dev mistakes are recoverable)
setup_dev_env() {
    export APP_ENV=development
    export RAILS_ENV=development
    export NODE_ENV=development
    export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/myapp_dev"
    unset FLASK_ENV DJANGO_ENV
}

# setup_test_env — simulate a test/CI environment
# Hook behavior: allow through (test DBs are ephemeral)
setup_test_env() {
    export APP_ENV=test
    export RAILS_ENV=test
    export NODE_ENV=test
    export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/myapp_test"
    unset FLASK_ENV DJANGO_ENV
}

# setup_unknown_env — simulate an environment where no env vars are set
# Hook behavior: warn (unknown = treat conservatively like staging)
setup_unknown_env() {
    unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV DJANGO_ENV
    unset DATABASE_URL
}

# ---------------------------------------------------------------------------
# Framework-specific profiles (for testing detection via non-APP_ENV vars)
# ---------------------------------------------------------------------------

# setup_flask_prod_env — Flask/Python production (uses FLASK_ENV)
setup_flask_prod_env() {
    export FLASK_ENV=production
    export DATABASE_URL="postgresql://flask_user:pass@prod-db.company.com:5432/flask_app"
    unset APP_ENV RAILS_ENV NODE_ENV DJANGO_ENV
}

# setup_django_prod_env — Django production (uses DJANGO_ENV or DJANGO_SETTINGS_MODULE)
setup_django_prod_env() {
    export DJANGO_ENV=production
    export DJANGO_SETTINGS_MODULE=myapp.settings.production
    export DATABASE_URL="postgresql://django_user:pass@prod-db.company.com:5432/django_app"
    unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV
}

# setup_url_only_prod_env — prod detected from DATABASE_URL hostname only (no APP_ENV)
# Tests the fallback detection path when only DATABASE_URL signals production.
setup_url_only_prod_env() {
    unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV DJANGO_ENV
    export DATABASE_URL="postgresql://user:pass@production-db.internal.company.com:5432/main"
}

# setup_url_only_local_env — local detected from DATABASE_URL hostname only
setup_url_only_local_env() {
    unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV DJANGO_ENV
    export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/myapp"
}

# ---------------------------------------------------------------------------
# teardown_env — restore original environment (call after test)
# In most cases, with_dbsafe_env from setup-test-env.sh handles this.
# Use teardown_env for standalone env setup/teardown without dbsafe_setup.
# ---------------------------------------------------------------------------
teardown_env() {
    unset APP_ENV RAILS_ENV NODE_ENV FLASK_ENV DJANGO_ENV
    unset DATABASE_URL DJANGO_SETTINGS_MODULE
}

# ---------------------------------------------------------------------------
# env_describe — return a short description of the current environment for
# test output and logging.
# ---------------------------------------------------------------------------
env_describe() {
    local env_indicator=""

    if [[ -n "${APP_ENV:-}" ]]; then
        env_indicator="APP_ENV=$APP_ENV"
    elif [[ -n "${RAILS_ENV:-}" ]]; then
        env_indicator="RAILS_ENV=$RAILS_ENV"
    elif [[ -n "${NODE_ENV:-}" ]]; then
        env_indicator="NODE_ENV=$NODE_ENV"
    elif [[ -n "${FLASK_ENV:-}" ]]; then
        env_indicator="FLASK_ENV=$FLASK_ENV"
    elif [[ -n "${DJANGO_ENV:-}" ]]; then
        env_indicator="DJANGO_ENV=$DJANGO_ENV"
    elif [[ -n "${DATABASE_URL:-}" ]]; then
        env_indicator="DATABASE_URL=<set>"
    else
        env_indicator="(no env vars set)"
    fi

    echo "$env_indicator"
}

# ---------------------------------------------------------------------------
# is_prod_env — returns 0 if current environment looks like production
# Mirrors the detection logic in hooks/db-safety.sh for test assertions.
# ---------------------------------------------------------------------------
is_prod_env() {
    local env_val="${APP_ENV:-${RAILS_ENV:-${NODE_ENV:-${FLASK_ENV:-${DJANGO_ENV:-}}}}}"
    local env_val_lower
    env_val_lower=$(echo "$env_val" | tr '[:upper:]' '[:lower:]')
    case "$env_val_lower" in
        production|prod)
            return 0
            ;;
    esac
    # Check DATABASE_URL for production hostname indicators
    if [[ -n "${DATABASE_URL:-}" ]]; then
        if echo "$DATABASE_URL" | grep -qiE '(prod|production)[^/]*\.' ; then
            return 0
        fi
    fi
    return 1
}
