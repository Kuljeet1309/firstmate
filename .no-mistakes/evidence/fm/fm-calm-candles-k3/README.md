# Calm candles scene: live validation evidence (2026-09-21)

Every artifact below was captured from the real Claude Code 2.1.278 TUI running the
worktree's `.claude/mods/firstmate-calm` mod through the project's `.claude/skills`
auto-load path, under a private tmux socket (160x44 unless stated), with an isolated
project and `FM_HOME` under /tmp and `--model haiku`. Images are SVG renderings of
`tmux capture-pane -e` output (the exact cells and 256-color SGR codes Claude Code
painted). No browser or image tool was on PATH here to make PNG screenshots.

| Artifact | What it shows |
| --- | --- |
| `candles-dark/candles-dark-screen.svg` | Full Claude Code screen mid-turn: two rows of candles replace the working row (dark theme, 256-color 71/204) |
| `candles-dark/candles-dark-replay.svg` | Animated replay of the captured working row at captured timing |
| `candles-dark/candles-dark-filmstrip.svg` | Consecutive frames: each is the previous one moved one column left |
| `candles-light/*.svg` | Same under `theme: light` (256-color 29/125) |
| `pace/candles-pace-replay.svg`, `pace/analysis.json` | 14 s window: 15 one-column left scrolls, mean 910 ms; the boat's hull steps at mean 924 ms under the same conditions |
| `narrow-resize/narrow-resize.svg` | One turn, pane resized mid-turn 160 → 40 → 12 → 6 → 3 → 100 columns: always two rows, no wrap, reflows |
| `setting-values.svg` | Working row per `config/calm-scene` value: absent/`Candles`/`sparkles`/empty draw the boat; `candles` and `  candles  ` draw candles |
| `flag-guard.svg` | Flag unset, `true`, `0` with candles chosen: stock spinner (with `true` the engine loads the module and the mod stays inert) |
| `calm-off-then-on.svg` | Calm off with candles chosen: stock spinner; after `/calm`: candles |
| `next-session.svg` | Mid-session edits wait for the next session start (`/clear` reloads neither `config/calm` nor the scene in 2.1.278) |
| `*/analysis.json` | Frame analysis: one-candle-one-gap in every frame, colors, glyph span, scroll transitions, intervals |
| `*/frames.ansi` | Raw timestamped ANSI captures behind every image |
| `live-guard-*.log` | `FM_CLAUDE_CALM_LIVE_E2E=1 tests/fm-calm-claude-mod-live-e2e.test.sh` runs (before and after the test fixes) |
| `default-boat/`, `base-no-preference/` | Debug-log WARN/ERROR lines: an absent optional config file logs `[ERROR] $.fs.read ... ENOENT` at the base commit too |
| `boat-identity.test.ts`, `boat-identity-plugin-test.log` | Temporary `claude plugin test` check (not committed): the default boat's frames and packed Raster cells are byte-identical to base 43bf6d3 |
| `driver/` | The driver, analyzer, and SVG renderers used |

Debug logs were deleted after the WARN/ERROR lines were extracted, because they carry
the full session environment.

## Test round 2: `$.fs.exists` before reading the optional config files

The installed Claude Code 2.1.278 plugin API (`/plugin-types` writes `claude-code.d.ts`)
declares `$.fs.exists(path)`, which "returns whether the path exists; rejects only a
network location". The mod now asks it before reading `config/calm` or
`config/calm-scene`, and the live guard's ENOENT filter is gone.

| Artifact | What it shows |
| --- | --- |
| `live-guard-exists-check-run.log` | Full `FM_CLAUDE_CALM_LIVE_E2E=1 tests/fm-calm-claude-mod-live-e2e.test.sh`: flag-off and candles sections pass, then section 3's "loads with no warning or error" check passes without any ENOENT filter; the run stops later at the known 2.1.278 operational-row step ("Removed 1 invisible character") |
| `exists-no-scene/` | Live, flag on, Calm on, no `config/calm-scene`: boat drawn, 0 ENOENT lines naming the Calm config files, only the benign userConfig notice (compare `default-boat/debug-warn-error.txt`, the target commit's ENOENT) |
| `exists-first-run/` | Live, flag on, neither `config/calm` nor `config/calm-scene`: stock spinner (Calm off), 0 ENOENT lines (compare `base-no-preference/`, base's ENOENT) |
| `candles-dark/` (re-captured) | Candles with the new read path: 80/80 frames one candle one gap, only 256-color 71/204, one-column left scrolls, median 923 ms |
| `plugin-suites-exists-check.log` | `tests/fm-calm-claude-mod-plugin.test.sh`: strict validation and the mod's `claude plugin test` suites pass |
| `driver/exists-check.sh` | The driver for `exists-*` |

Before the fix, a temporary copy of the mod with the old read path failed the updated
suites exactly where expected (`draws the boat when the setting is absent, without a
failed read of the missing file` received `[config/calm, config/calm-scene]`; the
working-notes count received 4, not 2).
