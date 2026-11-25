<?php

/**
 * NOTICE OF LICENSE
 *
 * This source file is subject to the Academic Free License version 3.0
 * that is bundled with this package in the file LICENSE.
 * It is also available through the world-wide-web at this URL:
 * https://opensource.org/licenses/AFL-3.0
 *
 * @author    Pensopay <support@pensopay.com>
 * @copyright Since 2026 Pensopay
 * @license   https://opensource.org/licenses/AFL-3.0 Academic Free License version 3.0
 */
declare(strict_types=1);

// Every file in src/ exits unless _PS_VERSION_ is defined, as it is when
// PrestaShop is loaded. Unit tests run without PrestaShop, so define it here.
if (!defined('_PS_VERSION_')) {
    define('_PS_VERSION_', '8.1.0');
}

require_once dirname(__DIR__) . '/vendor/autoload.php';
