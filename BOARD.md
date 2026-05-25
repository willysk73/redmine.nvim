# redmine.nvim — supervisor BOARD

## Direction

**Current milestone: M4 (spec §15 — 선택사항).** M1+M2+M3 shipped on
`main`. M4 tightens the compose-and-post workflow in two independent
ways: making the compose scaffold **discoverable** (status / progress /
assignee hints inside the buffer), and surfacing the existing
`.redmine/drafts/` staging area as a **first-class buffer** so the
plugin behaves more like fugitive (`:Rm` ≈ `:Git`).

Constraints workers should respect:

- **Plugin-only changes.** No `redmine-core` subcommand additions or
  breaking flag changes. CLI is still `0.1.1`. If a task seems to need
  new CLI surface, surface it as a `chat_ask` instead of inventing one.
- **CLAUDE.md rules apply.** Minimum code, surgical edits, no
  speculative features. Don't refactor adjacent code.
- **E2E must stay green** (`tests/run_e2e.lua` against the Docker
  stack at `test-stack/`, currently **45/45**). Each task adds tests
  for its own surface; existing tests must not regress.
- **`Setup` shape unchanged.** `config.lua` defaults may grow new
  keys (e.g. `compose.reference_section`, `keymaps.pending_buffer.*`)
  but must remain backwards-compatible with users who set up with
  M2-era config tables.

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

- id: T-4
  title: "Compose scaffold reference — status options + progress hint + assignee candidates"
  scope:
    include:
      - lua/redmine/ui/compose.lua
      - lua/redmine/cli.lua
      - lua/redmine/config.lua
      - tests/run_e2e.lua
    exclude: []
  status: assigned
  priority: high
  depends_on: []
  brief: .ccx/tasks/T-4.md
  attempts: 1
  worktree: /home/will/Repositories/redmine.nvim-T-4
  branch: ccx/T-4
  worker_pid: null
  started_at: "2026-05-25T08:32:44Z"
  finished_at: null
  exit_status: null
  notes: |

- id: T-5
  title: "Pending posts buffer + :Rm fallback + :Rmpost extensions"
  scope:
    include:
      - lua/redmine/ui/pending.lua
      - lua/redmine/commands.lua
      - lua/redmine/config.lua
      - tests/run_e2e.lua
    exclude: []
  status: pending
  priority: high
  depends_on: []
  brief: .ccx/tasks/T-5.md
  attempts: 0
  worktree: null
  branch: null
  worker_pid: null
  started_at: null
  finished_at: null
  exit_status: null
  notes: |
```
