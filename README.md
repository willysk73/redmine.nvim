# redmine.nvim

[English](README.md) · [한국어](README.ko.md)

Fugitive-style Redmine UI for Neovim. Thin wrapper over the
[`redmine-core`](#cli-dependency) CLI.

- Inbox + read-only issue buffer (fugitive-style)
- Compose buffer with frontmatter — bundles comment + status + progress
  + assignee + time into **one** PUT (one journal entry per post)
- Picker-based one-shot wrappers (`:Rmstatus`, `:Rmassign`, …)
- Issue buffer folding (body / comments / attachments) + in-memory cache
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
    { '<leader>ro', '<cmd>Rm<cr>',      desc = 'Redmine: current issue' },
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

| Command                         | Behavior                                                              |
|---------------------------------|-----------------------------------------------------------------------|
| `:Rm`                           | Detect issue from cwd/branch → issue buffer; falls back to inbox      |
| `:Rm <id>`                      | Open the given issue                                                  |
| `:Rminbox`                      | Open inbox (uses `inbox.default_filter`, default `open`)              |
| `:Rminbox <filter>`             | Open inbox with explicit filter — `open` / `closed` / `all` / `mine`. Invalid value → ERROR notify, no buffer. `<Tab>` completion supported. |
| `:Rmcomment [<id>]`             | Open compose buffer (assignee auto-suggested)                         |
| `:Rmpost`                       | Post the current compose buffer (single PUT, single journal)          |
| `:Rmstatus [<id>] [<name>]`     | Change status (no args → picker)                                      |
| `:Rmprogress [<id>] [<n>]`      | Change progress percent                                               |
| `:Rmlog [<id>] [<h>]`           | Log time                                                              |
| `:Rmassign [<id>] [<user>]`     | Change assignee                                                       |
| `:Rmfetch [<id>]`               | Refresh `task.md`                                                     |

## Buffer keymaps

- **Inbox**: `<CR>` open · `r` refresh · `f` filter picker (`open` / `closed` / `all` / `mine` / cancel) · `q` close
- **Issue**: `r` refresh (cache hit if fresh) · `R` hard refresh (bypass cache) · `q` close ·
  `cc` comment · `tt` timelog · `ss` status · `pp` progress · `aa` assign ·
  `oo` open attachment under cursor
- **Compose**: `<leader>p` post (confirm) · `<leader>P` post (no confirm) ·
  `<leader>x` discard

### Issue buffer folding

Body, comments, and attachments are foldable sections (`foldmethod=expr`).
Attachments are **closed by default**; body and comments are open. Use
the standard fold keys: `zc` / `zo` to close / open one section,
`zM` to close all, `zR` to open all.

### Cache and hard refresh

The plugin keeps an in-memory cache keyed by issue id + a hash of
`REDMINE_URL` / `REDMINE_API_KEY`. `r` returns the cached buffer when
it's still fresh; `R` (hard refresh) bumps the generation counter,
bypasses the cache, and writes the fresh result back. Use `R` after
out-of-band edits (web UI, another client) when you need to be sure
you're not looking at stale data.

## Compose draft

`:Rmcomment <id>` opens a markdown draft with frontmatter:

```markdown
---
id: 123
status:                            # blank = no change
assignee: Alice                    # pre-filled with last commenter
---


<!-- caret lands here; type your comment -->


<!-- ━━━ Below is reference only. Ignored on post. ━━━ -->
(issue context — rendered task; ignored on post)
```

Empty body with only frontmatter changes (e.g. status-only) is allowed.
A single PUT bundles all field changes plus the comment, so you get
exactly **one** journal entry no matter how many fields you change.

## Spec

See [spec.md](spec.md) for the full design (M1~M4).

## License

MIT — see [LICENSE](LICENSE).
