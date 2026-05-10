-- Filetype detection by buffer name. Buffers we create in code already set
-- filetype directly; this file is a safety net for users who load the buffer
-- name through other means (sessions, etc.).
vim.filetype.add({
  pattern = {
    ['redmine://inbox.*']  = 'redmine-inbox',
    ['redmine://issue/.*'] = 'redmine-issue',
    -- Compose drafts live in $WORKTREE/.claude/comment-draft-*.md by default.
    ['.*/%.claude/comment%-draft.*%.md'] = 'redmine-compose',
  },
})
