# 3x-ui server node

Standalone 3x-ui Docker deployment for the MiloshVPN server node.

This repository contains only the VPN node files:

- `compose.yaml` starts 3x-ui.
- `.env.example` contains the node environment template.
- `init-x3ui.sh` initializes panel credentials and creates the VLESS inbound.
- `xray-routing-policy.json` contains the optional Xray abuse-routing policy.
- `nftables-abuse-guard.nft` contains optional host firewall rules.
- `miloshvpn-abuse-guard.service` applies the firewall guard on boot without flushing Docker rules.

## Start

```sh
cp .env.example .env
nano .env
docker compose up -d
./init-x3ui.sh
```

Panel:

```text
http://SERVER_IP:2053/
```

Backend settings:

```env
X3UI_MODE=live
X3UI_USERNAME=<from .env>
X3UI_PASSWORD=<from .env>
X3UI_INBOUND_ID=1
VLESS_PUBLIC_HOST=SERVER_IP
VLESS_PUBLIC_PORT=8443
VLESS_QUERY=type=tcp&security=none
```

Keep `X3UI_USERNAME` and `X3UI_PASSWORD` in the backend node settings in sync with this server's local `.env`.

## Manage

```sh
docker compose ps
docker compose logs -f
docker compose restart
docker compose down
docker compose up -d
```

## Abuse Guard

The guard blocks common BitTorrent and Tor proxy ports without touching the VPN panel or VLESS ports.

```sh
cp miloshvpn-abuse-guard.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now miloshvpn-abuse-guard.service
```

Do not enable the default `nftables.service` unless `/etc/nftables.conf` has been reviewed; the distro default may flush Docker rules.
