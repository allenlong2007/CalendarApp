#!/bin/bash
# Free Apple IDs get 7-day provisioning profiles, and Xcode keeps reusing a
# cached profile until it has fully EXPIRED. So rerunning the app on day 6
# gives you a build that dies hours later (it reused the almost-dead profile).
#
# This moves this app's cached profiles aside when they're more than a day
# old, which makes Xcode create fresh 7-day ones during the same build.
# Profiles younger than that are left alone, so repeated builds in a day
# don't keep hitting Apple's servers.
#
# Safe by design: profiles are moved (to "<dir>.stale"), never deleted; it
# does nothing when offline (Xcode couldn't make new ones); and it always
# exits 0 so it can never block a build.
#
#   scripts/renew-stale-profiles.sh              # do it
#   scripts/renew-stale-profiles.sh --dry-run    # just report
#   RENEW_AFTER_HOURS=0 scripts/renew-stale-profiles.sh   # force renewal now

BUNDLE="com.footsoregnu3115.calendarapp"
MAX_AGE_HOURS="${RENEW_AFTER_HOURS:-24}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

if [ -n "${PROFILE_DIRS:-}" ]; then
    IFS=: read -r -a DIRS <<< "$PROFILE_DIRS"
else
    DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles")
fi

# Nothing to renew on a machine with no profile cache (e.g. CI).
found_dir=0
for d in "${DIRS[@]}"; do [ -d "$d" ] && found_dir=1; done
[ "$found_dir" = 0 ] && exit 0

if [ "$DRY_RUN" = 0 ] && ! curl -sI --max-time 4 https://developerservices2.apple.com >/dev/null 2>&1; then
    echo "renew-stale-profiles: offline, leaving profiles alone"
    exit 0
fi

now=$(date +%s)
tmp=$(mktemp)
moved=0

for dir in "${DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.mobileprovision "$dir"/*.provisionprofile; do
        [ -f "$f" ] || continue
        security cms -D -i "$f" > "$tmp" 2>/dev/null || continue
        app_id=$(plutil -extract Entitlements.application-identifier raw -o - "$tmp" 2>/dev/null) || continue
        case "$app_id" in
            *".$BUNDLE"|*".$BUNDLE."*) ;;
            *) continue ;;
        esac
        created=$(plutil -extract CreationDate raw -o - "$tmp" 2>/dev/null) || continue
        created_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$created" +%s 2>/dev/null) || continue
        age_hours=$(( (now - created_epoch) / 3600 ))
        [ "$age_hours" -ge "$MAX_AGE_HOURS" ] || continue

        if [ "$DRY_RUN" = 1 ]; then
            echo "would renew: $(basename "$f")  ($app_id, ${age_hours}h old)"
        else
            mkdir -p "$dir.stale" && mv "$f" "$dir.stale/" && echo "renewing: $(basename "$f")  ($app_id, ${age_hours}h old)"
        fi
        moved=$((moved + 1))
    done
done
rm -f "$tmp"
[ "$moved" -gt 0 ] && [ "$DRY_RUN" = 0 ] && echo "renew-stale-profiles: Xcode will create fresh profiles during this build"
exit 0
