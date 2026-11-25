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
# With EXPECT_INSTALL_FAILURE=1 (for shops on PHP below 8.1), the script
# instead checks that the module file loads without a fatal error and that
# install is refused with the "requires PHP 8.1" message:
#
#   PS81_TAG=8.1.7-7.4-apache EXPECT_INSTALL_FAILURE=1 make smoke V=81
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
MODULE="pensopay"
WAIT_SECONDS="${WAIT_SECONDS:-600}"
EXPECT_INSTALL_FAILURE="${EXPECT_INSTALL_FAILURE:-0}"

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

sql() {
  "${COMPOSE[@]}" exec -T -e MYSQL_PWD=prestashop "$DB" mariadb -uroot prestashop -Nse "$1"
}

# Prints the module's `active` value, or nothing if the module is not installed.
module_state() {
  sql "SELECT active FROM ps_module WHERE name = '${MODULE}'"
}

# Prints the module's id_module, or nothing if the module is not installed.
module_id() {
  sql "SELECT id_module FROM ps_module WHERE name = '${MODULE}'"
}

# Prints the names of the hooks the module is registered on, sorted, one per line.
module_hooks() {
  sql "SELECT DISTINCT h.name FROM ps_hook_module hm
       JOIN ps_hook h ON h.id_hook = hm.id_hook
       JOIN ps_module m ON m.id_module = hm.id_module
       WHERE m.name = '${MODULE}' ORDER BY h.name"
}

# Prints the number of hook registrations for a module id.
hook_rows_for_id() {
  sql "SELECT COUNT(*) FROM ps_hook_module WHERE id_module = $1"
}

shop_exec() {
  "${COMPOSE[@]}" exec -T "$SVC" "$@"
}

# Bootstraps PrestaShop and creates the module instance, as the back-office
# module page does. Fails on a fatal error, including a parse error.
check_module_loads() {
  local output status=0
  output="$(shop_exec php -r '
    define("_PS_ADMIN_DIR_", getcwd() . "/admin-dev");
    require "config/config.inc.php";
    $module = Module::getInstanceByName("'"$MODULE"'");
    echo is_object($module) ? "Loaded module: " . get_class($module) . PHP_EOL : "Module not found" . PHP_EOL;
  ' 2>&1)" || status=$?
  echo "$output"
  if [ "$status" -ne 0 ] || grep -qi 'fatal error\|parse error' <<<"$output"; then
    fail "loading $MODULE exited with $status or reported a fatal error"
  fi
  grep -q 'Loaded module: Pensopay' <<<"$output" || fail "$MODULE could not be loaded"
}

# Runs a module action and fails if the command fails or prints an error.
module_action() {
  local action="$1" output status=0
  output="$("${COMPOSE[@]}" exec -T "$SVC" php bin/console prestashop:module "$action" "$MODULE" 2>&1)" || status=$?
  echo "$output"
  if [ "$status" -ne 0 ]; then
    fail "'prestashop:module $action $MODULE' exited with $status"
  fi
  if grep -qi 'cannot' <<<"$output"; then
    fail "'prestashop:module $action $MODULE' reported an error"
  fi
}

if [ ! -f vendor/autoload.php ]; then
  echo "vendor/autoload.php is missing. Run 'composer install' first." >&2
  exit 1
fi

log "Starting $SVC ($("${COMPOSE[@]}" config --images | grep '^prestashop/'))"
"${COMPOSE[@]}" up -d

log "Waiting up to ${WAIT_SECONDS}s for the shop to finish installing on port $PORT"
deadline=$((SECONDS + WAIT_SECONDS))
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
echo "Shop is up (HTTP $code)."

if [ -n "$(module_state)" ]; then
  fail "$MODULE is already installed in $SVC. Uninstall it, or run 'make reset V=$V' for a clean shop."
fi

php_version="$(shop_exec php -r 'echo PHP_VERSION;')"
echo "Shop runs PHP $php_version."

if [ "$EXPECT_INSTALL_FAILURE" = "1" ]; then
  log "Checking that $MODULE loads without a fatal error on PHP $php_version"
  check_module_loads

  log "Installing $MODULE (expected to be refused)"
  status=0
  output="$(shop_exec php bin/console prestashop:module install "$MODULE" 2>&1)" || status=$?
  echo "$output"
  echo "(console exit code: $status)"
  state="$(module_state)"
  [ -z "$state" ] || fail "install should have been refused, but ps_module has a row with active = '${state}'"
  grep -q 'requires PHP 8.1' <<<"$output" || fail "install output does not contain 'requires PHP 8.1'"
  echo "OK: install was refused with the PHP version message, and nothing was written to ps_module."

  log "Smoke test passed for $SVC (install refused on PHP $php_version, as expected)"
  exit 0
fi

log "Installing $MODULE"
module_action install
state="$(module_state)"
[ "$state" = "1" ] || fail "after install, expected ps_module.active = 1, got '${state}'"
echo "OK: $MODULE is installed and active."

hooks="$(module_hooks)"
if [ "$hooks" != "$EXPECTED_HOOKS" ]; then
  echo "Expected hooks:"; echo "$EXPECTED_HOOKS"
  echo "Registered hooks:"; echo "${hooks:-(none)}"
  fail "registered hooks do not match the expected hooks"
fi
echo "OK: $MODULE is registered on all $(wc -l <<<"$EXPECTED_HOOKS" | tr -d ' ') expected hooks."

id="$(module_id)"

log "Uninstalling $MODULE"
module_action uninstall
state="$(module_state)"
[ -z "$state" ] || fail "after uninstall, expected no ps_module row, got active = '${state}'"
echo "OK: $MODULE is uninstalled."

rows="$(hook_rows_for_id "$id")"
[ "$rows" = "0" ] || fail "after uninstall, expected no ps_hook_module rows for id_module $id, got $rows"
echo "OK: no hook registrations remain."

log "Smoke test passed for $SVC"
