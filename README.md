# Linux Mint → RDP Kiosk Playbook

Automates the manual setup you outlined (autologin, Remmina, autostart,
keyring fix) and adds: sequential terminal naming, an independent admin
account for remote management, an on-demand VNC option, and a way for the
end user to shut the terminal down.

## What Ansible can and can't do

Ansible configures a machine that already has an OS + SSH — it doesn't
image bare metal. Workflow:

1. **Manual, once per PC:** install Linux Mint (Cinnamon), enable
   `openssh-server`, create the initial `ansible_user` account used in
   `inventory.ini` (with sudo). This is the "manual admin configuration"
   step — after this, the playbook does the rest.
2. **Run this playbook** to configure everything else.

## Files
- `inventory.ini` — one line per terminal. The **left-hand name is the
  actual hostname** the machine gets — this is your naming sequence
  (`mint-term-01`, `mint-term-02`, ...). Keep it consistent.
- `group_vars/all.yml` — Windows target, admin SSH key, VNC toggle,
  shutdown hotkey.
- `site.yml` — the playbook.

## Setup

1. Fill in `inventory.ini` with real IPs and sequential names.
2. Edit `group_vars/all.yml`:
   - `windows_rdp_host` — your Windows box.
   - `admin_ssh_pubkey` — **replace with your real public key**, this is
     how you'll manage these machines remotely afterwards.
   - `enable_optional_vnc` — leave `true` if you want the on-demand visual
     access option.
3. Run:
   ```bash
   ansible-playbook -i inventory.ini site.yml --ask-become-pass
   ```
   `--ask-become-pass` is only needed the **first time per kiosk** — the
   playbook grants the dedicated `admin` account passwordless sudo
   (NOPASSWD) as part of setup, then locks its password entirely (it's
   meant to be SSH-key-only). After that first run, drop the flag:
   `ansible-playbook site.yml` — a password won't be accepted anymore
   anyway, since there isn't one.

## What happens on each terminal

- Boots straight into Cinnamon, auto-logged in as `kiosk`, no password.
- After ~10s, Remmina launches full-screen against the Windows host.
  **Windows always prompts for username + password** — nothing is saved.
- If the kiosk user presses the shutdown hotkey (`Ctrl+Alt+F10` by
  default, set via `shutdown_hotkey`), the machine powers off — no
  password needed for that specific action, everything else stays locked
  down.

## Remote admin management

A separate `admin` account is created with sudo + SSH-key-only login
(password auth is disabled on SSH entirely). Use it for ongoing
management independent of the kiosk session:

```bash
ssh admin@mint-term-01
sudo apt update && sudo apt upgrade -y
```

Re-running the playbook any time (e.g. after adding new terminals to
`inventory.ini`) re-applies/updates the config on all of them.

### Optional: seeing the actual screen remotely

A `kiosk-vnc.service` is installed but **not** auto-started (keeps things
locked down by default). Start it on demand over an SSH tunnel:

```bash
ssh -L 5900:localhost:5900 admin@mint-term-01 'sudo systemctl start kiosk-vnc'
# then point a VNC viewer at localhost:5900
```

It runs with `-once -localhost`, so it exits after one viewer disconnects
and is never exposed outside the SSH tunnel.

## Automatic updates

`unattended-upgrades` is installed and configured to run daily
(`auto_update_schedule`, default 03:00) and reboot afterwards if needed
(`auto_update_reboot_time`, default 03:30). This is safe here specifically
*because* these are kiosks: a reboot just brings the machine back up
auto-logged-in and straight into the RDP session, no one has to do
anything.

- `auto_update_include_all: true` (default) — installs all available
  updates, not just security ones. Reasonable for unattended machines
  nobody is patching by hand. Set to `false` to restrict to
  security-only updates if you'd rather control feature/package updates
  manually.
- Change `auto_update_reboot_time` / `auto_update_schedule` to a window
  when the terminal is guaranteed to be unused (e.g. overnight).
- Set `auto_update_enabled: false` to turn this off entirely and manage
  updates yourself via the `admin` SSH account.

## Running from a dedicated Ansible control server

If you're running this from a separate Ubuntu server (rather than your
own laptop), do a one-time bootstrap there:

```bash
scp -r mint-rdp-kiosk/ user@control-server:/tmp/
ssh user@control-server
sudo mv /tmp/mint-rdp-kiosk/* /tmp/mint-rdp-kiosk/.* /opt/mint-rdp-kiosk/ 2>/dev/null || true
cd /opt/mint-rdp-kiosk
chmod +x setup-control-node.sh
./setup-control-node.sh
```

The script installs Ansible, generates an SSH keypair *dedicated to this
control server* (`/root/.ssh/mint_kiosk_admin`), and prints the exact
next steps, which are:

1. Put the printed public key into `group_vars/all.yml` as
   `admin_ssh_pubkey`.
2. For each kiosk, `ssh-copy-id` that key to the **bootstrap account**
   (the one manually created during OS install, referenced as
   `ansible_user` in `inventory.ini`) — this is only needed for the
   very first run.
3. Run `ansible-playbook site.yml` from `/opt/mint-rdp-kiosk`.

After that first run, the playbook has installed the same key under the
dedicated `admin` account on every kiosk (see the "Remote admin
management" section above), so subsequent runs — and ad-hoc
`ssh admin@mint-term-01` — just work, no more per-machine setup.

### Keeping the fleet in sync automatically (optional)

`mint-kiosk-sync.service` / `.timer` re-run the playbook daily from the
control server, so config drift gets corrected and newly-added kiosks
in `inventory.ini` get picked up without you manually triggering a run:

```bash
sudo cp mint-kiosk-sync.service mint-kiosk-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mint-kiosk-sync.timer
```

It passes `reboot_after_setup=false` so a daily sync run doesn't reboot
every terminal — reboots stay confined to what `unattended-upgrades`
schedules (see above). Check status with:
```bash
systemctl list-timers mint-kiosk-sync.timer
journalctl -u mint-kiosk-sync.service
```

## Web interface (Semaphore UI)

For easier day-to-day control than the raw CLI — running the playbook
on demand, seeing logs, scheduling, letting a non-Ansible teammate
trigger a run — install **Semaphore UI**, a lightweight self-hosted web
front-end for Ansible. Runs on the control server, alongside everything
above (it just calls the same `site.yml`).

## Semaphore Container Notes
Semaphore runs inside Docker and uses BoltDB as its local database.
All configuration and database files are stored inside the container under /etc/semaphore, which is mounted from Docker volumes defined in docker-compose.yml.

## How Semaphore initializes
On first startup, Semaphore automatically:
Creates config.json inside /etc/semaphore
Creates semaphore.boltdb after the admin user is initialized
Stores runtime data under /var/lib/semaphore
These files appear only after the container starts successfully.
If the container exits immediately, the files will not be created.

## Checking the container status

docker ps -a | grep semaphore
If the container shows Exited (1), it means Semaphore failed to start.

## Viewing logs

docker logs semaphore
This is the most important command — it tells you exactly why Semaphore exited.

## Inspecting the configuration directory inside the container

docker exec -it semaphore ls -l /etc/semaphore
Expected files:

config.json
semaphore.boltdb   # appears after admin initialization

## Restarting Semaphore cleanly
If Semaphore was previously started with incorrect environment variables (for example, MySQL settings), Docker volumes may contain invalid configuration.
To reset Semaphore completely:

docker stop semaphore
docker rm semaphore
docker volume rm semaphore-data
docker volume rm semaphore-lib
docker compose up -d
This forces a clean initialization using BoltDB.

## Accessing the UI
After a successful start, open:

http://<server-ip>:3000

### Install

```bash
cd /opt/mint-rdp-kiosk/semaphore
./install-semaphore.sh
```

This installs Docker if needed, starts Semaphore in a container, mounts
`/opt/mint-rdp-kiosk` into it read-only, and prints the URL + a
generated admin password. Open `http://<control-server-ip>:3000` and
log in.

### Configuring Semaphore for this playbook

One-time setup in the UI:

1. **Key Store → New Key**
   - Type: SSH Key
   - Paste the *private* key from the control server:
     `/root/.ssh/mint_kiosk_admin` (the one `setup-control-node.sh`
     generated). This is what lets Semaphore reach the kiosks.
2. **Repository → New Repository**
   - Type: Local
   - Path: `/ansible` (this is `/opt/mint-rdp-kiosk` as mounted into
     the container)
   - Access Key: the SSH key from step 1 (not needed for a local repo,
     but required for the initial connection to hosts)
3. **Inventory → New Inventory**
   - Type: File
   - File: `inventory.ini` (already in the repo)
   - User Credentials: the SSH key from step 1
4. **Task Templates → New Template**
   - Playbook: `site.yml`
   - Inventory: the one from step 3
   - Repository: the one from step 2
   - Optional: add `--extra-vars "reboot_after_setup=false"` under
     CLI Args for routine syncs, same reasoning as the systemd timer
     below.
5. Click **Run** on the template to trigger it manually, or add a
   **Schedule** (cron syntax) directly on the template if you'd rather
   use Semaphore's built-in scheduler instead of
   `mint-kiosk-sync.timer`.

### Restricting access to the local network

The compose file only publishes port 3000 on the server itself — there's
no reverse proxy or port-forward involved, so it's already unreachable
from outside your LAN as long as your router isn't forwarding that port.

To make that explicit at the OS level (recommended — protects you even
if the router config changes later), scope it with `ufw`:

```bash
sudo apt install -y ufw
sudo ufw allow ssh
sudo ufw allow from 192.168.1.0/24 to any port 3000 proto tcp
sudo ufw enable
sudo ufw status
```

Replace `192.168.1.0/24` with your actual LAN subnet. This blocks port
3000 from anywhere else, including the server's public interface if it
has one.


or tweaking `group_vars/all.yml` and re-running is all doable from the
browser — Semaphore just executes the same `ansible-playbook site.yml`
under the hood, so nothing about the playbook itself changes.

## Publishing this to GitHub

Two files contain your real environment details (IPs, admin's public
key, Windows host) and must **not** be committed as-is — `.gitignore`
already excludes them, and `.example` versions with placeholders are
tracked instead.

On your control server, before the first `git init`:

```bash
cd /opt/mint-rdp-kiosk

# Make sure your real configs match the .example filenames but
# without the real values leaking into git history:
git init
git add .
git status   # confirm inventory.ini and group_vars/all.yml do NOT appear
git commit -m "Initial commit: Mint RDP kiosk playbook"
git remote add origin git@github.com:<you>/mint-rdp-kiosk.git
git push -u origin main
```

If `inventory.ini` or `group_vars/all.yml` *do* show up in `git status`
despite `.gitignore`, it's because git already started tracking them in
an earlier `git add` — untrack them first:
```bash
git rm --cached inventory.ini group_vars/all.yml
```

**Anyone who clones the repo** (including future-you on a fresh
control server) sets it up with:
```bash
cp inventory.ini.example inventory.ini
cp group_vars/all.yml.example group_vars/all.yml
# then edit both with real IPs / hostnames / windows_rdp_host / admin_ssh_pubkey
```

Nothing else in the repo is sensitive:
- The SSH **private** key (`/root/.ssh/mint_kiosk_admin`) never lives in
  this repo — it stays on the control server only, and `.gitignore` has
  a safety net (`id_*`, `*_ed25519`, etc.) in case it's ever copied in
  by mistake.
- Kiosk/admin account passwords are locked (no password exists at all,
  by design), so there's nothing to leak there.
- Semaphore's generated admin password and encryption key live in
  `/opt/semaphore/docker-compose.yml`, which is a **separate directory**
  outside this repo — never pushed either way.

## Things worth deciding / open questions

- **Windows username**: leave `windows_rdp_user` blank if Windows should
  ask for the username too (as in your outline), or pre-fill it if the
  terminals map 1:1 to known Windows accounts.
- **Naming convention**: I used `mint-term-01`, `02`, ... — happy to
  switch to a location/department-based scheme (e.g. `LOBBY-01`,
  `ACCT-03`) if that fits your environment better.
- **Domain-joined Windows?** If `windows_rdp_domain` is relevant, set it
  in `group_vars/all.yml`.
- **VNC exposure**: currently loopback-only via SSH tunnel. If you'd
  rather have it listen on the LAN directly (e.g. no SSH tunnel needed),
  that's a one-line change but a real security tradeoff — let me know.
