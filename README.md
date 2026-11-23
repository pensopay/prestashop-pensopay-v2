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

Every folder (except `vendor/` and `tests/`) needs an `index.php` that blocks directory listing. When you add a folder, copy the root `index.php` into it.

Development tools are installed under `require-dev` only. Build release zips with `composer install --no-dev`.

## Features

_To be added as features are implemented._

## License

Licensed under the [Academic Free License 3.0](LICENSE).
