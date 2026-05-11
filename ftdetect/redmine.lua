-- Filetype detection by buffer name. Buffers we create in code already set
-- filetype directly; this file is a safety net for users who load the buffer
-- name through other means (sessions, etc.).
vim.filetype.add({
  pattern = {
    ['redmine://inbox.*']  = 'redmine-inbox',
    ['redmine://issue/.*'] = 'redmine-issue',
    -- Compose drafts: filename-only pattern so this fallback works
    -- regardless of where the user (or `[paths] draft_file` in
    -- redmine-core's config) actually puts them — default
    -- `.redmine/drafts/`, legacy `.claude/`, or any other directory
    -- via session restore / `:e`. compose.lua sets the filetype
    -- explicitly on first open; this is just for everything that
    -- bypasses that path.
    ['.*comment%-draft.*%.md'] = 'redmine-compose',
  },
})
