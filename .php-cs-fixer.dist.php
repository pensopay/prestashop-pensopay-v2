<?php

$finder = PhpCsFixer\Finder::create()
    ->in(__DIR__)
    ->exclude(['vendor', 'build', '.prestashop']);

// PrestaShop's Config returns a fixed rule set from getRules(), so setRules()
// would be ignored. Extend it to change a rule.
$config = new class extends PrestaShop\CodingStandards\CsFixer\Config {
    public function getRules(): array
    {
        return array_merge(parent::getRules(), [
            // The PrestaShop validator's license check requires the license
            // docblock on the line right after <?php, with no blank line in
            // between. bin/build.sh checks this too.
            'blank_line_after_opening_tag' => false,
        ]);
    }
};

return $config
    ->setUsingCache(true)
    ->setFinder($finder);
