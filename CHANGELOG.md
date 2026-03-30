# Changelog

## v1.0.0 (2026-03-30)

First public release. The core workflow engine, approval gates, Notion sync, and n8n integration are stable. Agent dispatch and deploy steps are functional but require configuration for your specific setup — see [INTEGRATION-STEPS.md](docs/INTEGRATION-STEPS.md).

### Added
- YAML-driven multi-step workflow execution
- Human-in-the-loop approval gates
- n8n integration via HTTP endpoints
- Notion task management integration (read tasks, update status)
- Discord notification support
- Idempotent request handling (SQLite-backed)
- Gunicorn production deployment support
- 5 workflow templates: complex, standard, fastlane, content, test
- Structured JSON logging
- Health check and metrics endpoints
- Web dashboard at `/dashboard`
- macOS LaunchAgent and Linux systemd service templates
