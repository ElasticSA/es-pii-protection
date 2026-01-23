#!/usr/bin/env bash
set -euo pipefail
###############################################################################
# Args
###############################################################################
CONFIG=${1?Config path required}
###############################################################################
# Example curl-style config file (without the "## " prefix)
#
#   #es_url "https://localhost:9200"
#
#   #pii_key "/secure/path/pii.key"
#   # OR:
#   #pii_key "my-super-secret-key-material"
#
#   # These headers must always exist in this file for the REST API
#   header "Accept: application/json"
#   header "Content-Type: application/json"
#
#   user "elastic:password"
#
# Or instead of user/pass:
#
#   header "Authorization: ApiKey BASE64_API_KEY"
#
# Notes:
# - Lines starting with '#' are ignored by curl but readable by this script.
# - `#pii_key` may reference a file path or contain the key material directly.
###############################################################################
DOCID_ARG=${2:-}
###############################################################################
# Config helpers
###############################################################################
get_config() {
    local key=${1?Key required}
    sed -n "s/^#${key}[[:space:]]*\"\\(.*\\)\"/\\1/p" "$CONFIG" | tail -n 1
}
escurl() {
    local es_url
    es_url=$(get_config es_url)
    local endpoint=${1?No ES endpoint given}
    shift
    es_url="${es_url%/}"
    endpoint="${endpoint#/}"
    curl -sSL --fail-with-body -K "$CONFIG" "$es_url/$endpoint" "$@"
}
###############################################################################
# PII key handling (from config)
###############################################################################
PII_KEY=$(get_config pii_key)
if [[ -z "$PII_KEY" ]]; then
    echo "! Missing #pii_key in config file" >&2
    exit 1
fi
if [[ -f "$PII_KEY" ]]; then
    # Read file, trim final newline only
    PII_KEY=$(sed '$ s/\n$//' "$PII_KEY")
fi
###############################################################################
# Key material for IP cipher (must match Logstash exactly)
###############################################################################
# IPv4: lower 16 bits additive cipher
IPV4_KEY=$(printf '%s' "$PII_KEY" \
    | openssl dgst -sha256 -binary \
    | dd bs=2 count=1 2>/dev/null \
    | xxd -p)
IPV4_KEY=$((0x$IPV4_KEY))
# IPv6: lower 64 bits XOR cipher
IPV6_KEY=$(printf '%s' "$PII_KEY" \
    | openssl dgst -sha256 -binary \
    | dd bs=8 count=1 2>/dev/null \
    | xxd -p)
###############################################################################
# AES decrypt helper
###############################################################################
# Encrypted format:
#   keyname:salt:BASE64(iv + ciphertext)
###############################################################################
decrypt_value() {
    local salt=$1
    local b64=$2
    local raw iv ct key
    raw=$(printf '%s' "$b64" | openssl base64 -d 2>/dev/null) || return 1
    iv=$(printf '%s' "$raw" | dd bs=16 count=1 2>/dev/null | xxd -p | tr -d '\n')
    ct=$(printf '%s' "$raw" | dd bs=16 skip=1 2>/dev/null)
    key=$(printf '%s' "${PII_KEY}${salt}" \
        | openssl dgst -sha256 -binary \
        | xxd -p | tr -d '\n')
    printf '%s' "$ct" | \
        openssl enc -aes-256-cbc -d \
            -K "$key" \
            -iv "$iv" \
            2>/dev/null
}
###############################################################################
# IP decrypt helpers (mirror Logstash)
###############################################################################
decrypt_ipv4() {
    local ip=$1
    local a b c d
    IFS=. read -r a b c d <<<"$ip"
    local suffix=$(( (c << 8) | d ))
    local dec_suffix=$(( (suffix - IPV4_KEY) & 0xFFFF ))
    printf '%d.%d.%d.%d' \
        "$a" "$b" \
        $(( (dec_suffix >> 8) & 0xFF )) \
        $(( dec_suffix & 0xFF ))
}
expand_ipv6() {
    # sipcalc prints fully expanded address; extract it
    sipcalc "$1" 2>/dev/null | awk '/Expanded Address/ {print $3}'
}
decrypt_ipv6() {
    local ip=$1
    local expanded hi lo lo_dec
    expanded=$(expand_ipv6 "$ip") || return 1
    hi=$(printf '%s' "$expanded" | cut -d: -f1-4 | tr -d :)
    lo=$(printf '%s' "$expanded" | cut -d: -f5-8 | tr -d :)
    lo_dec=$(printf '%016x' $(( 0x$lo ^ 0x$IPV6_KEY )))
    printf '%s:%s:%s:%s:%s:%s:%s:%s\n' \
        "${hi:0:4}" "${hi:4:4}" "${hi:8:4}" "${hi:12:4}" \
        "${lo_dec:0:4}" "${lo_dec:4:4}" "${lo_dec:8:4}" "${lo_dec:12:4}"
}
###############################################################################
# YAML decrypt filter
###############################################################################
decrypt_yaml() {
    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            echo "---"
            continue
        fi
        if [[ "$line" == *:* ]]; then
            # Split on first colon, preserve indentation
            keypart=${line%%:*}
            rest=${line#*:}
            rest=${rest# }
            # AES-encrypted scalar: salt:base64
            if [[ "$rest" =~ ^([a-f0-9]{4,8}):([A-Za-z0-9+/]+=*)$ ]]; then
                salt=${BASH_REMATCH[1]}
                b64=${BASH_REMATCH[2]}
                if decrypted=$(decrypt_value "$salt" "$b64"); then
                    printf '%s: %s\n' "$keypart" "$decrypted"
                    continue
                fi
            fi
            # IPv4
            if [[ "$rest" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                printf '%s: %s\n' "$keypart" "$(decrypt_ipv4 "$rest")"
                continue
            fi
            # IPv6
            if [[ "$rest" == *:* ]]; then
                if dec_ip=$(decrypt_ipv6 "$rest"); then
                    printf '%s: %s\n' "$keypart" "$dec_ip"
                    continue
                fi
            fi
        fi
        printf '%s\n' "$line"
    done
}
###############################################################################
# Fetch docs
###############################################################################
fetch_docs() {
    local index='["logs-*","metrics-*"]'
    local id
    if [[ "$1" == */* ]]; then
        index="[\"${1%/*}\"]"
        id="${1#*/}"
    else
        id="$1"
    fi
    escurl "_search" -XPOST -d @- <<EOM
{
  "index": $index,
  "query": {
    "ids": {
      "values": ["$id"]
    }
  }
}
EOM
}
###############################################################################
# Main
###############################################################################
process_id() {
    fetch_docs "$1" | yq -P '.hits.hits[]._source'
}
if [[ -n "$DOCID_ARG" ]]; then
    process_id "$DOCID_ARG" | decrypt_yaml
else
    first=true
    while IFS= read -r docid; do
        if ! $first; then
            echo "---"
        fi
        first=false
        process_id "$docid" | decrypt_yaml
    done
fi
