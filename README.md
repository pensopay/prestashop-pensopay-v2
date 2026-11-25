# Pensopay for PrestaShop

A PrestaShop payment module that lets merchants accept online payments through [Pensopay](https://pensopay.com).

## Status

Under development.

## Requirements

- PrestaShop
- PHP
- A Pensopay account and API key

## Installation

1. Copy the module into `modules/pensopay` in your PrestaShop installation.
2. Install it from **Modules > Module Manager** in the PrestaShop back office.
3. Enter your Pensopay API key in the module configuration.

## Development

The module supports PHP 8.1 and later. Composer resolves dependencies for PHP 8.1 (`config.platform.php`), even if you run a newer PHP locally.

```bash
composer install
```

| Command | What it does |
|---|---|
| `composer lint` | Checks code style (PHP-CS-Fixer, PrestaShop rules) |
| `composer lint:fix` | Fixes code style |
| `composer stan` | Runs static analysis (PHPStan, PHP 8.1 target) in Docker |
| `composer test` | Runs unit tests (PHPUnit) |

`composer stan` needs Docker. It runs PHPStan inside the official `prestashop/prestashop` image, so PHPStan can check the module against PrestaShop's core classes. The module is mounted read-only at `modules/pensopay`. By default it checks against PrestaShop 8.1, the oldest supported version. To check another version:

```bash
PS_VERSION=9.0 composer stan
```

The first run downloads the image (about 2 GB per PrestaShop version). Run `composer install` on your machine first, because the container uses the module's `vendor/`.

### Local environments

`docker-compose.yml` has one ready-to-use shop for each supported PrestaShop version. Each shop has its own database. The module folder is mounted into the shop, so code changes show up right away without a rebuild.

| PrestaShop | PHP | Profile | Shop | Back office |
|---|---|---|---|---|
| 8.1 | 8.1 | `ps81` | http://localhost:8081 | http://localhost:8081/admin-dev |
| 8.2 | 8.1 | `ps82` | http://localhost:8082 | http://localhost:8082/admin-dev |
| 9.0 | 8.4 | `ps90` | http://localhost:8090 | http://localhost:8090/admin-dev |
| 9.2 | 8.4 | `ps92` | http://localhost:8092 | http://localhost:8092/admin-dev |

Back office login: `demo@prestashop.com` / `prestashop_demo`. These credentials are for local use only. Never use them anywhere else.

Run `composer install` first, because the module loads `vendor/autoload.php`.

| Task | Make | Docker Compose |
|---|---|---|
| Start a shop | `make up V=81` | `docker compose --profile ps81 up -d` |
| Follow the logs | `make logs V=81` | `docker compose --profile ps81 logs -f ps81` |
| Stop a shop (keeps data) | `make down V=81` | `docker compose --profile ps81 down` |
| Reset a shop to a clean install | `make reset V=81` | `docker compose --profile ps81 down` then `docker volume rm pensopay_ps81_html pensopay_ps81_db` |
| Open a shell in the shop | `make shell V=81` | `docker compose --profile ps81 exec ps81 bash` |
| Install and uninstall the module and check both (the CI smoke test) | `make smoke V=81` | `.github/scripts/module-smoke-test.sh ps81` |

The first start downloads the image and installs the shop with demo data, which takes a few minutes. The shop is ready when the logs show Apache starting. Later starts are fast.

To switch versions, stop one shop and start another. You can also run several at once, because each one uses its own port.

To install the module, open **Modules > Module Manager**, search for "Pensopay" and click **Install**. Or run:

```bash
docker compose --profile ps81 exec ps81 php bin/console prestashop:module install pensopay
```

The shops listen on `127.0.0.1` only, and all image tags are pinned to exact versions.

To run a shop on a different PHP version, override its image tag with `PS81_TAG`, `PS82_TAG`, `PS90_TAG` or `PS92_TAG`, for example `PS92_TAG=9.2.1-6.1-classic-8.5-apache make up V=92`. CI uses this to test each PHP version. Run `make reset` first, because the shop's files live in a volume that was created from the previous image.

### Editor autocompletion

PrestaShop core classes such as `PaymentModule` are not a Composer package, so your editor can't find them in `vendor/`. Run `make ide-source` to copy the core source from the PrestaShop 8.1 image into `.prestashop/` (git ignores it). It uses 8.1 because that is the oldest supported version, so autocompletion only offers what 8.1 has.

PrestaShop's files declare classes with a `Core` suffix, such as `PaymentModuleCore`. PrestaShop creates the names modules use, such as `PaymentModule`, at runtime with `eval()`. Editors can't see those, so `make ide-source` also writes `.prestashop/aliases.php`, which declares each runtime name (`class PaymentModule extends PaymentModuleCore {}`). To look at another version, run for example `make ide-source IDE_V=92`.

Your editor may not index a hidden folder on its own, so add it to your editor's include path:

- **VS Code (PHP Tools by DEVSENSE):** add `"php.workspace.includePath": ".prestashop"` to `.vscode/settings.json`.
- **VS Code (Intelephense):** add `"intelephense.environment.includePaths": [".prestashop"]`.
- **PhpStorm:** **Settings > PHP > Include Path**, then add the `.prestashop` folder.

Every folder (except `vendor/` and `tests/`) needs an `index.php` that blocks directory listing. When you add a folder, copy the root `index.php` into it.

Development tools are installed under `require-dev` only. Build release zips with `composer install --no-dev`.

## CI

GitHub Actions ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs on every pull request and on pushes to `main` and `staging`. It tests each supported combination of PrestaShop and PHP:

| PrestaShop | PHP | Image (`prestashop/prestashop:`) |
|---|---|---|
| 8.1 | 8.1 | `8.1.7-8.1-apache` |
| 8.2 | 8.1 | `8.2.9-8.1-apache` |
| 9.0 | 8.1, 8.4 | `9.0.3-3.0-classic-8.1-apache`, `9.0.3-3.0-classic-8.4-apache` |
| 9.2 | 8.1, 8.4, 8.5 | `9.2.1-6.1-classic-8.1-apache`, `…-8.4-apache`, `…-8.5-apache` |

PrestaShop 9.0 supports PHP up to 8.4, and no PHP 8.5 image exists for it. PHP 8.5 is tested on 9.2 only.

Each job runs these steps in order. A job fails as soon as one step fails:

1. `composer lint`
2. `composer test`
3. `composer stan`, against the job's PrestaShop image
4. Starts the matching shop from `docker-compose.yml`, installs the module with the PrestaShop console, then uninstalls it. Each step is checked in the database, because PrestaShop 8.1's console exits with status 0 even when an install fails.

The **CI result** check passes only when every job passes. Branch protection on `main` and `staging` requires this check, so the protection rule stays the same when the matrix changes.

To run the install check locally, run `composer install` first, then:

```bash
make smoke V=81
```

To check a specific PHP version, also set the image tag. This command starts a fresh shop, so your existing local shop and its data are not touched. Stop your local shop for that version first (`make down V=92`), because both use the same port:

```bash
PS92_TAG=9.2.1-6.1-classic-8.5-apache COMPOSE_PROJECT_NAME=pensopay-smoke make smoke V=92
```

The check refuses to run if the module is already installed in the shop, so it never uninstalls a module you have set up. When you are done, delete the shop and its data with `COMPOSE_PROJECT_NAME=pensopay-smoke docker compose --profile ps92 down -v`.

All third-party actions are pinned to a full commit SHA. Dependabot opens a pull request each week to update them. The workflow uses no secrets.

## Features

_To be added as features are implemented._

## License

Licensed under the [Academic Free License 3.0](LICENSE).
