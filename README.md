# redmine.nvim

[English](README.md) · [한국어](README.ko.md)

Fugitive-style Redmine UI for Neovim. Thin wrapper over the
[`redmine-core`](#cli-dependency) CLI.

- Inbox + read-only issue buffer (fugitive-style)
- Pending posts buffer — staged drafts under `.redmine/drafts/` as a
  first-class listing; bulk-post / discard with one keystroke
- Compose buffer with frontmatter — bundles comment + status + progress
  + assignee + time into **one** PUT (one journal entry per post);
  optional Reference section shows allowed statuses + assignee candidates
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
| `:Rm`                           | Detect issue from cwd/branch → issue buffer; falls back to **pending posts** buffer when no id can be inferred |
| `:Rm <id>`                      | Open the given issue                                                  |
| `:Rminbox`                      | Open inbox (uses `inbox.default_filter`, default `open`)              |
| `:Rminbox <filter>`             | Open inbox with explicit filter — `open` / `all` / `mine`. Invalid value → ERROR notify, no buffer. `<Tab>` completion supported. |
| `:Rmcomment [<id>]`             | Open compose buffer (assignee auto-suggested)                         |
| `:Rmpost`                       | From a compose buffer: post current draft. From the pending buffer: post every listed draft. |
| `:Rmpost <id>`                  | Post the draft file for `<id>` without opening it (errors if no draft exists) |
| `:Rmpost all`                   | Post every draft in the drafts dir (same loop as `P` from pending)    |
| `:Rmstatus [<id>] [<name>]`     | Change status (no args → picker)                                      |
| `:Rmprogress [<id>] [<n>]`      | Change progress percent                                               |
| `:Rmlog [<id>] [<h>]`           | Log time                                                              |
| `:Rmassign [<id>] [<user>]`     | Change assignee                                                       |
| `:Rmfetch [<id>]`               | Refresh `task.md`                                                     |

## Buffer keymaps

- **Inbox**: `<CR>` open · `r` refresh · `f` filter picker (`open` / `all` / `mine` / cancel) · `q` close
- **Issue**: `r` refresh (cache hit if fresh) · `R` hard refresh (bypass cache) · `q` close ·
  `cc` comment · `tt` timelog · `ss` status · `pp` progress · `aa` assign ·
  `oo` open attachment under cursor
- **Pending**: `<CR>` open draft in compose · `p` post one · `P` post all · `d` discard ·
  `r` refresh · `q` close · `i` jump to inbox. Defaults configurable
  under `keymaps.pending_buffer`.
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

## Pending posts buffer

`.redmine/drafts/` holds compose drafts that haven't been posted yet
(written by `:Rmcomment`, archived to `.redmine/posted/` on success).
`:Rm` with no arg and no detectable issue id opens `redmine://pending`,
a read-only listing of those drafts sorted newest-first — one block
per draft showing the frontmatter change-summary, body preview, line
count, and mtime:

```
Pending Redmine posts — /path/to/cwd/.redmine/drafts  (2)

#42 — status: Resolved, progress: 100, assignee: Alice           14m ago
   draft.md (8 lines)
   "Fixed by reverting commit abc123 and re-running migration."

#7  — status: (no change)                                         3d ago
   draft.md (12 lines)
   "Added unit tests for the edge case discovered in QA."

p post · P post all · d discard · r refresh · q close · i inbox
```

`:Rmpost <id>` and `:Rmpost all` are the no-buffer-needed variants —
useful from a tmux scratch window or scripted batch.

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

### Reference section

Below the post-cutoff line the scaffold also appends a **Reference**
section with this issue's allowed statuses, a progress hint, and
assignee candidates (issue author + recent journal participants).
The reference is read-only — `redmine post --file` ignores everything
below the cutoff. Turn it off with `compose = { reference_section = false }`
in `setup()` if you prefer the leaner pre-M4 scaffold.

## Spec

See [spec.md](spec.md) for the full design (M1~M4).

## License

MIT — see [LICENSE](LICENSE).
