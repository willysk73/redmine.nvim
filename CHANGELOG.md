# Changelog

All notable changes to `redmine.nvim` are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This plugin tracks the [`redmine-core`](https://github.com/willysk73/redmine-core)
CLI as its backend; minimum CLI version is checked by `:checkhealth redmine`.

## [Unreleased]

### Changed
- Drafts/posted layout moved from `{worktree}/.claude/` to
  `{worktree}/.redmine/{drafts,posted}/`. Compose archive resolution
  follows the new layout.
- `:checkhealth redmine` requires `redmine-core >= 0.1.1`. 0.1.0 was yanked
  from PyPI because it shipped the old `.claude/` default.
- Documentation refresh: README install (`uv tool install` recommended),
  spec.md updated to match shipped behavior (CLI binary `redmine`, not
  the planning-stage placeholder `rm`; `.redmine/` paths; new CLI
  contract surface — `whoami`, `attachment download`, `suggest assignee`,
  `--version`).

### Added
- `:checkhealth redmine` — diagnoses CLI presence/version, env-var
  placeholders (`redmine.example.com` / `your-api-key-here`), and
  `whoami` connectivity.
- Issue buffer `oo` keymap — downloads the attachment under the cursor
  via `redmine attachment download` and opens it with the OS handler
  (`xdg-open` on Linux, `open` on macOS, `start` on Windows) detached.
- Compose buffer accepts empty body when frontmatter has changes
  (status-only / assignee-only updates).
- `ftdetect` pattern recognizes `{worktree}/.redmine/drafts/comment-draft-*.md`
  for users opening drafts via `:e`/sessions.

### Fixed
- `util.open_buffer`: virtual buffers (`redmine://inbox`, `redmine://issue/N`)
  now disable swapfile + set `buftype=nofile` *before* `nvim_buf_set_name`,
  so a stale swap from a crashed nvim no longer triggers E325 ATTENTION.

## [M2] - 2026-05-08

### Added
- Compose buffer + `:Rmpost`. Single PUT bundles `notes` + `status_id`
  + `done_ratio` + `assigned_to_id` → exactly one journal entry per
  post regardless of how many fields change. Time entry posts as a
  separate `POST /time_entries.json` when `time:` is set.
- Picker-based action wrappers: `:Rmstatus`, `:Rmprogress`, `:Rmlog`,
  `:Rmassign` (vim.ui.select / vim.ui.input). Same actions also bound
  to issue-buffer keymaps `cc/ss/pp/aa/tt`.
- Compose `assignee:` defaults to the last commenter (falls back to
  the issue author).
- Confirm prompt before post (`<leader>p`); `<leader>P` skips it.

## [M1] - 2026-05-07

### Added
- `setup()` / config merge / async CLI wrapper.
- `:Rm`, `:Rm <id>`, `:Rminbox`. ID detection from branch / `.redmine`
  / cwd via `redmine detect`.
- Read-only inbox + issue buffers (`redmine://inbox`, `redmine://issue/N`).
- Inbox keymaps: `<CR>` open, `r` refresh, `f` filter cycle
  (open/all/mine), `/` builtin search, `q` close.
- E2E suite (`tests/run_e2e.lua`) driven against the bundled Docker
  Redmine stack (`test-stack/`).
