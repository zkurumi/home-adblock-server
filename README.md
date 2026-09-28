# Home Network Ad Blocker (AdGuard Home on Headless Debian)

A repurposed laptop running minimal Debian 13 as a dedicated DNS server. It uses [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome) to block ads, trackers, and malicious domains for devices on a home network, and runs headless with the lid closed.

## Overview

DNS-level blocking works by answering lookups for known ad and tracker domains with nothing, so the content never loads. The blocking device sits beside the network rather than in the data path, so it adds no bandwidth overhead. Cached lookups on the LAN are also faster than round trips to an ISP resolver.

**Goals**

- Repurpose old hardware into an always-on network service
- Run a minimal, headless Linux install with remote administration only
- Filter ads, trackers, and malware domains at the DNS layer

## Stack

| Component | Purpose |
|---|---|
| Debian 13 (minimal, no desktop) | Base OS |
| AdGuard Home | DNS server and filtering |
| OpenSSH | Remote administration |
| systemd / systemd-logind | Service management, lid-close behavior |

**Hardware:** HP EliteBook Folio laptop, 180 GB Intel SSD, wired Ethernet to the home gateway.

## Architecture

```
Devices ──DNS query──▶ AdGuard Home (Debian server) ──▶ Upstream DNS (Cloudflare / Quad9)
   │                          │
   │                          └─ blocked domains: answered locally, never reach the internet
   └────────── normal traffic goes directly to the router ──────────▶ Internet
```

## Setup Summary

1. **Install Debian 13 (netinst)** with no desktop environment. In the software selection screen, only *SSH server* and *standard system utilities* were selected. Used wired Ethernet and guided partitioning (UEFI, single ext4 root + swap).
2. **Install prerequisites.** A minimal install does not include `sudo` or `curl`:
   ```bash
   su -
   apt update && apt install -y sudo curl
   usermod -aG sudo <username>
   ```
3. **Enable headless (lid-closed) operation** by editing `/etc/systemd/logind.conf`:
   ```
   HandleLidSwitch=ignore
   HandleLidSwitchExternalPower=ignore
   HandleLidSwitchDocked=ignore
   ```
   then `sudo systemctl restart systemd-logind`.
4. **Manage remotely over SSH** from another machine:
   ```bash
   ssh <username>@<server-ip>
   ```
5. **Install AdGuard Home** using the official script:
   ```bash
   curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
   ```
6. **Complete the web setup wizard** at `http://<server-ip>:3000` (admin UI on port 80, DNS on port 53, create an admin account).
7. **Configure filtering** in the dashboard:
   - Filters → DNS blocklists: AdGuard DNS filter, AdAway, OISD
   - Settings → DNS settings → upstream: DNS-over-HTTPS to Cloudflare or Quad9
8. **Point clients at the server.** Either set the router's DHCP DNS to the server's IP (network-wide) or set DNS manually on a single device for testing.

## Verification

- The AdGuard dashboard's **Top clients** panel shows the test device with a growing request count.
- Query Log shows blocked (red) and allowed (green) lookups in real time.
- Confirmed working on an iPhone by manually setting Wi-Fi DNS to the server's IP.

## Troubleshooting Notes

Problems I hit and how I resolved them:

| Problem | Cause | Fix |
|---|---|---|
| `sudo: command not found` | Minimal Debian does not install sudo | Log in as root with `su -`, install sudo, add the user to the `sudo` group |
| `curl: command not found` | Not included in minimal install | `sudo apt install curl` |
| `LC_CTYPE: cannot change locale (UTF-8)` on SSH login | macOS Terminal forwards a locale name Debian does not recognize | Cosmetic; can be silenced with `SendEnv -LC_*` in the client's `~/.ssh/config` |
| Ping to the server timed out | I was using an assumed IP; DHCP had assigned a different subnet | Check the real address with `ip -4 addr show` |
| AdGuard login blocked (`429`) | Repeated failed logins trigger a 15-minute lockout (`auth_attempts: 5`, `block_auth_min: 15`) | Wait it out; usernames are case-sensitive |
| Setup wizard threw `404` after editing the config | Removing only the `users:` block left a partial config | Stop the service, delete `AdGuardHome.yaml`, restart, and re-run the wizard on port 3000 |

## Limitations

DNS blocking cannot filter ads that are served from the same domain as the content itself. This includes:

- YouTube video ads
- Instagram and Facebook feed ads
- Twitch stream ads

For browser use, a content blocker such as uBlock Origin complements DNS filtering.

## Possible Improvements

- Automate the setup with a provisioning script (`setup.sh`)
- Assign a DHCP reservation or static IP so the server address never changes
- Add a secondary DNS server for redundancy
- Add monitoring or alerting for service downtime
- Back up `AdGuardHome.yaml` on a schedule

## What I Learned

- Headless Linux administration and remote management over SSH
- systemd service control and power-management configuration
- How DNS resolution, DHCP, and upstream resolvers fit together
- Diagnosing network and permission issues methodically from logs and error messages
- The practical limits of DNS-based filtering
