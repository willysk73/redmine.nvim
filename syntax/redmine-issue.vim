if exists('b:current_syntax') | finish | endif

syntax match RedmineIssueHeader  /\%1l.*/
syntax match RedmineIssueSection /^▾.*/
syntax match RedmineIssueFolded  /^▸.*/
syntax match RedmineIssueId      /#\d\+/
syntax match RedmineIssueField   /^\(상태\|담당\|트래커\|작성\)\s*:/
syntax match RedmineIssueDivider /^\s*───.*───\s*$/

hi default link RedmineIssueHeader  Title
hi default link RedmineIssueSection Statement
hi default link RedmineIssueFolded  Comment
hi default link RedmineIssueId      Identifier
hi default link RedmineIssueField   Type
hi default link RedmineIssueDivider Comment

let b:current_syntax = 'redmine-issue'
