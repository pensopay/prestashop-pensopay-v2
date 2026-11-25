#!/usr/bin/env bash
#
# Smoke test: start a PrestaShop shop from docker-compose.yml, install the
# module through the PrestaShop console, uninstall it, and check both steps.
#
#   .github/scripts/module-smoke-test.sh ps81    (or: make smoke V=81)
#
# Override the image with PS81_TAG, PS82_TAG, PS90_TAG or PS92_TAG to test
# another PHP version. The shop is left running; stop it with `make down`.
#
# After install, every hook in EXPECTED_HOOKS must be registered. After
# uninstall, no hook registrations may remain.
#
# Set LEGACY_PHP_TAG to an image of the same PrestaShop version on PHP below
# 8.1 to also test the PHP version guard. The script then installs the module,
# switches the same shop to that image (no reinstall of PrestaShop), and checks
# that the module loads with a warning, can be uninstalled, and refuses to
# install again. Afterwards it switches the shop back.
#
#   LEGACY_PHP_TAG=8.1.7-7.4-apache make smoke V=81
#
# The console command is not trusted on its own: on PrestaShop 8.1,
# `prestashop:module install` exits 0 even when the install fails. Each step
# is therefore also checked in the database.

set -euo pipefail

SVC="${1:-}"
case "$SVC" in
  ps81 | ps82 | ps90 | ps92) ;;
  *)
    echo "Usage: $0 ps81|ps82|ps90|ps92" >&2
    exit 2
    ;;
esac

V="${SVC#ps}"
DB="db${V}"
PORT="80${V}"
TAG_VAR="PS${V}_TAG"
MODULE="pensopay"
WAIT_SECONDS="${WAIT_SECONDS:-600}"
LEGACY_PHP_TAG="${LEGACY_PHP_TAG:-}"

# Keep in sync with Pensopay::HOOKS in pensopay.php. Sorted, to compare with the query output.
EXPECTED_HOOKS="actionFrontControllerSetMedia
actionOrderStatusUpdate
displayAdminOrderMain
displayPaymentReturn
paymentOptions"

cd "$(dirname "$0")/../.."

COMPOSE=(docker compose --profile "$SVC")

log() { printf '\n==> %s\n' "$*"; }

fail() {
  echo "FAIL: $*" >&2
  log "Shop container logs (last 200 lines)"
  "${COMPOSE[@]}" logs --no-color --tail 200 "$SVC" || true
  log "PrestaShop logs (var/logs)"
  "${COMPOSE[@]}" exec -T "$SVC" sh -c 'tail -n 100 var/logs/*.log 2>/dev/null || echo "(no log files)"' || true
  exit 1
}

shop_exec() { "${COMPOSE[@]}" exec -T "$SVC" "$@"; }
sql() { "${COMPOSE[@]}" exec -T -e MYSQL_PWD=prestashop "$DB" mariadb -uroot prestashop -Nse "$1"; }

# Prints the module's `active` value, or nothing if the module is not installed.
module_state() { sql "SELECT active FROM ps_module WHERE name = '${MODULE}'"; }
module_id() { sql "SELECT id_module FROM ps_module WHERE name = '${MODULE}'"; }

# Prints the names of the hooks the module is registered on, sorted, one per line.
module_hooks() {
  sql "SELECT DISTINCT h.name FROM ps_hook_module hm
       JOIN ps_hook h ON h.id_hook = hm.id_hook
       JOIN ps_module m ON m.id_module = hm.id_module
       WHERE m.name = '${MODULE}' ORDER BY h.name"
}

# Starts the shop, with the image tag in $1 if given, and waits until it answers.
start_shop() {
  if [ -n "${1:-}" ]; then
    export "$TAG_VAR=$1"
  fi
  log "Starting $SVC ($("${COMPOSE[@]}" config --images | grep '^prestashop/'))"
  "${COMPOSE[@]}" up -d

  local code deadline=$((SECONDS + WAIT_SECONDS))
  until code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: localhost:$PORT" "http://127.0.0.1:$PORT/")" \
    && [[ "$code" =~ ^(200|301|302)$ ]]; do
    if [ -z "$("${COMPOSE[@]}" ps --status running -q "$SVC")" ]; then
      fail "$SVC stopped before the shop was ready"
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      fail "shop not ready after ${WAIT_SECONDS}s (last HTTP status: ${code:-none})"
    fi
    sleep 5
  done
  PHP_VERSION="$(shop_exec php -r 'echo PHP_VERSION;')"
  echo "Shop is up (HTTP $code) on PHP $PHP_VERSION."
}

# Runs a console module action. Prints its output and sets ACTION_OUTPUT.
# Fails if the command exits non-zero, unless $2 is "allow-failure".
module_action() {
  local status=0
  ACTION_OUTPUT="$(shop_exec php bin/console prestashop:module "$1" "$MODULE" 2>&1)" || status=$?
  echo "$ACTION_OUTPUT"
  if [ "$status" -ne 0 ] && [ "${2:-}" != "allow-failure" ]; then
    fail "'prestashop:module $1 $MODULE' exited with $status"
  fi
}

install_and_check() {
  log "Installing $MODULE on PHP $PHP_VERSION"
  module_action install
  if grep -qi 'cannot' <<<"$ACTION_OUTPUT"; then fail "install reported an error"; fi
  local state hooks
  state="$(module_state)"
  [ "$state" = "1" ] || fail "after install, expected ps_module.active = 1, got '${state}'"
  echo "OK: $MODULE is installed and active."

  hooks="$(module_hooks)"
  if [ "$hooks" != "$EXPECTED_HOOKS" ]; then
    echo "Expected hooks:"; echo "$EXPECTED_HOOKS"
    echo "Registered hooks:"; echo "${hooks:-(none)}"
    fail "registered hooks do not match the expected hooks"
  fi
  echo "OK: $MODULE is registered on all expected hooks."
}

uninstall_and_check() {
  local id state rows
  id="$(module_id)"
  log "Uninstalling $MODULE on PHP $PHP_VERSION"
  module_action uninstall
  if grep -qi 'cannot' <<<"$ACTION_OUTPUT"; then fail "uninstall reported an error"; fi
  state="$(module_state)"
  [ -z "$state" ] || fail "after uninstall, expected no ps_module row, got active = '${state}'"
  rows="$(sql "SELECT COUNT(*) FROM ps_hook_module WHERE id_module = ${id}")"
  [ "$rows" = "0" ] || fail "after uninstall, expected no ps_hook_module rows for id_module $id, got $rows"
  echo "OK: $MODULE is uninstalled and no hook registrations remain."
}

# Bootstraps PrestaShop and creates the module instance, as the back-office
# module page does. Fails on a fatal error, including a parse error.
# Prints the module's warning, which the module list shows.
check_module_loads() {
  local output status=0
  log "Loading $MODULE like the module page does, on PHP $PHP_VERSION"
  output="$(shop_exec php -r '
    define("_PS_ADMIN_DIR_", getcwd() . "/admin-dev");
    require "config/config.inc.php";
    $module = Module::getInstanceByName("'"$MODULE"'");
    echo is_object($module) ? "Loaded module: " . get_class($module) . PHP_EOL . "Warning: " . $module->warning . PHP_EOL : "Module not found" . PHP_EOL;
  ' 2>&1)" || status=$?
  echo "$output"
  if [ "$status" -ne 0 ] || grep -qi 'fatal error\|parse error' <<<"$output"; then
    fail "loading $MODULE exited with $status or reported a fatal error"
  fi
  grep -q 'Loaded module: Pensopay' <<<"$output" || fail "$MODULE could not be loaded"
  MODULE_WARNING="$(sed -n 's/^Warning: //p' <<<"$output")"
}

if [ ! -f vendor/autoload.php ]; then
  echo "vendor/autoload.php is missing. Run 'composer install' first." >&2
  exit 1
fi

start_shop
if [ -n "$(module_state)" ]; then
  fail "$MODULE is already installed in $SVC. Uninstall it, or run 'make reset V=$V' for a clean shop."
fi

install_and_check
uninstall_and_check

if [ -n "$LEGACY_PHP_TAG" ]; then
  # Installed on a supported PHP, then the server is downgraded.
  install_and_check
  original_tag="${!TAG_VAR:-}"
  start_shop "$LEGACY_PHP_TAG"

  check_module_loads
  grep -q 'requires PHP 8.1' <<<"$MODULE_WARNING" \
    || fail "expected the module list warning to contain 'requires PHP 8.1', got '${MODULE_WARNING}'"
  echo "OK: the module list shows the PHP version warning."

  uninstall_and_check

  log "Installing $MODULE on PHP $PHP_VERSION (expected to be refused)"
  module_action install allow-failure
  state="$(module_state)"
  [ -z "$state" ] || fail "install should have been refused, but ps_module has a row with active = '${state}'"
  grep -q 'requires PHP 8.1' <<<"$ACTION_OUTPUT" || fail "install output does not contain 'requires PHP 8.1'"
  echo "OK: install was refused with the PHP version message, and nothing was written to ps_module."

  # Leave the shop on the image it started with.
  if [ -n "$original_tag" ]; then
    start_shop "$original_tag"
  else
    unset "$TAG_VAR"
    start_shop
  fi
fi

log "Smoke test passed for $SVC"
