# redmine.nvim — supervisor BOARD

## Direction

**Current milestone: M3 polish.** M1 + M2 are shipped; the plugin and
its sibling CLI (`redmine-core 0.1.1`) live on PyPI / GitHub. This
milestone tightens UX in three independent areas — inbox filtering,
issue-buffer folding, and a cache layer for `r` vs `R`.

Constraints workers should respect:

- **Plugin-only changes.** No CLI subcommand additions or breaking
  changes to existing CLI flags. If a task seems to need new CLI
  surface, surface it as a `chat_ask` instead of inventing one.
- **CLAUDE.md rules apply.** Minimum code, surgical edits, no
  speculative features. Don't refactor adjacent code.
- **E2E must stay green** (`tests/run_e2e.lua` against the Docker
  stack at `test-stack/`, currently 33/33). Each task adds tests
  for its own surface; existing tests should not regress.
- **`Setup` shape unchanged.** `config.lua` defaults may grow new
  keys but must remain backwards-compatible with users who set up
  with M2-era config tables.

Integration branch: `main`. Worktrees fork from current `HEAD` per
ccx convention.

## Tasks

```yaml
- id: T-1
  title: "Inbox filter polish — :Rminbox <filter> arg + picker"
  scope:
    include:
      - lua/redmine/ui/inbox.lua
      - lua/redmine/commands.lua
      - tests/run_e2e.lua
    exclude: []
  status: merged
  priority: high
  depends_on: []
  brief: .ccx/tasks/T-1.md
  attempts: 1
  worktree: /home/will/Repositories/redmine.nvim-T-1
  branch: ccx/T-1
  worker_pid: null
  started_at: "2026-05-11T14:02:08Z"
  finished_at: "2026-05-11T14:10:52Z"
  exit_status: approved
  notes: |

- id: T-2
  title: "Issue buffer folding — body / comments / attachments sections"
  scope:
    include:
      - lua/redmine/ui/issue.lua
      - syntax/redmine-issue.vim
      - tests/run_e2e.lua
    exclude: []
  status: merged
  priority: high
  depends_on: []
  brief: .ccx/tasks/T-2.md
  attempts: 1
  worktree: /home/will/Repositories/redmine.nvim-T-2
  branch: ccx/T-2
  worker_pid: null
  started_at: "2026-05-14T12:32:28Z"
  finished_at: "2026-05-14T13:05:57Z"
  exit_status: approved
  notes: |

- id: T-3
  title: "CLI cache layer + R hard-refresh wiring"
  scope:
    include:
      - lua/redmine/cli.lua
      - lua/redmine/ui/inbox.lua
      - lua/redmine/ui/issue.lua
      - lua/redmine/config.lua
      - tests/run_e2e.lua
    exclude: []
  status: merged
  priority: normal
  depends_on: [T-1, T-2]
  brief: .ccx/tasks/T-3.md
  attempts: 1
  worktree: /home/will/Repositories/redmine.nvim-T-3
  branch: ccx/T-3
  worker_pid: null
  started_at: "2026-05-14T13:06:32Z"
  finished_at: "2026-05-14T13:45:23Z"
  exit_status: approved
  notes: |
```
