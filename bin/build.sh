#!/usr/bin/env bash
#
# Builds the release zip for the PrestaShop module.
#
#   bin/build.sh 2.0.0        (or: make build VERSION=2.0.0)
#
# Writes build/pensopay-<version>.zip, with a top-level pensopay/ folder as
# PrestaShop requires. Without an argument, the version is taken from a git
# tag on HEAD (v2.0.0 or 2.0.0).
#
# Steps:
#   1. Copy the runtime files (RUNTIME_PATHS) into build/pensopay/. Only files
#      tracked by git are copied, so local files such as config.xml, caches and
#      .DS_Store never end up in the zip.
#   2. Run `composer install --no-dev --optimize-autoloader` inside the build
#      folder, so vendor/ holds production dependencies only. The vendor/ of
#      the working tree is not touched.
#   3. Remove dot files, add index.php to every vendor/ folder, and protect
#      vendor/ with an .htaccess.
#   4. Check the result, then zip it.
#
# The build fails if:
#   - a top-level path tracked by git is in neither RUNTIME_PATHS nor DEV_PATHS,
#     so a new folder is never left out of the zip by accident,
#   - any folder is missing an index.php,
#   - any PHP, JS, CSS or template file outside vendor/ is missing the license header,
#   - the version in pensopay.php does not match the release version.

set -euo pipefail

MODULE="pensopay"
MAIN_FILE="${MODULE}.php"

# Top-level paths that go into the zip.
RUNTIME_PATHS=(
  "$MAIN_FILE"
  index.php
  logo.png
  LICENSE
  controllers
  src
  translations
  upgrade
  views
)

# Top-level paths that stay out of the zip. composer.json and composer.lock
# are used to install vendor/ and then removed.
DEV_PATHS=(
  .gitattributes
  .github
  .gitignore
  .php-cs-fixer.dist.php
  Makefile
  README.md
  bin
  composer.json
  composer.lock
  docker-compose.yml
  phpstan.neon.dist
  phpunit.xml.dist
  tests
)

# Every file of these types outside vendor/ must contain both lines.
LICENSE_MARKERS=(
  "NOTICE OF LICENSE"
  "Academic Free License version 3.0"
)
# How far into a file the license header may start.
LICENSE_HEADER_LINES=20

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build"
STAGE_DIR="$BUILD_DIR/$MODULE"

log() { printf '\n==> %s\n' "$*"; }
fail() {
  echo "BUILD FAILED: $*" >&2
  exit 1
}

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# --- Release version ---------------------------------------------------------

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
  VERSION="${VERSION#v}"
  [ -n "$VERSION" ] || fail "no release version given and HEAD has no tag. Usage: $0 <version>, for example $0 2.0.0"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || fail "'$VERSION' is not a valid version. Use for example 2.0.0"

ZIP_PATH="$BUILD_DIR/${MODULE}-${VERSION}.zip"

for tool in composer git zip; do
  command -v "$tool" >/dev/null || fail "'$tool' is not installed"
done

log "Building $MODULE $VERSION"

# --- Version check -----------------------------------------------------------

module_version="$(sed -nE "s/^[[:space:]]*\\\$this->version[[:space:]]*=[[:space:]]*'([^']+)'.*/\1/p" "$MAIN_FILE")"
[ -n "$module_version" ] || fail "could not find \$this->version in $MAIN_FILE"
[ "$module_version" = "$VERSION" ] \
  || fail "$MAIN_FILE has version '$module_version', but the release version is '$VERSION'. Update \$this->version in $MAIN_FILE."
echo "OK: $MAIN_FILE has version $VERSION."

# --- Every top-level path is classified ---------------------------------------

unknown=()
while IFS= read -r top; do
  contains "$top" "${RUNTIME_PATHS[@]}" "${DEV_PATHS[@]}" || unknown+=("$top")
done < <(git ls-files | cut -d/ -f1 | sort -u)
if [ "${#unknown[@]}" -gt 0 ]; then
  printf '  %s\n' "${unknown[@]}" >&2
  fail "the paths above are not listed in RUNTIME_PATHS or DEV_PATHS in bin/build.sh. Add each to one of them."
fi
echo "OK: every tracked top-level path is listed as runtime or development."

if [ -n "$(git status --porcelain -- "${RUNTIME_PATHS[@]}" composer.json composer.lock)" ]; then
  echo "WARNING: runtime files have uncommitted changes or untracked files. Untracked files are left out; changes to tracked files are included." >&2
fi

# --- Copy runtime files ------------------------------------------------------

log "Copying runtime files into ${STAGE_DIR#"$ROOT"/}"
rm -rf "$STAGE_DIR" "$ZIP_PATH"
mkdir -p "$STAGE_DIR"

# git ls-files lists tracked files that still exist in the working tree.
git ls-files -z -- "${RUNTIME_PATHS[@]}" composer.json composer.lock \
  | while IFS= read -r -d '' file; do
      [ -e "$file" ] || continue
      mkdir -p "$STAGE_DIR/$(dirname "$file")"
      cp -p "$file" "$STAGE_DIR/$file"
    done

for path in "${RUNTIME_PATHS[@]}"; do
  [ -e "$STAGE_DIR/$path" ] || fail "runtime path '$path' is not tracked by git or does not exist"
done

# --- Production dependencies -------------------------------------------------

log "Installing production dependencies"
(
  cd "$STAGE_DIR"
  composer install --no-dev --optimize-autoloader \
    --no-interaction --no-progress --prefer-dist --no-scripts
)
rm -f "$STAGE_DIR/composer.json" "$STAGE_DIR/composer.lock"
[ -f "$STAGE_DIR/vendor/autoload.php" ] || fail "composer did not create vendor/autoload.php"

# --- Clean up and protect vendor/ --------------------------------------------

# Dot files and folders (.git, .github, .gitignore, .php-cs-fixer.dist.php, ...),
# including any inside vendor packages.
find "$STAGE_DIR" -mindepth 1 -name '.*' -prune -exec rm -rf {} +

# vendor/ is never served directly. Same rules as PrestaShop's own vendor/.htaccess.
cat >"$STAGE_DIR/vendor/.htaccess" <<'HTACCESS'
# Apache 2.2
<IfModule !mod_authz_core.c>
    Order deny,allow
    Deny from all
</IfModule>

# Apache 2.4
<IfModule mod_authz_core.c>
    Require all denied
</IfModule>
HTACCESS

# Third-party folders get a copy of the module's index.php. Folders outside
# vendor/ must have their own, committed index.php; that is checked below.
find "$STAGE_DIR/vendor" -type d | while IFS= read -r dir; do
  [ -f "$dir/index.php" ] || cp "$STAGE_DIR/index.php" "$dir/index.php"
done

# --- Checks ------------------------------------------------------------------

log "Checking the build"

missing_index="$(find "$STAGE_DIR" -type d -exec sh -c '[ -f "$1/index.php" ] || echo "$1"' _ {} \; \
  | sed "s|^$STAGE_DIR|$MODULE|")"
if [ -n "$missing_index" ]; then
  echo "$missing_index" >&2
  fail "the folders above have no index.php. Copy the root index.php into each."
fi
echo "OK: every folder has an index.php."

missing_license=()
while IFS= read -r -d '' file; do
  header="$(head -n "$LICENSE_HEADER_LINES" "$file")"
  for marker in "${LICENSE_MARKERS[@]}"; do
    if ! grep -qF "$marker" <<<"$header"; then
      missing_license+=("${file#"$STAGE_DIR"/}")
      break
    fi
  done
done < <(find "$STAGE_DIR" -path "$STAGE_DIR/vendor" -prune -o -type f \
  \( -name '*.php' -o -name '*.js' -o -name '*.css' -o -name '*.tpl' -o -name '*.twig' \) -print0)
if [ "${#missing_license[@]}" -gt 0 ]; then
  printf '  %s\n' "${missing_license[@]}" >&2
  fail "the files above have no license header in their first $LICENSE_HEADER_LINES lines. Copy the header from $MAIN_FILE."
fi
echo "OK: every PHP, JS, CSS and template file has the license header."

# --- Zip ---------------------------------------------------------------------

log "Creating ${ZIP_PATH#"$ROOT"/}"
(
  cd "$BUILD_DIR"
  # -X leaves out extra file attributes (uid/gid), so zips from different machines match.
  zip -qrX "$ZIP_PATH" "$MODULE"
)

echo "Built ${ZIP_PATH#"$ROOT"/} ($(zipinfo -1 "$ZIP_PATH" | grep -vc '/$') files)"
