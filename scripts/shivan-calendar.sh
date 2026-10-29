#!/bin/bash
# LaunchServices owns the process so Calendar permission belongs to this app,
# not Grok's general-purpose command shell. JSON only; no public socket.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
SHIVAN_EXCHANGE="$HOME/Library/Application Support/ShivanCalendarBridge/exchange"
mkdir -p "$SHIVAN_EXCHANGE"
SHIVAN_REQUEST=$(mktemp "$SHIVAN_EXCHANGE/request.XXXXXXXX")
SHIVAN_RESPONSE="$SHIVAN_REQUEST.response"
trap 'rm -f "$SHIVAN_REQUEST" "$SHIVAN_RESPONSE" "$SHIVAN_RESPONSE.status"' EXIT
cat > "$SHIVAN_REQUEST"
open -n -W "$PWD/build/ShivanCalendarBridge.app" --args \
  --request-file "$SHIVAN_REQUEST" --response-file "$SHIVAN_RESPONSE"
if [ ! -s "$SHIVAN_RESPONSE" ]; then
  echo '{"error":"The bridge returned no response. Check its Calendar permission and retry with the same requestID."}'
  exit 1
fi
cat "$SHIVAN_RESPONSE"
if [ ! -s "$SHIVAN_RESPONSE.status" ] || [ "$(cat "$SHIVAN_RESPONSE.status")" != 0 ]; then
  exit 1
fi
