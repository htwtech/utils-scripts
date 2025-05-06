#!/bin/bash

BOT_TOKEN=""
CHANNEL_ID=""


# Info for caption
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')

# Temporary file for response
TMP_RESPONSE=$(mktemp)

usage() {
    echo "Usage:"
    echo "  echo \"your message\" | $0               # send a message"
    echo "  $0 /path/to/file             # send a file"
    exit 1
}

if [[ -n "$1" ]]; then
    FILE_PATH="$1"

    CAPTION="Host: ${HOSTNAME}
IP: ${IP_ADDRESS}
Date: ${DATE_NOW}"

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F "chat_id=${CHANNEL_ID}" \
        -F "caption=${CAPTION}" \
        -F "parse_mode=HTML" \
        -F "document=@${FILE_PATH}" > "$TMP_RESPONSE"
elif [ ! -t 0 ]; then
    MESSAGE=$(cat)

    TEXT="Host: ${HOSTNAME}
IP: ${IP_ADDRESS}
Date: ${DATE_NOW}

${MESSAGE}"

    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHANNEL_ID}" \
        -d "text=${TEXT}" \
        -d "parse_mode=HTML" > "$TMP_RESPONSE"
else
    # No arguments and no stdin — show usage
    usage
fi

if grep -q '"ok":true' "$TMP_RESPONSE"; then
    # Success — do nothing
    true
else
    ERROR_CODE=$(grep -o '"error_code":[0-9]*' "$TMP_RESPONSE" | cut -d':' -f2)
    DESCRIPTION=$(grep -o '"description":"[^"]*' "$TMP_RESPONSE" | cut -d':' -f2 | tr -d '"')
    echo "Error $ERROR_CODE: $DESCRIPTION"
fi

rm -f "$TMP_RESPONSE"
