#!/bin/bash
# Get register ids from the texts and make POST requests to Anton to get the TEI
# data only for the ids actually used.
#
# The ids are requested in batches: Anton validates the `ids` parameter and
# rejects an overly long list with "The ids parameter is too long." (it then
# returns its HTML homepage instead of TEI). The actors register alone already
# has >2400 ids, so a single request fails. Each batch is fetched separately and
# the per-batch responses are merged into one register file per entity.
#
# Usage: ./bin/get-anton-data.sh {src_dir} {anton_api_token}

set -uo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

SRC_DIR=$1
API_TOKEN=$2
URL=https://lub.anton.ch/api/tei
REGISTERS_DIR="$SCRIPT_DIR/../data/registers"

# Number of ids per request. A known-good request had 878 ids / ~3400 chars, a
# failing one 2432 ids / ~11300 chars, so 500 stays well under the limit whether
# Anton counts ids or characters.
BATCH_SIZE=500

# entity -> the TEI list container whose entries get merged across batches
# (the first element of that name in document order). A function rather than an
# associative array, because Ansible runs this with macOS' bash 3.2.
container_for() {
    case "$1" in
        actors)   echo listPerson ;;
        places)   echo listPlace ;;
        keywords) echo list ;;
    esac
}

entities=( actors places keywords )

cd "$SRC_DIR" || { echo "ERROR: src dir '$SRC_DIR' not found"; exit 1; }

for entity in "${entities[@]}"; do
    # I don't know why, but ack is not working when started from ansible
    ids=$(egrep -oh -e "lub-$entity-[0-9]+" *.xml | egrep -oh -e '[0-9]+' | sort -n | uniq)

    if [ -z "$ids" ]; then
        echo "No ids found for $entity"
        exit 1
    fi

    total=$(echo "$ids" | grep -c .)
    echo "$entity: $total ids -> batches of $BATCH_SIZE"

    tmpdir=$(mktemp -d)
    # split the sorted ids into batch files (keeps global order across batches)
    echo "$ids" | split -l "$BATCH_SIZE" - "$tmpdir/batch."

    parts=()
    batch_no=0
    for batchfile in "$tmpdir"/batch.*; do
        batch_no=$((batch_no + 1))
        batch_ids=$(paste -sd, "$batchfile")
        out="$tmpdir/resp.$batch_no.xml"

        wget -q --post-data "ids=$batch_ids&api_token=$API_TOKEN" "$URL/$entity" -O "$out"

        # Guard: a rejected request returns Anton's HTML page, not TEI. Abort
        # instead of committing a broken register file.
        if ! head -c 64 "$out" | grep -q '<?xml'; then
            msg=$(grep -o '<li>[^<]*</li>' "$out" | head -1 | sed 's/<[^>]*>//g')
            echo "ERROR: $entity batch $batch_no did not return TEI."
            echo "       Anton said: ${msg:-unknown error (see $out)}"
            rm -rf "$tmpdir"
            exit 1
        fi
        echo "  batch $batch_no: $(wc -l < "$batchfile" | tr -d ' ') ids ok"
        parts+=("$out")
    done

    dest="$REGISTERS_DIR/lub3-$entity.xml"
    if [ "${#parts[@]}" -eq 1 ]; then
        cp "${parts[0]}" "$dest"
    else
        php "$SCRIPT_DIR/merge-tei.php" "$(container_for "$entity")" "$dest" "${parts[@]}" || {
            echo "ERROR: merging $entity batches failed"
            rm -rf "$tmpdir"
            exit 1
        }
    fi
    echo "$entity: wrote $dest"
    rm -rf "$tmpdir"
done

echo "Done."
exit 0
