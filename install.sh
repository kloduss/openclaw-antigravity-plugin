#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# OpenClaw Google Antigravity Auth — Auto-Installer + Multi-Account Failover
# Supports: OpenClaw 2026.4.8+
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

echo ""
echo "🦞 OpenClaw Google Antigravity Auth — Installer"
echo "================================================="
echo ""

# ── 1. Locate OpenClaw ────────────────────────────────────────────────────────
OPENCLAW_BIN=""
for candidate in \
    "$(which openclaw 2>/dev/null || true)" \
    "$HOME/.npm-global/bin/openclaw" \
    "$HOME/.local/bin/openclaw" \
    "/usr/local/bin/openclaw" \
    "/usr/bin/openclaw"; do
  if [ -x "$candidate" ]; then
    OPENCLAW_BIN="$candidate"
    break
  fi
done

if [ -z "$OPENCLAW_BIN" ]; then
  echo "❌  Error: openclaw executable not found. Install OpenClaw first."
  exit 1
fi
echo "✅  Found OpenClaw at: $OPENCLAW_BIN"

# ── 2. Locate pi-ai proxy (google-gemini-cli.js) ─────────────────────────────
CLI_JS_PATH=$(find \
    "$HOME/.npm-global" \
    "$HOME/.local" \
    /usr \
    -path '*/openclaw/node_modules/@mariozechner/pi-ai/dist/providers/google-gemini-cli.js' \
    -type f 2>/dev/null | head -n 1 || true)

if [ -z "${CLI_JS_PATH:-}" ]; then
  NPM_ROOT=$(npm root -g 2>/dev/null || true)
  if [ -n "${NPM_ROOT:-}" ]; then
    CLI_JS_PATH="$NPM_ROOT/openclaw/node_modules/@mariozechner/pi-ai/dist/providers/google-gemini-cli.js"
  fi
fi

if [ ! -f "${CLI_JS_PATH:-/dev/null}" ]; then
  echo "⚠️   Warning: Could not find google-gemini-cli.js — proxy patch skipped."
  CLI_JS_PATH=""
fi

# ── 3. Install Plugin ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SOURCE_DIR="$SCRIPT_DIR/plugin"
PLUGIN_DEST_DIR="$HOME/.openclaw/workspace/google-antigravity-auth-backup"
INSTALL_PATH="$HOME/.openclaw/extensions/google-antigravity-auth"

echo "📦  Installing plugin to $INSTALL_PATH ..."
mkdir -p "$INSTALL_PATH"
cp -r "$PLUGIN_SOURCE_DIR/"* "$INSTALL_PATH/"

# Also keep a backup copy in workspace
mkdir -p "$PLUGIN_DEST_DIR"
cp -r "$PLUGIN_SOURCE_DIR/"* "$PLUGIN_DEST_DIR/"

# ── 4. Register Plugin in openclaw.json ───────────────────────────────────────
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"

echo "⚙️   Configuring openclaw.json ..."
node - << NODEJS_EOF
const fs = require('fs');
const file = '$OPENCLAW_JSON';
if (!fs.existsSync(file)) { console.log('No openclaw.json found, skipping.'); process.exit(0); }
const cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
if (!cfg.plugins) cfg.plugins = {};
if (!Array.isArray(cfg.plugins.allow)) cfg.plugins.allow = [];
if (!cfg.plugins.allow.includes('google-antigravity-auth')) cfg.plugins.allow.push('google-antigravity-auth');
if (!cfg.plugins.entries) cfg.plugins.entries = {};
if (!cfg.plugins.entries['google-antigravity-auth']) cfg.plugins.entries['google-antigravity-auth'] = { enabled: true };
if (!cfg.plugins.installs) cfg.plugins.installs = {};
cfg.plugins.installs['google-antigravity-auth'] = {
  source: 'path',
  sourcePath: '$PLUGIN_DEST_DIR',
  installPath: '$INSTALL_PATH',
  version: '2026.2.2',
  installedAt: new Date().toISOString()
};
fs.writeFileSync(file, JSON.stringify(cfg, null, 2));
console.log('openclaw.json updated.');
NODEJS_EOF

# ── 5. Apply Core Proxy Patch (Multi-Account Failover) ───────────────────────
if [ -n "${CLI_JS_PATH:-}" ]; then
  echo "🔧  Applying multi-account failover patch to: $CLI_JS_PATH"
  AUTH_PROFILES_FILE="$HOME/.openclaw/agents/main/agent/auth-profiles.json"

  # Write the patch script to a temp file to avoid bash variable-expansion conflicts
  PATCH_SCRIPT=$(mktemp /tmp/antigravity_patch_XXXXXX.js)

  cat > "$PATCH_SCRIPT" << 'PATCH_JS_EOF'
const fs = require('fs');
const CLI_JS = process.argv[1];
const AUTH_PROFILES = process.argv[2];

let content = fs.readFileSync(CLI_JS, 'utf8');

// ── Patch 1: Legacy token fallback (V3) ─────────────────────────────────────
const PATCH1_MARKER = '// ANTIGRAVITY_PATCH_V3';
const OLD_CATCH = `            catch {\n                throw new Error("Invalid Google Cloud Code Assist credentials. Use /login to re-authenticate.");\n            }`;
const NEW_CATCH = `            catch {\n                ${PATCH1_MARKER}: legacy string token fallback\n                try { const o = JSON.parse(apiKeyRaw); accessToken = o.access || o.token; projectId = o.projectId || projectId; } catch { accessToken = apiKeyRaw; }\n            }`;

if (content.includes(PATCH1_MARKER)) {
  console.log('  ℹ️   Patch 1 already applied (V3).');
} else if (content.includes(OLD_CATCH)) {
  content = content.replace(OLD_CATCH, NEW_CATCH);
  console.log('  ✅  Patch 1 applied: legacy token fallback (V3).');
} else {
  console.log('  ⚠️   Patch 1 skipped: target signature not found in this version.');
}

// ── Patch 2: Multi-account failover fetch interceptor ─────────────────────────
const MARKER = '/* ANTIGRAVITY_MULTIACCOUNT_PATCH_V2 */';
if (!content.includes(MARKER)) {
  const INJECTION = `
${MARKER}
(function injectAntigravityFailover() {
  const _fs = require('fs');
  const _AUTH = ${JSON.stringify(AUTH_PROFILES)};
  const _TOKEN_URL = 'https://oauth2.googleapis.com/token';
  const _CID = Buffer.from('MTA3MTAwNjA2MDU5MS10bWhzc2luMmgyMWxjcmUyMzV2dG9sb2poNGc0MDNlcC5hcHBzLmdvb2dsZXVzZXJjb250ZW50LmNvbQ==','base64').toString();
  const _CS = Buffer.from('R09DU1BYLUs1OEZXUjQ4NkxkTEoxbUxCOHNYQzR6NnFEQWY=','base64').toString();

  function _loadPool() {
    try {
      if (!_fs.existsSync(_AUTH)) return [];
      const raw = JSON.parse(_fs.readFileSync(_AUTH,'utf8'));
      const p = raw.profiles || {}, s = raw.usageStats || {};
      return Object.entries(p)
        .filter(([,v]) => v.provider==='google-antigravity' && v.type==='oauth')
        .map(([id,v]) => { const st=s[id]||{}; return {id,email:v.email||id,access:v.access||'',refresh:v.refresh||'',expires:v.expires||0,projectId:v.projectId||'rising-fact-p41fc',errors:st.errorCount||0,failedAt:st.lastFailureAt||0}; })
        .sort((a,b) => a.errors!==b.errors ? a.errors-b.errors : a.failedAt-b.failedAt);
    } catch { return []; }
  }
  function _markFailed(id) {
    try {
      const raw = JSON.parse(_fs.readFileSync(_AUTH,'utf8'));
      if (!raw.usageStats) raw.usageStats = {};
      const st = raw.usageStats[id] || {};
      st.errorCount = (st.errorCount||0)+1; st.lastFailureAt = Date.now();
      raw.usageStats[id] = st;
      _fs.writeFileSync(_AUTH, JSON.stringify(raw,null,2));
    } catch {}
  }
  async function _refresh(id, rt) {
    try {
      const res = await _origFetch(_TOKEN_URL, {method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:_CID,client_secret:_CS,grant_type:'refresh_token',refresh_token:rt})});
      if (!res.ok) return null;
      const d = await res.json(); const ac = d.access_token?.trim(); if (!ac) return null;
      if (_fs.existsSync(_AUTH)) { const raw=JSON.parse(_fs.readFileSync(_AUTH,'utf8')); if(raw.profiles?.[id]){raw.profiles[id].access=ac;raw.profiles[id].expires=Date.now()+(d.expires_in||3600)*1000-300000;_fs.writeFileSync(_AUTH,JSON.stringify(raw,null,2));} }
      return ac;
    } catch { return null; }
  }

  const _origFetch = globalThis.fetch;
  globalThis.fetch = async function antigravityFetch(url, init) {
    const urlStr = typeof url==='string' ? url : (url?.toString?.() || '');
    if (!urlStr.includes('cloudcode-pa.googleapis.com')) return _origFetch(url,init);
    const pool = _loadPool();
    if (pool.length <= 1) return _origFetch(url,init);
    let lastRes;
    for (const acc of pool) {
      let token = acc.access;
      if (acc.expires < Date.now() && acc.refresh) { const r = await _refresh(acc.id, acc.refresh); if (r) token = r; }
      const h = new Headers(init?.headers); h.set('Authorization','Bearer '+token);
      const res = await _origFetch(url, {...init, headers:h});
      if (res.status===429 || res.status===403) { console.error('[antigravity-failover] '+acc.email+' returned '+res.status+', trying next...'); _markFailed(acc.id); lastRes=res; continue; }
      return res;
    }
    return lastRes;
  };
  console.error('[antigravity-failover] active, pool size: '+_loadPool().length);
})();
`;
  content = INJECTION + '\n' + content;
  console.log('  ✅  Patch 2 applied: multi-account failover interceptor.');
} else {
  console.log('  ℹ️   Patch 2 already applied.');
}

// ── Patch 3: Field fix — parsed.token || parsed.access ────────────────────────
const PATCH3_MARKER = '// ANTIGRAVITY_FIELD_FIX';
const OLD_TOKEN = '                accessToken = parsed.token;\n                projectId = parsed.projectId;';
const NEW_TOKEN = `                accessToken = parsed.token || parsed.access; ${PATCH3_MARKER}\n                projectId = parsed.projectId;`;

if (content.includes(PATCH3_MARKER)) {
  console.log('  \u2139\ufe0f   Patch 3 already applied (field fix).');
} else if (content.includes(OLD_TOKEN)) {
  content = content.replace(OLD_TOKEN, NEW_TOKEN);
  console.log('  \u2705  Patch 3 applied: parsed.token || parsed.access fallback.');
} else {
  console.log('  \u26a0\ufe0f   Patch 3 skipped: target not found (may already be correct).');
}

fs.writeFileSync(CLI_JS, content);
console.log('  ✅  Proxy file saved.');
PATCH_JS_EOF

  node "$PATCH_SCRIPT" "$CLI_JS_PATH" "$AUTH_PROFILES_FILE"
  rm -f "$PATCH_SCRIPT"
  echo "✅  Core proxy patch complete."
fi

# ── 5.5 Patch pi-ai Models ──────────────────────────────────────────────────
echo "🔧  Applying 1M context limits patch to openclaw models..."
MODELS_FILE="$(npm root -g)/openclaw/node_modules/@mariozechner/pi-ai/dist/models.generated.js"
if [ -f "$MODELS_FILE" ]; then
  # Inject contextWindow before cost block for gemini models
  sed -i 's/cost: {/contextWindow: 1000000, cost: {/g' "$MODELS_FILE"
  echo "  ✅  Models file patched."
else
  echo "  ⚠️   Models file not found at $MODELS_FILE"
fi

# ── 6. Restart Gateway ────────────────────────────────────────────────────────
echo "🔄  Restarting OpenClaw gateway..."
"$OPENCLAW_BIN" gateway restart && echo "✅  Gateway restarted." || echo "⚠️   Gateway restart failed — please restart manually."

# ── 7. Done ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "🎉  Installation complete!"
echo "════════════════════════════════════════════════════"
echo ""
echo "📋  NEXT STEPS:"
echo ""
echo "  1. Authenticate your FIRST Google Account:"
echo "     openclaw models auth login --provider google-antigravity"
echo ""
echo "  2. (Optional) Add a SECOND account for auto-failover:"
echo "     openclaw models auth login --provider google-antigravity"
echo "     → Sign in with a DIFFERENT Google account."
echo "     → Repeat for as many accounts as you want."
echo ""
echo "  3. Choose your preferred model:"
echo "     openclaw configure  →  Model  →  google-antigravity"
echo ""
echo "  When quota is exhausted, the bot auto-switches accounts. 🔄"
echo ""
