# AgentBar

AgentBar is a native macOS menu bar monitor for local Codex and Claude Code usage signals.

## Data Sources

- Codex: reads `~/.codex/accounts/registry.json` and `~/.codex/sessions/**/*.jsonl` in read-only mode. Credential auth files are not opened.
- Claude Code: detects local Claude Code availability. On this Mac, no `~/.claude` CLI usage source was found, so the app reports an unavailable live source instead of fabricating data.
- Costs: local subscription sessions do not expose authoritative per-request cost. The UI shows `N/A` unless a real model pricing or authorized Admin API source is added.

## Build

```bash
swift test
swift build
./script/build_and_run.sh --verify
```

The app bundle is staged at `dist/AgentBar.app`.
