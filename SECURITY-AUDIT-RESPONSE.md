# FlowClaw v1.0.2 — Security Audit Response

**Date:** 2026-03-30  
**Auditor:** Engineering Agent  
**Triggered by:** skill-vetter security review  
**Scope:** Credential auto-loading + subprocess/command execution audit

---

## 1. Credential Auto-Loading from `~/.openclaw/openclaw.json`

### Current Behavior

The function `_load_env_from_openclaw()` (line 267) reads `~/.openclaw/openclaw.json` and silently injects API keys into `os.environ` at module load time. It's called in three places:

| Location | Line | When |
|----------|------|------|
| Module-level | 283 | On first import (every process start) |
| `_on_startup()` | 1879 | On Gunicorn worker init (redundant) |
| Gateway URL fallback | 290–298 | Separate `OPENCLAW_CONFIG.exists()` check for gateway config |

**What it loads:**
- `NOTION_API_KEY`
- `DISCORD_BOT_TOKEN`
- `N8N_API_KEY`
- `OPENCLAW_GATEWAY_URL`
- `OPENCLAW_GATEWAY_TOKEN`
- `WORKFLOW_EXECUTOR_API_KEY`

**Security issue confirmed:** This silently inherits credentials the user never explicitly provided to FlowClaw. If FlowClaw has a vulnerability (e.g., SSRF, log leak, agent injection), the blast radius includes every credential in the user's global OpenClaw config — not just what they intended to share.

The gateway URL/token fallback block (lines 290–298) has the same issue: it reads `openclaw.json` unconditionally without opt-in.

### Proposed Fix

Add a `FLOWCLAW_LOAD_OPENCLAW_CONFIG` environment variable that must be explicitly set to `true` for the config file to be read. Default behavior: **off**.

#### Code Change: `_load_env_from_openclaw()` (replace lines 267–280)

```python
def _load_env_from_openclaw() -> None:
    """Load API keys from openclaw.json env block — OPT-IN ONLY.
    
    Set FLOWCLAW_LOAD_OPENCLAW_CONFIG=true to enable.
    By default, FlowClaw only reads credentials from environment variables or .env files.
    """
    opt_in = os.environ.get("FLOWCLAW_LOAD_OPENCLAW_CONFIG", "").lower().strip()
    if opt_in != "true":
        return

    if not OPENCLAW_CONFIG.exists():
        return

    log.warning(
        "Loading credentials from openclaw.json — this is opt-in behavior. "
        "Set credentials via .env or environment variables for tighter isolation.",
        config_path=str(OPENCLAW_CONFIG),
    )

    try:
        config = json.loads(OPENCLAW_CONFIG.read_text())
        env_block = config.get("env", {})
        loaded_keys = []
        for key in [
            "NOTION_API_KEY", "DISCORD_BOT_TOKEN", "N8N_API_KEY",
            "OPENCLAW_GATEWAY_URL", "OPENCLAW_GATEWAY_TOKEN",
            "WORKFLOW_EXECUTOR_API_KEY",
        ]:
            if key not in os.environ and key in env_block:
                os.environ[key] = env_block[key]
                loaded_keys.append(key)
        if loaded_keys:
            log.info(
                "Loaded credentials from openclaw.json",
                keys=loaded_keys,
                count=len(loaded_keys),
            )
    except Exception as exc:
        log.warning("Failed to load env from openclaw.json", error=str(exc))
```

#### Code Change: Gateway URL fallback (replace lines 290–298)

```python
if not OPENCLAW_GATEWAY_URL and os.environ.get("FLOWCLAW_LOAD_OPENCLAW_CONFIG", "").lower().strip() == "true":
    if OPENCLAW_CONFIG.exists():
        try:
            config = json.loads(OPENCLAW_CONFIG.read_text())
            gateway = config.get("gateway", {})
            if gateway.get("bind", "loopback") == "loopback":
                OPENCLAW_GATEWAY_URL = "http://127.0.0.1:18789"
            if not OPENCLAW_GATEWAY_TOKEN:
                OPENCLAW_GATEWAY_TOKEN = config.get("gateway", {}).get("auth", {}).get("token", "")
        except Exception:
            pass
```

#### Code Change: Remove redundant call in `_on_startup()` (line 1879)

The `_load_env_from_openclaw()` call at module level (line 283) already runs before `_on_startup()`. The call inside `_on_startup()` is redundant and should be removed to avoid confusion about when credentials are loaded.

#### Config Change: `config/example.env`

Add after the `HOST=127.0.0.1` line:

```env
# ── Credential Isolation ─────────────────────────────
# By default, FlowClaw only reads credentials from environment variables
# and .env files. Set this to "true" to also load missing credentials
# from ~/.openclaw/openclaw.json. Only enable this if you understand
# that ALL credentials in your OpenClaw config become accessible to FlowClaw.
FLOWCLAW_LOAD_OPENCLAW_CONFIG=false
```

#### Docs Change: README.md Security Notes section

Replace the "Credential loading" bullet with:

```markdown
- **Credential isolation (default):** FlowClaw only reads API keys from environment variables or `.env` files. It does **not** automatically inherit credentials from `~/.openclaw/openclaw.json`. To opt in to config file loading, set `FLOWCLAW_LOAD_OPENCLAW_CONFIG=true` — but be aware this gives FlowClaw access to all credentials in your global OpenClaw config.
```

---

## 2. Subprocess and Command Execution Audit

### 2.1 Inventory of All Subprocess Calls

| # | Location | Call | What It Does |
|---|----------|------|-------------|
| 1 | `_step_spawn_agent` (line 1104) | `subprocess.Popen(cmd, ...)` | Spawns an OpenClaw agent CLI process |
| 2 | `_step_wait_completion` (line 1125–1137) | `proc.communicate()` / `proc.kill()` | Waits for spawned agent to finish; kills on timeout |
| 3 | `_step_qa_check` (line 1248) | `subprocess.run(["python3", str(script_path), url], ...)` | Runs a QA validation script |
| 4 | `_step_deploy` (line 1285) | `subprocess.run(cmd, cwd=work_dir, ...)` | Runs `vercel --prod --yes` deploy |

### 2.2 Other Dangerous Patterns

| Pattern | Found? | Details |
|---------|--------|---------|
| `os.system()` | ❌ No | Not used anywhere |
| `exec()` | ❌ No | Not used (only `executor.execute()` method calls) |
| `eval()` | ❌ No | Not used anywhere |
| `shell=True` | ❌ No | All subprocess calls use list-form arguments (safe) |
| `pickle` | ⚠️ Import only | `import pickle` on line 27 but **never used** — dead import |

### 2.3 Detailed Analysis of Each Subprocess Call

#### Call #1: `_step_spawn_agent` — `subprocess.Popen` (line 1104)

```python
cmd = [openclaw_bin, "agent", "--agent", agent_id, "--message", task_text,
       "--session-id", session_id, "--timeout", str(timeout_s), "--json"]
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
```

**Input sources:**
- `openclaw_bin` — Resolved via `shutil.which("openclaw")` or hardcoded candidate paths. ✅ Safe (not user-controlled).
- `agent_id` — From workflow YAML config or `_vars` (originally from `AgentSelector.select()`). ⚠️ **Moderate risk** — could contain arbitrary strings from Notion task data via template resolution.
- `task_text` — From workflow YAML config, possibly loaded from a file via `file:` prefix. ⚠️ **Moderate risk** — flows from Notion description through template vars.
- `session_id` — Constructed as `f"wf-{self.run_id}-{agent_id}"`. Inherits `agent_id` risk.
- `timeout_s` — Cast to `int()`, then `str()`. ✅ Safe.

**Verdict:** ⚠️ **Moderate risk.** The `agent_id` and `task_text` values flow through from Notion task data. Since subprocess uses list-form (no `shell=True`), there's no shell injection — but a malicious Notion task could specify an arbitrary `agent_id` which becomes a CLI argument. In practice, `openclaw agent --agent <value>` would reject unknown agent names, so risk is bounded by OpenClaw's own validation.

**Recommendation:** Add `agent_id` validation against an allowlist:

```python
ALLOWED_AGENTS = {"frontend", "backend", "creative", "quality", "devops", "main"}

if agent_id not in ALLOWED_AGENTS:
    return {"status": "failed", "error": f"Unknown agent: {agent_id!r}. Allowed: {sorted(ALLOWED_AGENTS)}"}
```

#### Call #2: `_step_wait_completion` — `proc.communicate()` (line 1125–1137)

```python
stdout, stderr = proc.communicate(timeout=remaining)
```

**Verdict:** ✅ **Safe.** This only waits for an already-spawned process and reads its output. The timeout + `proc.kill()` on `TimeoutExpired` is correct.

#### Call #3: `_step_qa_check` — `subprocess.run` (line 1248)

```python
script_path = _safe_path(FLOWCLAW_DIR, script)
proc = subprocess.run(["python3", str(script_path), url],
                      capture_output=True, text=True, timeout=60)
```

**Input sources:**
- `script` — From workflow YAML config `cfg.get("script")`. Validated via `_safe_path()` which prevents path traversal. ✅ Path-safe.
- `url` — From workflow YAML config or `_vars` (user data from Notion). ⚠️ **Low risk** — passed as a single argument to the script (no shell expansion), but the script itself could do anything with it.

**Verdict:** ⚠️ **Low-to-moderate risk.** The `_safe_path()` check ensures the script must exist under `FLOWCLAW_DIR`, preventing execution of arbitrary scripts outside the workflow directory. However:
1. The script that runs is **user-authored** — this is by design (QA scripts are part of the workflow).
2. The `url` argument passes through without sanitization, but since there's no `shell=True`, it can't cause shell injection.

**Recommendation:** Consider adding a check that the script is actually a `.py` file and not executable with unexpected interpreters:

```python
if not str(script_path).endswith('.py'):
    return {"status": "failed", "error": "QA scripts must be .py files"}
```

#### Call #4: `_step_deploy` — `subprocess.run` (line 1285)

```python
cmd = ["vercel"] + (["--prod"] if prod else []) + ["--yes"]
proc = subprocess.run(cmd, cwd=work_dir, capture_output=True, text=True, timeout=300)
```

**Input sources:**
- `cmd` — Static: `["vercel", "--prod", "--yes"]`. ✅ Safe (no user data in command).
- `work_dir` — From `_safe_path(WORKSPACE, cwd)` or `WORKSPACE / project`. The `cwd` value goes through `_safe_path()` which prevents traversal. The `project` value comes from YAML config/vars. ⚠️ **Low risk** — `project` is not validated by `_safe_path()` when used as `WORKSPACE / project`, but since it only sets the working directory for `vercel`, the impact is limited to deploying from the wrong directory.

**Verdict:** ⚠️ **Low risk.** The deploy command is static and safe. The `cwd` path has proper validation when explicitly provided. The `project` fallback path should also use `_safe_path()`.

**Recommendation:**

```python
# Replace line 1276:
#   work_dir = WORKSPACE / project
# With:
    work_dir = _safe_path(WORKSPACE, project)
```

### 2.4 `pickle` Import (line 27)

```python
import pickle
```

**Verdict:** ⚠️ **Dead code.** `pickle` is imported but never used anywhere in the file. The `pickle` module is inherently dangerous for deserialization of untrusted data, but since it's not called, there's no active vulnerability. However, it should be removed to:
1. Avoid confusion for future auditors
2. Prevent accidental future use without proper review

**Recommendation:** Remove `import pickle` from line 27.

---

## 3. Summary of Recommendations

### Priority 1 — Must fix before next release

| # | Issue | Fix | Risk if ignored |
|---|-------|-----|-----------------|
| 1 | Silent credential auto-loading from `openclaw.json` | Add `FLOWCLAW_LOAD_OPENCLAW_CONFIG=true` opt-in gate | Users unknowingly expose unrelated credentials |
| 2 | `agent_id` not validated in `_step_spawn_agent` | Add allowlist check | Arbitrary agent names passed to CLI |
| 3 | `project` path not validated in `_step_deploy` fallback | Use `_safe_path(WORKSPACE, project)` | Potential path traversal in `cwd` |

### Priority 2 — Should fix (hardening)

| # | Issue | Fix | Risk if ignored |
|---|-------|-----|-----------------|
| 4 | Dead `import pickle` | Remove the import | Confusion for auditors; risk of accidental misuse |
| 5 | Redundant `_load_env_from_openclaw()` call in `_on_startup()` | Remove (module-level call suffices) | Confusion about credential loading lifecycle |
| 6 | QA script not restricted to `.py` extension | Add file extension check | Minor — `_safe_path` already bounds to `FLOWCLAW_DIR` |

### Priority 3 — Nice to have

| # | Issue | Fix |
|---|-------|-----|
| 7 | No outbound network call audit logging | Add structured log for every external HTTP request (Notion, Discord) with destination URL |
| 8 | `url` passed to QA script without format validation | Add URL format check (must start with `http://` or `https://`) |

### What's Already Good ✅

- **No `shell=True` anywhere** — all subprocess calls use list-form arguments
- **No `eval()` or `exec()`** — no dynamic code execution
- **No `os.system()`** — only `subprocess` module used
- **`_safe_path()` used consistently** for file operations (prevents path traversal)
- **`_VALID_NAME_RE` enforces** alphanumeric workflow names (prevents injection via workflow name)
- **HMAC-based auth** with constant-time comparison (`hmac.compare_digest`)
- **Discord channel allowlist** prevents messages to arbitrary channel IDs
- **Timeouts on all subprocess calls** (60s for QA, 300s for deploy, configurable for agents)
- **Structured logging** doesn't leak credential values

---

## 4. Files to Modify (Implementation Checklist)

When approved, these changes should be applied:

- [ ] `src/workflow-executor.py` — Gate `_load_env_from_openclaw()` behind `FLOWCLAW_LOAD_OPENCLAW_CONFIG`
- [ ] `src/workflow-executor.py` — Gate gateway URL fallback (lines 290–298) behind same env var
- [ ] `src/workflow-executor.py` — Remove redundant `_load_env_from_openclaw()` from `_on_startup()`
- [ ] `src/workflow-executor.py` — Add `ALLOWED_AGENTS` allowlist in `_step_spawn_agent`
- [ ] `src/workflow-executor.py` — Use `_safe_path()` for `project` in `_step_deploy` fallback
- [ ] `src/workflow-executor.py` — Remove `import pickle` (line 27)
- [ ] `config/example.env` — Add `FLOWCLAW_LOAD_OPENCLAW_CONFIG=false` with documentation
- [ ] `README.md` — Update Security Notes section
- [ ] `CHANGELOG.md` — Document security changes under v1.0.3

---

*End of audit. No source files were modified — review this document and approve before implementation.*
