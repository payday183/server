# Backend setup for VLESS TCP REALITY

This node already has two VLESS inbounds:

| Purpose | Inbound ID | Port | Network | Security | Status |
| --- | ---: | ---: | --- | --- | --- |
| Legacy clients | 1 | 8443 | tcp | none | keep enabled |
| New REALITY clients | 2 | 443 | tcp | reality | use for new backend config |

Do not delete inbound `1` while existing users still have old links.

## Current REALITY node values

Use these values when creating or editing the node in the backend admin panel:

```text
Name: MiloshVPN France_1 REALITY
Mode: live
3x-ui URL: http://91.108.240.52:2053
Login: value from /root/x3ui-node/.env -> X3UI_USERNAME
Password: value from /root/x3ui-node/.env -> X3UI_PASSWORD
Inbound ID: 2
Max clients: 10
Public host: 91.108.240.52
Public port: 443
VLESS query: encryption=none&type=tcp&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=aU_lFnKEqA7A_Byxc6X8ru-p5jfShdyOZHnbduMvBWo&sid=865a8fd4ee3e2627&spx=%2F
Active: yes, after backend code supports 3x-ui v3 client API
```

The same values are stored locally in:

```sh
/root/x3ui-node/.env
```

Relevant keys:

```env
X3UI_REALITY_PORT=443
X3UI_REALITY_INBOUND_ID=2
X3UI_REALITY_PUBLIC_KEY=aU_lFnKEqA7A_Byxc6X8ru-p5jfShdyOZHnbduMvBWo
X3UI_REALITY_SHORT_ID=865a8fd4ee3e2627
X3UI_REALITY_SNI=www.cloudflare.com
X3UI_REALITY_FINGERPRINT=chrome
X3UI_REALITY_VLESS_QUERY=encryption=none&type=tcp&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=aU_lFnKEqA7A_Byxc6X8ru-p5jfShdyOZHnbduMvBWo&sid=865a8fd4ee3e2627&spx=%2F
```

## What must change in the backend

The backend currently must be checked/fixed in three places.

### 1. Generated VLESS link

For REALITY, the backend should generate links like:

```text
vless://CLIENT_UUID@91.108.240.52:443?encryption=none&type=tcp&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=aU_lFnKEqA7A_Byxc6X8ru-p5jfShdyOZHnbduMvBWo&sid=865a8fd4ee3e2627&spx=%2F#CLIENT_LABEL
```

If the backend already builds the link as:

```text
vless://{uuid}@{public_host}:{public_port}?{vless_query}#{label}
```

then only the backend node settings need to be changed to:

```env
public_host=91.108.240.52
public_port=443
vless_query=encryption=none&type=tcp&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=aU_lFnKEqA7A_Byxc6X8ru-p5jfShdyOZHnbduMvBWo&sid=865a8fd4ee3e2627&spx=%2F
```

No `flow` is required for this REALITY inbound.

### 2. 3x-ui API client creation

This node runs `3x-ui` v3.2.8. In this version the old endpoint:

```text
POST /panel/api/inbounds/addClient
```

is not the API used by the current UI anymore.

The current client API is:

```text
POST /panel/api/clients/add
POST /panel/api/clients/del/{email}
POST /panel/api/clients/update/{email}
```

Recommended create-client payload:

```json
{
  "client": {
    "email": "milosh_123456789",
    "id": "CLIENT_UUID",
    "enable": true,
    "expiryTime": 0,
    "totalGB": 0,
    "tgId": 123456789,
    "limitIp": 0,
    "subId": "CLIENT_SUB_ID"
  },
  "inboundIds": [2]
}
```

Notes:

- `inboundIds` must include `2` for VLESS TCP REALITY.
- `email` is the unique identifier used by the new client API.
- For deletion, call `POST /panel/api/clients/del/{email}`.
- If the backend still deletes by UUID using `/panel/api/inbounds/{id}/delClient/{uuid}`, update it to delete by `email` for 3x-ui v3.2.8 compatibility.
- Login requests need CSRF handling in 3x-ui v3.2.8: first `GET /`, read the `csrf-token` meta value and cookie, then `POST /login` with `X-CSRF-Token`.

### 3. Apply client changes to Xray

After `POST /panel/api/clients/add` succeeds, the backend must make sure Xray reloads the updated 3x-ui database into its runtime config.

This node had the exact failure mode where:

```text
3x-ui API inbound 2 clients: 11
running Xray config inbound 2 clients: 0
```

After running this on the node:

```sh
cd /root/x3ui-node
docker compose exec -T x3ui x-ui restart-xray
```

the running Xray config changed to:

```text
running Xray config inbound 2 clients: 11
```

So the backend must not only generate a VLESS link and save the client through the 3x-ui API. It also needs an apply step after create/update/delete:

```text
1. Login to 3x-ui with CSRF support.
2. POST /panel/api/clients/add with inboundIds: [2].
3. Confirm the response is successful.
4. Reload/restart Xray on the node.
5. Only then send the VLESS link to the user.
```

If the backend has access to a confirmed 3x-ui API endpoint for restarting Xray, use that endpoint. Otherwise run `x-ui restart-xray` on the node through a controlled SSH/worker action. Do not restart the whole Docker container for every key unless there is no better option.

## Safe migration plan

1. Keep the existing backend node using inbound `1` active until old users are migrated.
2. Add a new backend node for REALITY using inbound `2`.
3. Test one paid/test key through the backend and confirm the generated link contains:

```text
security=reality
pbk=aU_lFnKEqA7A_Byxc6X8ru-p5jfShdyOZHnbduMvBWo
sid=865a8fd4ee3e2627
sni=www.cloudflare.com
fp=chrome
```

4. Confirm the client appears in 3x-ui under inbound `miloshvpn-reality`.
5. Only after successful testing, make the REALITY node active for new users.
6. Do not remove inbound `1` until all old `8443/security=none` links are no longer needed.

## Quick verification on the node

```sh
cd /root/x3ui-node
docker compose ps
ss -tulpn | grep -E ':443|:2053|:8443'
```

Expected ports:

```text
0.0.0.0:443
0.0.0.0:2053
0.0.0.0:8443
```
