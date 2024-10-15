#!/bin/bash
# Get register ids from the texts and make a post request to Anton to get the tei data only with used ids.

# Usage: ./bin/get-anton-data.sh {src_dir} {anton_api_token}

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

SRC_DIR=$1
API_TOKEN=$2
URL=https://lub.anton.ch/api/tei

entities=( actors places keywords )

cd $SRC_DIR;

for entity in ${entities[@]}; do
    # I don‘t know why, but ack is not working when started from ansible
    ids=$(egrep -oh -e "\lub-$entity-(\d+)" *.xml  | egrep -oh -e '\d+' | sort -n | uniq | sed -e :a -e '$!N; s/\n/,/; ta');
    #ids=$(ack -oh "\lub-$entity-(\d+)"  | ack -oh '\d+' | sort -n | uniq | sed -e :a -e '$!N; s/\n/,/; ta');

    #echo $ids;
    if [ -z "$ids" ]; then
        echo "No ids found for $entity";
        exit 1;
    fi

    wget --post-data "ids=$ids" $URL/$entity?api_token=$API_TOKEN -O ../registers/archives-$entity.xml;
done
exit 0;
