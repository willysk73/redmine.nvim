# redmine.nvim

Fugitive-style Redmine UI for Neovim. Thin wrapper over the [`redmine-core`](#cli-dependency) CLI.

> Status: M1 + M2 done — read-only inbox & issue detail, compose/post round-trip, status/progress/timelog/assign actions. M3 (filter/search polish, folding, attachments, `:checkhealth`) is next.

## Install

lazy.nvim:

```lua
{
  'will/redmine.nvim',
  cmd  = { 'Rm', 'Rminbox' },
  keys = {
    { '<leader>ri', '<cmd>Rminbox<cr>', desc = 'Redmine: inbox' },
    { '<leader>ro', '<cmd>Rm<cr>',      desc = 'Redmine: 현재 일감' },
  },
  opts = {},
}
```

## CLI dependency

The plugin shells out to a CLI named `redmine` (package: `redmine-core`).
The CLI handles auth, paths, and JSON ↔ display rendering.

```bash
pip install --user -e /path/to/redmine-core
export REDMINE_URL=https://redmine.example.com
export REDMINE_API_KEY=...
redmine whoami      # connectivity check
```

Or use `~/.config/redmine-core/config.toml`:

```toml
url = "https://redmine.example.com"
api_key = "deadbeef..."
```

## Commands

| 명령 | 동작 |
|---|---|
| `:Rm` | cwd 기준 issue 감지 → issue 버퍼; 실패 시 inbox |
| `:Rm <id>` | 해당 issue 강제 |
| `:Rminbox` | inbox 강제 |
| `:Rmcomment [<id>]` | 코멘트 작성 (compose 버퍼) |
| `:Rmpost` | 현재 compose 버퍼 post |
| `:Rmstatus [<id>] [<name>]` | 상태 변경 (인자 없으면 picker) |
| `:Rmprogress [<id>] [<n>]` | 진척률 변경 |
| `:Rmlog [<id>] [<h>]` | 시간 기록 |
| `:Rmassign [<id>] [<user>]` | 담당자 변경 |
| `:Rmfetch [<id>]` | task.md 갱신 |

## Buffer keymaps

- **Inbox**: `<CR>` open · `r` refresh · `f` filter · `q` close
- **Issue**: `r` refresh · `R` hard refresh · `q` close · `cc` comment · `tt` timelog · `ss` status · `pp` progress · `aa` assign · `oo` attachments (M3)
- **Compose**: `<leader>p` post · `<leader>P` post (no confirm) · `<leader>x` discard

## Spec

See [spec.md](spec.md) for the full design (M1~M4).
