# Third-party notices

`telemetry.py` is adapted from [drkang7/codex-token-hud](https://github.com/drkang7/codex-token-hud), version `v1.2.0-beta.1`, under the MIT License. The upstream copyright and permission notice are retained in `LICENSE`.

Local changes include whole-response client-observed timing, avoiding late item delivery timestamps, and ignoring duplicate tool outputs as timing boundaries. The inline renderer, agent, installer, and reader integration are specific to this project.

Context reporting was researched against [Javis603/token-monitor's Codex context reader](https://github.com/Javis603/token-monitor/blob/bb6ec57483fdbd8491fb4c83320c4710d8f6a673/src/shared/providers/codex/sessionContext.js), Codex's token protocol, and local rollout observations. This project uses the reported last total and per-session window, with explicit invalidation after compaction, rollback, or model changes.

Node.js and Python are user-installed runtimes. Their binaries are not redistributed in this repository or source release.

Codex is an OpenAI product. This project is an unofficial local customization and is not affiliated with or endorsed by OpenAI.
