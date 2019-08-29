#!/bin/bash -e

usage() {
    echo 'usage: merge_prs_and_build.sh <token> <repo1>:"<PR1>[:<PR2>[:...]]" [<repo2>:"<PR1>[:<PR2>[:...]]"] [...]'  >&2
    echo '  example: ./merge_prs_and_build.sh ~/mytoken xenclient-oe:"42 43" manager:666' >&2
    exit $1
}

[ $# -lt 2 ] && usage 1

token=$1
shift

url="http://openxt-builder.ainfosec.com:8010/builders/openxt64?"

for repoprs in "$@"; do
    repo=`echo $repoprs | cut -d ':' -f 1`
    prs=` echo $repoprs | cut -d ':' -f 2`
    override=`./pr_merger.sh $token $repo $prs | grep 'BuildBot: ' | sed 's/BuildBot: //'`
    url="${url}${repo}url=${override}&"
done

echo Opening the following URL: $url
xdg-open "$url"
