" Inbox highlighting. Minimal so we don't fight user colorschemes.
if exists('b:current_syntax') | finish | endif

syntax match RedmineInboxHeader  /\%1l.*/
syntax match RedmineInboxFooter  /\%$.*/
syntax match RedmineInboxId      /#\d\+/                   contained
syntax match RedmineInboxPercent /\d\+%/                   contained
syntax match RedmineInboxRow     /^\s\{2,\}#\d.*$/         contains=RedmineInboxId,RedmineInboxPercent

hi default link RedmineInboxHeader  Title
hi default link RedmineInboxFooter  Comment
hi default link RedmineInboxId      Identifier
hi default link RedmineInboxPercent Number

let b:current_syntax = 'redmine-inbox'
