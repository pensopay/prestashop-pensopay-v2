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
| `composer stan` | Runs static analysis (PHPStan, PHP 8.1 target) |
| `composer test` | Runs unit tests (PHPUnit) |

`composer stan` uses PrestaShop's PHPStan extension. It needs `_PS_ROOT_DIR_` set to the path of a PrestaShop installation, so it can load PrestaShop classes:

```bash
_PS_ROOT_DIR_=/path/to/prestashop composer stan
```

Every folder (except `vendor/` and `tests/`) needs an `index.php` that blocks directory listing. When you add a folder, copy the root `index.php` into it.

Development tools are installed under `require-dev` only. Build release zips with `composer install --no-dev`.

## Features

_To be added as features are implemented._

## License

Licensed under the [Academic Free License 3.0](LICENSE).
