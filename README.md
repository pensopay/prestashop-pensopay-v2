# Pensopay for PrestaShop

A PrestaShop payment module that lets merchants accept online payments through [Pensopay](https://pensopay.com). Under development.

## Requirements

- PrestaShop 8.1.0 or later
- PHP 8.1 or later
- A Pensopay account and API key

On PHP below 8.1 the module refuses to install. If it is already installed, the module list shows a warning and it can still be uninstalled.

## Installation

1. Copy the module into `modules/pensopay` in your PrestaShop installation.
2. Install it from **Modules > Module Manager** in the back office.
3. Enter your Pensopay API key in the module configuration.

## Development

### Quick start

```bash
composer install     # the module needs vendor/autoload.php, also inside the shop
make up V=81         # start a PrestaShop 8.1 shop with the module mounted
```

The first start downloads the image and installs the shop, which takes a few minutes. Then open http://localhost:8081/admin-dev (`demo@prestashop.com` / `prestashop_demo`, local use only) and install the module from **Modules > Module Manager**. Code changes show up right away.

### Commands

| Command | What it does |
|---|---|
| `composer lint` / `lint:fix` | Check / fix code style (PHP-CS-Fixer, PrestaShop rules) |
| `composer test` | Unit tests (PHPUnit) |
| `composer stan` | PHPStan inside the PrestaShop 8.1 Docker image, so it sees core classes. Another version: `PS_VERSION=<image tag> composer stan` |
| `make up` / `down` / `logs` / `shell` | Start, stop, follow logs of, or open a shell in a shop |
| `make reset` | Delete a shop and its database, for a clean install on the next start |
| `make smoke` | Install and uninstall the module and check the database, as CI does |
| `make ide-source` | Copy PrestaShop core source into `.prestashop/` for editor autocompletion |

All `make` targets take `V=81`, `82`, `90` or `92` (default `81`). Run `make` on its own to list them.

### Supported versions

| PrestaShop | Local shop | Local PHP | Tested in CI on PHP |
|---|---|---|---|
| 8.1 | http://localhost:8081 | 8.1 | 8.1 (and 7.4 for the version guard) |
| 8.2 | http://localhost:8082 | 8.1 | 8.1 |
| 9.0 | http://localhost:8090 | 8.4 | 8.1, 8.4 |
| 9.2 | http://localhost:8092 | 8.4 | 8.1, 8.4, 8.5 |

The back office is at `/admin-dev` on each shop. The exact image tags are pinned in [docker-compose.yml](docker-compose.yml) and [ci.yml](.github/workflows/ci.yml). To run a local shop on another PHP version, override its tag, for example `PS92_TAG=9.2.1-6.1-classic-8.5-apache make up V=92`. Run `make reset` first, because the shop's files live in a volume created from the previous image.

### Code conventions

- **[pensopay.php](pensopay.php) and [upgrade/](upgrade/) scripts must parse on PHP 7.2.** PrestaShop 8.x runs on PHP 7.2+ and includes these files before the module's PHP version check can run, so a parse error breaks the back office. Avoid typed properties, arrow functions, `??=`, union types, `mixed`, enums, `readonly`, `match`, `?->`, named arguments, constructor promotion and attributes. Put modern code in `src/`, which loads only on PHP 8.1+. Upgrade scripts must check the PHP version before touching `src/` and return `false` if it is too old. CI checks both with `php -l` on PHP 7.2.
- **Every PHP file in `src/`** has the direct-access guard right after its `namespace` line: `if (!defined('_PS_VERSION_')) { exit; }`. [tests/bootstrap.php](tests/bootstrap.php) defines `_PS_VERSION_` for unit tests.
- **Every folder** except `vendor/` and `tests/` needs an `index.php` that blocks directory listing. Copy the root `index.php` into new folders.

### Smoke test

`make smoke V=81` starts the shop, installs and uninstalls the module, and checks each step in the database. It refuses to run if the module is already installed, so it never touches a module you have set up.

To test without touching your local shop, use a separate Compose project. It uses the same port, so stop your local shop for that version first:

```bash
PS92_TAG=9.2.1-6.1-classic-8.5-apache COMPOSE_PROJECT_NAME=pensopay-smoke make smoke V=92
COMPOSE_PROJECT_NAME=pensopay-smoke docker compose --profile ps92 down -v   # clean up afterwards
```

To also test the PHP version guard, as CI does on PrestaShop 8.1: `LEGACY_PHP_TAG=8.1.7-7.4-apache make smoke V=81`.

### Editor autocompletion

PrestaShop core classes aren't a Composer package, so editors can't find them. `make ide-source` copies the core source from the 8.1 image into `.prestashop/` (ignored by git) and writes `.prestashop/aliases.php`, which declares the runtime class names such as `PaymentModule`. Add the folder to your editor's include path:

- **VS Code (PHP Tools by DEVSENSE):** `"php.workspace.includePath": ".prestashop"` in `.vscode/settings.json`
- **VS Code (Intelephense):** `"intelephense.environment.includePaths": [".prestashop"]`
- **PhpStorm:** **Settings > PHP > Include Path**, add `.prestashop`

### CI

[ci.yml](.github/workflows/ci.yml) runs on every pull request and on pushes to `main` and `staging`:

1. **Checks** (about a minute): lint, unit tests, and the PHP 7.2 syntax check.
2. **One smoke job per PrestaShop/PHP combination** in the table above, using a `vendor/` without dev dependencies, like a release. The PHP 8.1 job of each PrestaShop version also runs PHPStan. The PrestaShop 8.1 job also switches the shop to PHP 7.4 and checks that the version guard works.

Branch protection requires only the **CI result** check, which passes when every job passes. Actions are pinned to commit SHAs and updated weekly by Dependabot. The comments in `ci.yml` explain the details.

### Releases

The release version is `$this->version` in [pensopay.php](pensopay.php). Build the zip with:

```bash
make build             # or: bin/build.sh
```

This writes `build/pensopay-<version>.zip` with a top-level `pensopay/` folder. Bump the version only for an actual release: rebuilding while testing is fine. If the zip already exists, the script asks before overwriting it (`make build FORCE=1` or `bin/build.sh --force` skips the question; without a terminal it fails instead). `make build VERSION=2.0.0` checks that `pensopay.php` has that version, and a git tag on HEAD (`v2.0.0` or `2.0.0`) must match it too. It copies only the runtime files tracked by git, installs production dependencies with `composer install --no-dev --optimize-autoloader` in the build folder (your own `vendor/` is left alone), removes dot files, and adds `index.php` and an `.htaccess` to `vendor/`.

The build fails if:

- a version given on the command line, or a git tag on HEAD, does not match `pensopay.php`,
- a folder has no `index.php`,
- a PHP, JS, CSS or template file outside `vendor/` has no license header,
- a new top-level file or folder is not listed in `RUNTIME_PATHS` or `DEV_PATHS` in [bin/build.sh](bin/build.sh). Add it to one of the two lists to choose whether it goes in the zip.

## License

Licensed under the [Academic Free License 3.0](LICENSE).
