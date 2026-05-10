# redmine.nvim

Fugitive-style Redmine UI for Neovim. Thin wrapper over the
[`redmine-core`](#cli-dependency) CLI.

- Inbox + read-only issue buffer (fugitive-style)
- Compose buffer with frontmatter — bundles comment + status + progress
  + assignee + time into **one** PUT (one journal entry per post)
- Picker-based one-shot wrappers (`:Rmstatus`, `:Rmassign`, …)
- Attachment open via OS handler (`oo` → `xdg-open` / `open` / `start`)
- `:checkhealth redmine` for env / CLI / auth diagnostics

## Requirements

- Neovim 0.10+
- [`redmine-core`](https://github.com/willysk73/redmine-core) on `$PATH`
  (the plugin shells out to it)

## Install

lazy.nvim:

```lua
{
  'willysk73/redmine.nvim',
  cmd  = { 'Rm', 'Rminbox', 'Rmcomment', 'Rmpost',
           'Rmstatus', 'Rmprogress', 'Rmlog', 'Rmassign', 'Rmfetch' },
  keys = {
    { '<leader>ri', '<cmd>Rminbox<cr>', desc = 'Redmine: inbox' },
    { '<leader>ro', '<cmd>Rm<cr>',      desc = 'Redmine: 현재 일감' },
  },
  opts = {},
}
```

Run `:checkhealth redmine` after install — it verifies the CLI is on
`$PATH`, that env vars aren't placeholders, and that `whoami` succeeds.

## CLI dependency

```bash
uv tool install redmine-core    # recommended (isolated, fastest)
# or
pipx install redmine-core
# or
pip install --user redmine-core
```

Configure via env or `~/.config/redmine-core/config.toml`:

```bash
export REDMINE_URL=https://redmine.example.com
export REDMINE_API_KEY=<your-api-key>
redmine whoami    # connectivity check
```

## Commands

| 명령                          | 동작                                                         |
|-------------------------------|--------------------------------------------------------------|
| `:Rm`                         | cwd/branch 기반 issue 감지 → issue 버퍼; 실패 시 inbox        |
| `:Rm <id>`                    | 해당 issue 열기                                              |
| `:Rminbox`                    | inbox 열기                                                   |
| `:Rmcomment [<id>]`           | compose 버퍼 열기 (assignee 자동 추천)                        |
| `:Rmpost`                     | 현재 compose 버퍼 post (single-PUT, single-journal)           |
| `:Rmstatus [<id>] [<name>]`   | 상태 변경 (인자 없으면 picker)                                |
| `:Rmprogress [<id>] [<n>]`    | 진척률 변경                                                  |
| `:Rmlog [<id>] [<h>]`         | 시간 기록                                                    |
| `:Rmassign [<id>] [<user>]`   | 담당자 변경                                                  |
| `:Rmfetch [<id>]`             | task.md 갱신                                                 |

## Buffer keymaps

- **Inbox**: `<CR>` open · `r` refresh · `f` filter · `q` close
- **Issue**: `r` refresh · `R` hard refresh · `q` close · `cc` comment ·
  `tt` timelog · `ss` status · `pp` progress · `aa` assign ·
  `oo` open attachment under cursor
- **Compose**: `<leader>p` post (confirm) · `<leader>P` post (no confirm) ·
  `<leader>x` discard

## Compose draft

`:Rmcomment <id>` opens a markdown draft with frontmatter:

```markdown
---
id: 123
status:                            # blank = no change
assignee: Alice                    # pre-filled with last commenter
---


<!-- caret lands here; type your comment -->


<!-- ━━━ 아래는 참고용. post 시 무시됨. ━━━ -->
(이슈 컨텍스트 — render된 task; post 시 무시됨)
```

Empty body with only frontmatter changes (e.g. status-only) is allowed.
A single PUT bundles all field changes plus the comment, so you get
exactly **one** journal entry no matter how many fields you change.

## Spec

See [spec.md](spec.md) for the full design (M1~M4).

## License

MIT — see [LICENSE](LICENSE).
