# Changelog

## v1.0.3 (2026-03-30)

Security hardening (audit response):

- **Credential isolation:** `_load_env_from_openclaw()` is now opt-in only. FlowClaw no longer silently reads `~/.openclaw/openclaw.json` at startup. Set `FLOWCLAW_LOAD_OPENCLAW_CONFIG=true` to enable. Gateway URL fallback block gated by the same variable.
- **Agent spawn validation:** Added `ALLOWED_AGENTS` allowlist check in `_step_spawn_agent`. Unknown agent IDs are rejected before any subprocess is launched.
- **Deploy path validation:** `_step_deploy` fallback path (`WORKSPACE / project`) now goes through `_safe_path()`, preventing path traversal via workflow YAML config.
- **Dead code removed:** `import pickle` (unused) removed from module imports.
- **Redundant call removed:** `_load_env_from_openclaw()` call inside `_on_startup()` removed (module-level call suffices).
- `config/example.env`: Added `FLOWCLAW_LOAD_OPENCLAW_CONFIG=false` with documentation; updated stale NOTE comment.
- `README.md`: Updated Security Notes to reflect new opt-in credential loading behaviour.

## v1.0.2 (2026-03-30)

- Security: default bind address changed to 127.0.0.1 (local only)
- Added credential loading documentation
- Declared required/optional environment variables in skill metadata

## v1.0.1 (2026-03-30)

- Clarified that Notion, n8n, and Discord integrations are optional

## v1.0.0 (2026-03-30)

First public release.

- Multi-step workflow execution defined in YAML
- Human-in-the-loop approval gates
- Notion task sync (optional)
- n8n HTTP trigger integration (optional)
- Discord notifications (optional)
- 5 workflow templates included
- macOS and Linux service templates
