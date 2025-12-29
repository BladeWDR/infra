#!/usr/bin/env bash
LOGFILE=/var/log/nextcloud-appupdate.log

write-log (){
  echo "$1" | tee -a "$LOGFILE"
}

if [ "$(date +%u)" -ne 6 ]; then
  write-log "INFO: Today is not Saturday. Skipping."
  exit 0
fi

current_month=$(date +%m)
next_saturday_month=$(date -d 'next saturday' +%m)

if [ "$next_saturday_month" = "$current_month" ]; then
  write-log "INFO: This is not the last Saturday of the month. Skipping."
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  write-log "ERROR: Docker could not be found on the path."
  exit 1
fi

write-log "Updating NextCloud apps..."
docker exec --user www-data nextcloud-aio-nextcloud php occ app:update --all
write-log "Running NextCloud database maintenance..."
docker exec --user www-data nextcloud-aio-nextcloud php occ maintenance:repair --include-expensive
write-log "Checking NextCloud database for missing indices..."
docker exec --user www-data nextcloud-aio-nextcloud php occ db:add-missing-indices
write-log "NextCloud apps update done."

if [ "$(wc -l < "$LOGFILE")" -gt 50 ]; then
  tail -n 50 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
  write-log "INFO: Log truncated to 50 lines."
fi
