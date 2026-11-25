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

namespace PensoPay\PrestaShop\Api;

if (!defined('_PS_VERSION_')) {
    exit;
}

/**
 * Version of the Pensopay API that the module targets.
 */
final class ApiVersion
{
    public const VERSION = 'v2';
}
