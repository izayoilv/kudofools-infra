# Matrix (Conduit) operations

Self-hosted Matrix homeserver: **Conduit** at `https://conduit.kudofools.dev` (deployment lives in the `matrix-conduit` repo, Flux wiring in `clusters/default/matrix-conduit.yaml`). Element Web at `https://element.kudofools.dev`.

Reference: [Conduit configuration](https://docs.conduit.rs/configuration.html), Conduit admin source.

## Admin room

- The **first registered user** on the server is the admin.
- The admin room is a room with `@conduit:conduit.kudofools.dev`; its alias is `#admins:conduit.kudofools.dev`. **Membership in that room = admin.**
- Admin commands are sent as chat messages; the bot replies in the room. Format:
  ```
  @conduit:conduit.kudofools.dev: <command> [args]
  ```
  (in practice a bare `reset-password <user>` message in the room works — the bot treats messages there as commands).

Useful commands:

| Command | Purpose |
|---|---|
| `help` | List all commands |
| `list-local-users` | List local accounts |
| `reset-password <username>` | Generate a new random password for the user and reply with it; also **reactivates** a deactivated account |
| `create-user <username> [password]` | Create an account; password is generated and printed if omitted; no device is created |
| `deactivate-user <@user:server>` | Deactivate an account |
| `allow-registration true\|false` | Temporarily toggle registration without a restart |
| `show-config` | Print the effective config |

## Recover a forgotten password (still logged in)

1. In Element, open the admin room (room with the `@conduit` bot).
2. Send:
   ```
   reset-password <yourusername>
   ```
3. The bot replies `Successfully reset the password for user @you:conduit.kudofools.dev: <new-password>`.
4. Log in with that password, then optionally set your own in Element → Settings → Account → **Change password** (enter the generated one as the current password).

## Locked out entirely (emergency password)

If you cannot access the admin room (lost session, not the first user, etc.):

1. Add to the `[global]` section of the Conduit config (`conduit-config` ConfigMap in the `matrix-conduit` repo, `clusters/default/configmap.yaml`):
   ```toml
   emergency_password = "<long-random-password>"
   ```
2. Push / restart Conduit, then log in as `@conduit:conduit.kudofools.dev` with that password.
3. From there: run `reset-password <yourusername>` or invite your account back into the admin room.
4. **Remove the `emergency_password` afterwards and restart.**

## Alerts bot (used by the monitoring stack)

The monitoring stack posts alerts through a dedicated Matrix account:

1. In the admin room, create the bot (pick a strong password and save it):
   ```
   create-user alerts <password>
   ```
2. Create a room for alerts (e.g. `#alerts:kudofools.dev`) from your admin account and invite `@alerts:conduit.kudofools.dev`.
3. Get the bot's access token (creates a login device):
   ```bash
   curl -s -XPOST https://conduit.kudofools.dev/_matrix/client/v3/login \
     -H 'Content-Type: application/json' \
     -d '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"alerts"},"password":"<password>","device_id":"ALERTSBOT"}' \
     | jq -r .access_token
   ```

   > Each login without `device_id` creates a **new device and a new access token** (per the Matrix
   > spec). Always pass `device_id` for the bot so re-logins reuse one device — note that logging in
   > with an existing `device_id` invalidates that device's previous token, so re-seed OpenBao after
   > rotating. `GET /_matrix/client/v3/account/whoami` shows which device a token belongs to;
   > `GET /_matrix/client/v3/devices` lists them and `DELETE /_matrix/client/v3/devices/{id}` removes
   > stale ones (do not delete the device whose token the receiver uses).
4. Note the **internal room ID** (Element → room settings → Advanced → Internal room ID). Conduit creates
   **room version 12** rooms, whose IDs are create-event hashes **without a `:server` suffix** (e.g.
   `!YHUMLDOI_KcSD-2Nk-SOMbbvt0pTK1iVXPUokQpZfJs`). Use it exactly as shown — appending
   `:conduit.kudofools.dev` causes "non-create event for room of unknown version" errors on send.
5. Store the token in OpenBao (see `SETUP.md`, monitoring section):
   `kv/matrix-alertmanager-receiver/secrets` → `MATRIX_ACCESS_TOKEN`.
   The room ID goes into the `mar-config` ConfigMap in `clusters/default/infra/platform/monitoring/matrix-alertmanager-receiver.yaml`.

The room ID is not a secret and lives in git; only the access token is stored in OpenBao and synced via ESO.

## Notes

- `allow_registration = true` with a registration token in this deployment; the admin bot commands above bypass registration entirely.
- Conduit stores data in RocksDB on the `conduit-data-pvc` volume; media retention is configured in the `conduit-config` ConfigMap.
- Password reset via email is not configured (no SMTP); use the admin room or the emergency password.
