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
use PrestaShop\PrestaShop\Core\Payment\PaymentOption;

if (!defined('_PS_VERSION_')) {
    exit;
}

// The Composer autoloader (and its platform_check.php, which stops PHP below 8.1)
// is loaded only on PHP 8.1+.
if (PHP_VERSION_ID >= 80100 && file_exists(__DIR__ . '/vendor/autoload.php')) {
    require_once __DIR__ . '/vendor/autoload.php';
}

/**
 * Keep this file parseable on PHP 7.2 — modern code belongs in src/.
 *
 * PrestaShop 8.x runs on PHP 7.2+ and includes this file to build the module
 * list, so a parse error here would break the back office before the PHP
 * version check below could run. `php -l` on PHP 7.2 checks this in CI.
 */
class Pensopay extends PaymentModule
{
    private const MIN_PHP_VERSION_ID = 80100;
    private const MIN_PHP_VERSION = '8.1';

    private const CONFIG_API_KEY = 'PENSOPAY_API_KEY';

    /**
     * Hooks registered on install.
     */
    private const HOOKS = [
        'paymentOptions',
        'displayPaymentReturn',
        'displayAdminOrderMain',
        'actionOrderStatusUpdate',
        'actionFrontControllerSetMedia',
    ];

    public function __construct()
    {
        $this->name = 'pensopay';
        $this->tab = 'payments_gateways';
        $this->version = '0.1.2';
        $this->author = 'Pensopay A/S';
        $this->need_instance = 0;
        $this->ps_versions_compliancy = ['min' => '8.1.0', 'max' => _PS_VERSION_];
        $this->bootstrap = true;

        parent::__construct();

        $this->displayName = $this->trans('Pensopay Payments', [], 'Modules.Pensopay.Admin');
        $this->description = $this->trans('Accept online payments with Pensopay.', [], 'Modules.Pensopay.Admin');

        // $this->id is set only when the module is installed. Warn in the module list instead of failing.
        if (!self::isPhpVersionSupported() && $this->id) {
            $this->warning = $this->getPhpVersionError();
        }
    }

    public function isUsingNewTranslationSystem(): bool
    {
        return true;
    }

    public function install(): bool
    {
        // Checked before parent::install() so nothing is written to the database.
        if (!self::isPhpVersionSupported()) {
            $this->_errors[] = $this->getPhpVersionError();

            return false;
        }

        return parent::install() && $this->registerHook(self::HOOKS);
    }

    /**
     * Must work on any PHP version, so it never touches src/ or vendor/.
     * parent::uninstall() removes the hook registrations.
     */
    public function uninstall(): bool
    {
        foreach (self::getConfigurationKeys() as $key) {
            Configuration::deleteByName($key);
        }

        return parent::uninstall();
    }

    /**
     * @param array<string, mixed> $params
     *
     * @return PaymentOption[]
     */
    public function hookPaymentOptions(array $params): array
    {
        // Without an API key no payment can be created, so the option is not offered.
        if (!self::isPhpVersionSupported() || !$this->active || !Configuration::get(self::CONFIG_API_KEY)) {
            return [];
        }

        // PrestaShop 9.2 types $this->context as nullable, older versions do not.
        // The @var gives PHPStan the same type on every version.
        /** @var Context|null $context */
        $context = $this->context;
        $link = $context instanceof Context ? $context->link : null;
        if ($link === null) {
            return [];
        }

        $option = new PaymentOption();
        $option->setModuleName((string) $this->name)
            ->setCallToActionText($this->trans('Pay with Pensopay', [], 'Modules.Pensopay.Shop'))
            ->setAction($link->getModuleLink((string) $this->name, 'payment', [], true));

        return [$option];
    }

    /**
     * @param array<string, mixed> $params
     */
    public function hookDisplayPaymentReturn(array $params): string
    {
        if (!self::isPhpVersionSupported()) {
            return '';
        }

        return '';
    }

    /**
     * @param array<string, mixed> $params
     */
    public function hookDisplayAdminOrderMain(array $params): string
    {
        if (!self::isPhpVersionSupported()) {
            return '';
        }

        return '';
    }

    /**
     * @param array<string, mixed> $params
     */
    public function hookActionOrderStatusUpdate(array $params): void
    {
        if (!self::isPhpVersionSupported()) {
            return;
        }
    }

    /**
     * @param array<string, mixed> $params
     */
    public function hookActionFrontControllerSetMedia(array $params): void
    {
        if (!self::isPhpVersionSupported()) {
            return;
        }
    }

    /**
     * Configuration keys owned by the module; deleted on uninstall.
     *
     * @return string[]
     */
    private static function getConfigurationKeys(): array
    {
        return [self::CONFIG_API_KEY];
    }

    private static function isPhpVersionSupported(): bool
    {
        return PHP_VERSION_ID >= self::MIN_PHP_VERSION_ID;
    }

    private function getPhpVersionError(): string
    {
        return $this->trans(
            'This module requires PHP %required% or higher. Your server runs PHP %current%.',
            [
                '%required%' => self::MIN_PHP_VERSION,
                '%current%' => PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION,
            ],
            'Modules.Pensopay.Admin'
        );
    }
}
