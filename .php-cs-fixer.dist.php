<?php

$finder = PhpCsFixer\Finder::create()
    ->in(__DIR__)
    ->exclude(['vendor', 'translations']);

return (new PrestaShop\CodingStandards\CsFixer\Config())
    ->setUsingCache(true)
    ->setFinder($finder);
