# 🦞 OpenClaw Google Antigravity Plugin

[![OpenClaw](https://img.shields.io/badge/OpenClaw-2026.4.8%2B-blue.svg)](https://github.com/openclaw/openclaw)
[![Plugin](https://img.shields.io/badge/Plugin-google--antigravity--auth-green.svg)](#)
[![Multi-Account](https://img.shields.io/badge/Multi--Account-Auto--Failover-orange.svg)](#)
[![Auto-Refresh](https://img.shields.io/badge/OAuth-Auto--Refresh-brightgreen.svg)](#)

Restores the `google-antigravity-auth` plugin for **OpenClaw 2026.4.8+** with **multi-account auto-failover** and **automatic OAuth token refresh** — keeps your Telegram bot running 24/7 without any manual intervention.

---

## 🛑 The Problem

OpenClaw's native Google Cloud Code Assist (`google-antigravity`) provider requires a plugin that:
1. Performs PKCE OAuth login on a headless VPS (no browser on the server).
2. Packages credentials as `{ token, projectId }` JSON — without this the provider throws `"Missing token or projectId"` on **every single request**.
3. Automatically refreshes access tokens before they expire (they last ~1 hour).

Without this plugin, every message to the bot returns: `⚠️ Something went wrong`.

---

## 🟢 What This Fixes

| Issue | Fix |
|---|---|
| `Missing token or projectId` on every request | `formatApiKey` hook packages `{token, projectId}` correctly |
| Tokens expire → bot stops working | `refreshOAuth` hook auto-refreshes before expiry |
| Single account quota exhausted | Multi-account pool with auto-failover |
| Post-update proxy patch lost | `install.sh` re-applies patches after `npm update` |

---

## 🚀 Installation

Run on the server where OpenClaw is installed:

```bash
git clone https://github.com/kloduss/openclaw-antigravity-plugin.git
cd openclaw-antigravity-plugin
chmod +x install.sh
./install.sh
```

> The script locates your OpenClaw install, installs the plugin, patches the core proxy, and restarts the gateway.

### Authenticate your first Google account

```bash
openclaw models auth login --provider google-antigravity
```

1. Copy the **Login URL** printed in the terminal.
2. Open it in any browser → sign in with your Google Account.
3. Your browser redirects to `localhost:51121/oauth-callback?code=...`
4. **Copy that full URL** from the browser address bar.
5. Paste it back into the terminal and press **Enter**.

Done! Tokens are now stored and **auto-refreshed automatically** via the `refreshOAuth` hook. 🔄

---

## 👥 Multi-Account Auto-Failover

Add as many Google accounts as you want. The plugin automatically switches to the next account when quota runs out.

```bash
# Add a second (or third) account
openclaw models auth login --provider google-antigravity
# → Sign in with a DIFFERENT Google account. Repeat for each account.
```

**How failover works:**
- When a request fails with `429 Too Many Requests` or `403 Forbidden`, the proxy interceptor catches it silently.
- It marks that account as degraded and retries with the next healthiest account.
- Accounts are ranked by fewest recent errors → zero-downtime operation.

```bash
# Check registered accounts
openclaw models auth list --provider google-antigravity
```

---

## 🧠 Selecting a Model

```bash
openclaw configure
```
→ Select **Model** → filter by `google-antigravity` → pick from:
- `gemini-3-flash` (default — fast, free tier)
- `gemini-3.1-pro-low` / `gemini-3.1-pro-high`
- `claude-sonnet-4-6`
- `claude-opus-4-5-thinking`

---

## 🔧 After OpenClaw Updates

When you run `npm update -g openclaw`, the proxy patch may be overwritten. Re-apply everything with one command:

```bash
./install.sh
```

---

## 📁 Repository Structure

```
├── install.sh          # One-shot installer + proxy patcher
└── plugin/
    ├── index.ts        # Plugin source (formatApiKey + refreshOAuth + OAuth login)
    ├── package.json    # Plugin package manifest
    └── openclaw.plugin.json  # Plugin registration manifest
```

---

## 🐛 Troubleshooting

| Symptom | Fix |
|---|---|
| `⚠️ Something went wrong` | Run `./install.sh` to re-apply patches, then `openclaw gateway restart` |
| `Missing token or projectId` | Plugin not loaded — check `openclaw doctor` |
| `all in cooldown` | All tokens expired — add another account or wait 5 min |
| Bot duplicates messages | Clear session: `truncate -s 0 ~/.openclaw/agents/main/sessions/*.jsonl` |

---

## 🔑 Technical Notes

- **`formatApiKey`**: Called by OpenClaw before each request to convert the stored OAuth credential `{access, refresh, expires, projectId}` into the `{token, projectId}` JSON string the provider expects.
- **`refreshOAuth`**: Called by OpenClaw when a token is near expiry. Uses the stored `refresh` token to get a new `access` token from Google without any user interaction.
- **Proxy Patch V5**: Completely intercepts Google Cloud Code Assist network requests to add failover logic:
  - Automatically switches accounts on `429 Too Many Requests`, `403 Forbidden`, `500 Internal Error`, `502 Bad Gateway`, and `503 Service Unavailable (No Capacity)`.
  - **Sticky Sessions:** Reuses the successful active account for 60 minutes to prevent redundant rotation and mitigate ban risks.
  - **SSE Streaming Notifications:** Injects real-time warnings (`⚠️ Antigravity Auto-Failover Triggered`) directly into the Telegram response stream whenever an account switch occurs.
  - Fixes `google-gemini-cli.js` token fallback to handle ES Modules natively.
