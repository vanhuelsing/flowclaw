# FlowClaw

**Automate your agent workflows. Stay in control of what happens next.**

FlowClaw orchestrates your AI agent teams through automated multi-step workflows — with approval gates that pause and wait for your go-ahead before anything critical runs. Integrates with Notion, n8n, and Discord (all optional).

## Features

- ✅ **Approval Gates** — Workflows pause and wait for your go-ahead before anything critical runs. You stay in control, always.
- 🔄 **YAML Workflow Definitions** — Write your workflows in simple, readable YAML. Version-control them, share them, tweak them without touching code.
- 🤖 **Multi-Agent Orchestration** — Route tasks to the right OpenClaw agent for each step. FlowClaw handles the sequencing so you don't have to.
- 📊 **Notion Integration** — Pick up tasks from Notion and write status back automatically.
- 🚀 **n8n Integration** — Trigger workflows from n8n via HTTP. Drop-in compatible.
- 🔔 **Discord Notifications** — Know what's happening at every step, in real time.
- 🛡️ **Runs Reliably** — Idempotent execution, SQLite-backed state, structured logging, Gunicorn multi-worker, health + metrics endpoints.

## Before You Start

FlowClaw v1.0.0 is fully functional for workflow orchestration, approval gates, Notion sync, and Discord notifications. Agent dispatch and deploy steps work but need to be wired up for your specific setup — they're not auto-configured out of the box.

→ See [INTEGRATION-STEPS.md](docs/INTEGRATION-STEPS.md) for what to configure first.

## Quick Start

**Prerequisites:** Python 3.8+, OpenClaw with configured agents. Optional: n8n, Notion API key, Discord bot token.

1. Install dependencies:
   ```bash
   pip3 install -r src/requirements.txt
   ```

2. Copy and configure environment variables:
   ```bash
   cp config/example.env .env
   # Edit .env with your API keys
   ```

3. Start the executor:
   ```bash
   python3 src/workflow-executor.py
   ```

4. Import `src/n8n-workflow.json` into your n8n instance and update the placeholder values.

5. Configure n8n to call `http://127.0.0.1:8765/workflow/execute`

## Built to Keep Running

FlowClaw runs as a persistent service and handles the edge cases you'd rather not think about:

- **Idempotent execution** — trigger the same workflow twice, it only runs once
- **Gunicorn multi-worker** — concurrent requests handled, no bottlenecks
- **Structured logging** — readable in your terminal, parseable by log tools
- **Health + metrics endpoints** — `/health` and `/metrics` work out of the box
- **Service templates** — systemd (Linux) and LaunchAgent (macOS) configs included

## API Endpoints

Once running, FlowClaw exposes the following endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/workflow/execute` | POST | Execute a workflow |
| `/workflow/approve` | POST | Approve a pending step |
| `/workflow/resume` | POST | Resume a paused workflow |
| `/notify/discord` | POST | Send Discord notification |
| `/metrics` | GET | Execution metrics |
| `/dashboard` | GET | Web dashboard |

## Project Structure

```
flowclaw/
├── src/
│   ├── workflow-executor.py    # Main application
│   ├── n8n-workflow.json       # n8n workflow template
│   ├── requirements.txt        # Python dependencies
│   ├── workflow-schema.json    # YAML workflow schema
│   ├── scripts/
│   │   └── start-workflow-executor.sh  # Gunicorn launcher
│   └── workflows/
│       ├── complex-task.yaml   # Multi-phase workflow
│       ├── simple-task.yaml    # Standard workflow
│       ├── fastlane-deploy.yaml # Quick deploy workflow
│       ├── content-task.yaml   # Content creation workflow
│       └── test-demo.yaml      # Test/demo workflow
├── config/
│   ├── example.env             # Environment variable template
│   ├── launchagent.plist       # macOS LaunchAgent template
│   └── workflow-executor.service # systemd service template
├── docs/
│   ├── n8n-integration-guide.md
│   └── INTEGRATION-STEPS.md
├── README.md
├── SKILL.md
└── CHANGELOG.md
```

## Requirements

- Python 3.8+
- OpenClaw (for agent execution)
- n8n (optional — for Notion trigger automation)
- Notion API key (optional — for task management)
- Discord bot token (optional — for notifications)

## License

MIT

## Author

[@vanhuelsing](https://github.com/vanhuelsing)
