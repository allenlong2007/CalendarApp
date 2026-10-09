#!/bin/bash
# The weekly refresh in one command: renews expiring signing, then rebuilds and
# installs the app on this Mac and on your iPhone (if it's connected).
#
#   scripts/refresh-devices.sh          # Mac + phone
#   scripts/refresh-devices.sh --mac    # Mac only
#
# Why a script and not something inside Xcode: Xcode reuses a cached signing
# profile until it has fully expired, so a run on day 6 produces a build that
# dies hours later. Clearing the old profile has to happen BEFORE xcodebuild
# plans its work -- done from inside the build, it breaks that build.
#
# The phone needs to be plugged in or on the same Wi-Fi, unlocked, and trusted
# once (Settings > General > VPN & Device Management) the first time after a
# fresh profile. Your data is kept; the app is installed over the old one.

set -u
cd "$(dirname "$0")/.."
SCHEME=CalendarApp
BUNDLE=com.footsoregnu3115.calendarapp
MAC_ONLY=0
[ "${1:-}" = "--mac" ] && MAC_ONLY=1

step() { printf '\n== %s\n' "$1"; }
expiry() {
    for f in "$1/embedded.mobileprovision" "$1/embedded.provisionprofile"; do
        [ -f "$f" ] || continue
        security cms -D -i "$f" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null && return
    done
}
products_dir() { xcodebuild -scheme "$SCHEME" -destination "$1" -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/ {print $2; exit}'; }

step "Renewing signing profiles older than a day"
scripts/renew-stale-profiles.sh

step "Mac: build"
MAC_DEST='platform=macOS,variant=Mac Catalyst'
xcodebuild -scheme "$SCHEME" -configuration Debug -destination "$MAC_DEST" -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
MAC_APP="$(products_dir "$MAC_DEST")/$SCHEME.app"
if [ -d "$MAC_APP" ]; then
    step "Mac: install and relaunch"
    killall CalendarApp 2>/dev/null; sleep 1
    rm -rf /Applications/CalendarApp.app && ditto "$MAC_APP" /Applications/CalendarApp.app && open /Applications/CalendarApp.app
    echo "Mac profile valid until: $(expiry "$MAC_APP/Contents")  (UTC)"
fi

[ "$MAC_ONLY" = 1 ] && exit 0

step "iPhone: looking for your phone"
xcrun devicectl list devices --json-output /tmp/refresh-devs.json >/dev/null 2>&1
read -r UDID NAME < <(python3 - <<'PY'
import json
try:
    devs = json.load(open("/tmp/refresh-devs.json"))["result"]["devices"]
except Exception:
    devs = []
for d in devs:
    hw, cp, dp = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS" and cp.get("tunnelState") != "unavailable":
        print(hw["udid"], dp.get("name", "iPhone").replace(" ", "_")); break
PY
)
if [ -z "${UDID:-}" ]; then
    echo "No phone reachable. Plug it in (or put it on the same Wi-Fi), unlock it, and run this again."
    echo "The Mac is already done."
    exit 0
fi
echo "Found ${NAME//_/ } ($UDID)"

step "iPhone: build"
PHONE_DEST="id=$UDID"
xcodebuild -scheme "$SCHEME" -configuration Debug -destination "$PHONE_DEST" -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
PHONE_APP="$(products_dir "$PHONE_DEST")/$SCHEME.app"
[ -d "$PHONE_APP" ] || { echo "Phone build not found."; exit 1; }
echo "Phone profile valid until: $(expiry "$PHONE_APP")  (UTC)"

step "iPhone: install"
xcrun devicectl device install app --device "$UDID" "$PHONE_APP" 2>&1 | tail -3

step "iPhone: launch"
if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE" 2>&1 | tee /tmp/refresh-launch.txt | grep -q "Launched application"; then
    if grep -qi "not been explicitly trusted" /tmp/refresh-launch.txt; then
        echo "Installed, but iOS wants you to trust it: on the phone open Settings > General >"
        echo "VPN & Device Management > your developer account > Trust, then open the app."
    else
        tail -3 /tmp/refresh-launch.txt
        echo "Installed, but it didn't launch. Unlock the phone and open the app by hand."
    fi
fi
