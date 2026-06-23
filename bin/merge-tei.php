<?php
// merge-tei.php <containerLocalName> <output> <input1> [<input2> ...]
//
// Merges several TEI register responses (as returned by the Anton API) into a
// single document. The first <containerLocalName> element of the first input is
// used as the base; the entry elements of every further input's container are
// appended to it. Used by get-anton-data.sh, which has to request the register
// data in batches because Anton rejects an overly long `ids` parameter.

if ($argc < 4) {
    fwrite(STDERR, "usage: merge-tei.php <container> <out> <in1> [<in2> ...]\n");
    exit(2);
}

const TEI_NS = 'http://www.tei-c.org/ns/1.0';

$container = $argv[1];
$out       = $argv[2];
$inputs    = array_slice($argv, 3);

libxml_use_internal_errors(true);

function first_container(DOMDocument $doc, string $local): ?DOMElement {
    foreach ($doc->getElementsByTagNameNS(TEI_NS, $local) as $el) {
        return $el; // first in document order
    }
    return null;
}

function load(string $path): DOMDocument {
    $doc = new DOMDocument();
    $doc->preserveWhiteSpace = true;
    if (!$doc->load($path)) {
        fwrite(STDERR, "merge-tei: could not parse $path as XML\n");
        exit(1);
    }
    return $doc;
}

$base = load($inputs[0]);
$baseContainer = first_container($base, $container);
if (!$baseContainer) {
    fwrite(STDERR, "merge-tei: <$container> not found in {$inputs[0]}\n");
    exit(1);
}

for ($i = 1; $i < count($inputs); $i++) {
    $doc = load($inputs[$i]);
    $c = first_container($doc, $container);
    if (!$c) {
        fwrite(STDERR, "merge-tei: <$container> not found in {$inputs[$i]}\n");
        exit(1);
    }
    foreach (iterator_to_array($c->childNodes) as $child) {
        if ($child->nodeType === XML_ELEMENT_NODE) {
            $baseContainer->appendChild($base->importNode($child, true));
        }
    }
}

if ($base->save($out) === false) {
    fwrite(STDERR, "merge-tei: could not write $out\n");
    exit(1);
}
