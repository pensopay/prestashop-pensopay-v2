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

The first start downloads the image and installs the shop with demo data, which takes a few minutes. The shop is ready when the logs show Apache starting. Later starts are fast.

To switch versions, stop one shop and start another. You can also run several at once, because each one uses its own port.

To install the module, open **Modules > Module Manager**, search for "Pensopay" and click **Install**. Or run:

```bash
docker compose --profile ps81 exec ps81 php bin/console prestashop:module install pensopay
```

The shops listen on `127.0.0.1` only, and all image tags are pinned to exact versions.

### Editor autocompletion

PrestaShop core classes such as `PaymentModule` are not a Composer package, so your editor can't find them in `vendor/`. Run `make ide-source` to copy the core source from the PrestaShop 8.1 image into `.prestashop/` (git ignores it). It uses 8.1 because that is the oldest supported version, so autocompletion only offers what 8.1 has.

PrestaShop's files declare classes with a `Core` suffix, such as `PaymentModuleCore`. PrestaShop creates the names modules use, such as `PaymentModule`, at runtime with `eval()`. Editors can't see those, so `make ide-source` also writes `.prestashop/aliases.php`, which declares each runtime name (`class PaymentModule extends PaymentModuleCore {}`). To look at another version, run for example `make ide-source IDE_V=92`.

Your editor may not index a hidden folder on its own, so add it to your editor's include path:

- **VS Code (PHP Tools by DEVSENSE):** add `"php.workspace.includePath": ".prestashop"` to `.vscode/settings.json`.
- **VS Code (Intelephense):** add `"intelephense.environment.includePaths": [".prestashop"]`.
- **PhpStorm:** **Settings > PHP > Include Path**, then add the `.prestashop` folder.

Every folder (except `vendor/` and `tests/`) needs an `index.php` that blocks directory listing. When you add a folder, copy the root `index.php` into it.

Development tools are installed under `require-dev` only. Build release zips with `composer install --no-dev`.

## Features

_To be added as features are implemented._

## License

Licensed under the [Academic Free License 3.0](LICENSE).
