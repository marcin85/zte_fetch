#!/bin/sh
set -eu

ROUTER="http://192.168.32.1"
PASS_FILE="/config/zte_password"

COOKIE_JAR="/config/.zte_cookiejar.txt"
OUT="/config/www/zte_stats.json"
TMP="/config/www/zte_stats.json.tmp"
LOG="/config/zte_fetch.log"

mkdir -p /config/www

PASS="$(head -n 1 "$PASS_FILE" 2>/dev/null | tr -d '\r\n' || true)"
[ -n "$PASS" ] || { echo "$(date) ERROR: missing password in $PASS_FILE" >>"$LOG"; exit 1; }

# Base64(password) without trailing newline
PASS_B64="$(printf "%s" "$PASS" | base64 | tr -d '\n')"

# SHA256(Base64(password)) -> HEX uppercase (same as ZTE UI)
PASS_HASH="$(printf "%s" "$PASS_B64" | sha256sum | awk '{print toupper($1)}')"

curlj() {
  curl -sS --compressed \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -H "User-Agent: Mozilla/5.0" \
    -H "Accept: application/json, text/javascript, */*; q=0.01" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "Referer: $ROUTER/index.html" \
    "$@"
}

login() {
  # Initialize cookies
  curlj "$ROUTER/index.html" -o /dev/null 2>>"$LOG" || true
  RESP_FILE="/config/login_resp.txt"

  HTTP="$(curlj -o "$RESP_FILE" -w "%{http_code}" \
    -X POST "$ROUTER/goform/goform_set_cmd_process" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    --data "isTest=false&goformId=LOGIN&password=$PASS_HASH" \
    2>>"$LOG" || true)"

  echo "$(date) login http=$HTTP resp=$(tr -d '\n' < "$RESP_FILE" | cut -c1-200)" >>"$LOG"
}

CMD="modem_main_state,pin_status,opms_wan_mode,opms_wan_auto_mode,loginfo,new_version_state,current_upgrade_state,is_mandatory,ppp_dial_conn_fail_counter,dm_update_package_file_exist,signalbar,network_type,network_provider,wifi_ap_mode,dhcp_wan_status,ppp_status,simcard_roam,station_mac,battery_exist,battery_charging,battery_vol_percent,battery_value,battery_pers,spn_name_data,spn_b1_flag,spn_b2_flag,realtime_tx_bytes,realtime_rx_bytes,realtime_time,realtime_tx_thrpt,realtime_rx_thrpt,monthly_rx_bytes,monthly_tx_bytes,wan_lan_in_same_subnet,wifi_dfs_status,wifi_access_sta_num,wifi_onoff_state,wifi_chip1_ssid1_ssid,wifi_chip2_ssid1_ssid,wifi_chip1_ssid1_access_sta_num,wifi_chip2_ssid1_access_sta_num,lan_ipaddr,monthly_time,data_volume_limit_switch,data_volume_limit_size,data_volume_alert_percent,data_volume_limit_unit,dial_mode,wan_lte_ca,privacy_read_flag,sms_unread_num"

fetch_stats() {
  URL="$ROUTER/goform/goform_get_cmd_process?multi_data=1&isTest=false&cmd=$CMD&_=$(date +%s)"
  HTTP="$(curlj -o "$TMP" -w "%{http_code}" "$URL" 2>>"$LOG" || true)"

  echo "$(date) fetch http=$HTTP bytes=$(wc -c < "$TMP" 2>/dev/null || echo 0)" >>"$LOG"

  # Minimal validation
  grep -q '"ppp_status"' "$TMP" || return 1
  grep -q '"signalbar"' "$TMP" || return 1

  # Full dataset => realtime or monthly values present
  if grep -q '"realtime_rx_thrpt":"[^"]\+"' "$TMP" || grep -q '"monthly_rx_bytes":"[^"]\+"' "$TMP"; then
    TS_EPOCH="$(date +%s)"
    TS_ISO="$(date '+%Y-%m-%dT%H:%M:%S%z')"

    # Inject fetch timestamp into JSON (if python3 is available)
    if command -v python3 >/dev/null 2>&1; then
      python3 - <<PY 2>>"$LOG" || true
import json
p="$TMP"
with open(p,"r",encoding="utf-8") as f:
    d=json.load(f)
d["fetched_at_epoch"]=$TS_EPOCH
d["fetched_at_iso"]="$TS_ISO"
with open(p,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,separators=(",",":"))
PY
    else
      echo "$(date) WARN: python3 not found, timestamp not injected" >>"$LOG"
    fi

    mv "$TMP" "$OUT"
    echo "$(date) OK: full dataset saved" >>"$LOG"
    return 0
  fi

  echo "$(date) WARN: partial dataset received" >>"$LOG"
  return 2
}

# 1) Try with existing session
set +e
fetch_stats
RC=$?
set -e
[ "$RC" -eq 0 ] && exit 0

# 2) Re-login and retry
rm -f "$COOKIE_JAR" 2>/dev/null || true
login

set +e
fetch_stats
RC2=$?
set -e
[ "$RC2" -eq 0 ] && exit 0

echo "$(date) ERROR: still receiving partial dataset after login" >>"$LOG"
exit 1
