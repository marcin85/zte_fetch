# ZTE MF286D – Automatic Login & Statistics Export

This repository contains a POSIX shell script that automatically logs into a **ZTE MF286D / ZTE LTE router**, fetches detailed modem and traffic statistics via the undocumented ZTE `goform` API, and exports them as a JSON file suitable for further processing.

The script reproduces the exact authentication flow used by the ZTE web UI:
`SHA256(Base64(password))`.

It is designed to run unattended (cron, Home Assistant `shell_command`) and safely re-authenticates when the session expires.

---

## Features

- Automatic login using the ZTE web UI hashing algorithm
- Cookie-based session handling
- Fetches real-time LTE statistics:
  - RX / TX throughput
  - Monthly RX / TX usage
  - Signal strength and network type
  - Connected Wi-Fi clients
  - SMS unread counter
- Detects partial datasets and retries after re-login
- Exports a clean JSON file for integrations (Home Assistant, Grafana, dashboards)
- Injects fetch timestamps (epoch + ISO-8601) into the output
- Robust logging for diagnostics and long-term monitoring
- No browser automation, no Selenium, no vendor SDKs

---

## Requirements

- POSIX-compatible shell (`/bin/sh`)
- `curl`
- `base64`
- `sha256sum`
- `awk`
- `python3` (optional, for timestamp injection)

Tested on Home Assistant OS and standard Linux distributions.

---

## Router Address (Important)

⚠ **The router IP address is currently hardcoded in the script.**

By default, the script assumes the router is available at: ```http://192.168.32.1```

If your router uses a different IP address or subnet, you must edit this value manually before running the script.

---

## Authentication Details

⚠ **Password must be storred in file ```/config/zte_password```**

The script reproduces the exact client-side algorithm used in the web UI:

```text
password_hash = SHA256( Base64(password) )
```
The resulting hash is sent as the password field to:
```text
POST /goform/goform_set_cmd_process
```
This allows programmatic login without storing cookies from a browser session.

---

## Output Files

| File                         | Description                                   |
| ---------------------------- | --------------------------------------------- |
| `/config/www/zte_stats.json` | JSON export with modem and traffic statistics |
| `/config/zte_fetch.log`      | Execution and error log                       |
| `/config/.zte_cookiejar.txt` | Session cookies (auto-managed)                |

---

## JSON Output Example
```text
{
  "ppp_status": "ppp_connected",
  "signalbar": "4",
  "network_type": "LTE_A",
  "realtime_rx_thrpt": "3956",
  "realtime_tx_thrpt": "1944",
  "monthly_rx_bytes": "133570238584",
  "monthly_tx_bytes": "21662284932",
  "fetched_at_epoch": 1766955282,
  "fetched_at_iso": "2025-01-28T21:21:22+0100"
}
```

---

## Usage Examples
### Cron

```text
*/1 * * * * /config/zte_fetch.sh
```

### Home Assistant
```text
shell_command:
  zte_fetch: /config/zte_fetch.sh
```

The generated JSON can then be consumed using a REST or command_line sensor.

---

## Known Limitations
- The script supports only one active session at a time.  If you are logged in elsewhere when the script starts, the existing session will be automatically logged out.
- Script relies on undocumented ZTE endpoints (goform_*)
- Firmware updates may change field names or authentication flow
- Some fields may be empty when the router is not fully connected

---

## Security Notes

- Store the router password in a separate file (```zte_password```)
- The password is never logged
- Only the hashed value is transmitted to the router
- Restrict file permissions on ```/config/zte_password```

---

## Compatibility

Known to work with:

- ZTE MF286D
- ZTE firmware with classic ```goform``` API and SHA256(Base64) login
- Other ZTE models may work but are untested.

---

## License

GPLv3

