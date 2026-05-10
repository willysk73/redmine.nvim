" redmine-compose: markdown + dimmed cutoff + frontmatter highlight
if exists('b:current_syntax') | finish | endif

" Re-use markdown's syntax under us.
runtime! syntax/markdown.vim
unlet! b:current_syntax

syntax match RedmineCompFmDelim /^---$/
syntax region RedmineCompFm     start=/\%^---$/ end=/^---$/ keepend contains=RedmineCompFmKey,RedmineCompFmDelim
syntax match RedmineCompFmKey   /^\(id\|status\|progress\|time\|assignee\):/ contained

syntax match RedmineCompCutoff  /^<!--.*━━━.*-->$/
syntax region RedmineCompContext start=/^<!--.*━━━.*-->$/ end=/\%$/ contains=@Spell

hi default link RedmineCompFmDelim Comment
hi default link RedmineCompFmKey   Identifier
hi default link RedmineCompCutoff  Comment
hi default link RedmineCompContext NonText

let b:current_syntax = 'redmine-compose'
