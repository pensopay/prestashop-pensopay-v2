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

namespace PensoPay\PrestaShop\Tests\Unit\Api;

use PensoPay\PrestaShop\Api\ApiVersion;
use PHPUnit\Framework\TestCase;

final class ApiVersionTest extends TestCase
{
    public function testClassIsLoadedThroughComposerAutoloader(): void
    {
        self::assertTrue(class_exists(ApiVersion::class));
    }

    public function testTargetsApiV2(): void
    {
        self::assertSame('v2', ApiVersion::VERSION);
    }
}
