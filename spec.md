# redmine.nvim 명세

> Redmine을 위한 fugitive 스타일 Neovim 플러그인.
> 일감 탐색·상세 보기·코멘트 작성·상태 변경을 nvim 버퍼와 키맵으로 처리한다.

**버전**: 0.1 (draft)

---

## 1. 개요

`redmine.nvim`은 Redmine REST API를 직접 호출하지 않는다. 별도의 CLI(`rm`,
패키지명은 `redmine-core`)에 위임하고, 플러그인은 **얇은 UI 레이어**로서
다음을 책임진다:

- inbox(내 일감 목록), issue(상세), compose(코멘트 작성) 세 가지 버퍼 제공
- 키맵 기반 액션(상태 변경, 담당자 변경, 시간 기록 등)
- 현재 worktree 컨텍스트에서 issue ID 자동 감지
- CLI를 비동기로 호출하고 결과를 버퍼에 그림

플러그인은 인증 토큰, 경로 결정, 데이터 렌더링(JSON↔Markdown), API 호출을
**알지 못한다**. 이 모두 CLI의 책임.

---

## 2. 설계 원칙

1. **얇은 UI 레이어**: API 호출·인증·경로 결정은 CLI에 위임. 플러그인은
   `vim.system`으로 CLI를 호출하고 결과를 그린다.
2. **포터블**: 호스트별 상태/멤버/우선순위는 동적으로 fetch. 하드코딩 없음.
3. **파일 기반 통합**: Claude Code 등 외부 도구와의 상호작용은 합의된 파일
   경로(`.redmine/task.md`, `.redmine/comment-draft.md` 등)를 통해서만.
   경로는 CLI 설정으로 결정되며 플러그인은 경로를 모른다.
4. **명시적 액션**: `:w`는 저장, post는 별도 키. "저장 = 발사" 같은 마법
   금지.
5. **비동기 우선**: 모든 CLI 호출은 비동기. UI 블록 금지.
6. **의존성 최소**: nvim 0.10+ stdlib만으로 동작. telescope/plenary는
   선택 통합.

---

## 3. 아키텍처

```
┌──────────────────────────────────────────────────────────┐
│                      redmine.nvim                         │
│                                                            │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────┐    │
│  │ Commands│  │ Inbox   │  │ Issue    │  │ Compose  │    │
│  │ (:Rm*)  │  │ Buffer  │  │ Buffer   │  │ Buffer   │    │
│  └────┬────┘  └────┬────┘  └─────┬────┘  └─────┬────┘    │
│       │            │             │             │         │
│       └────────────┴─────────────┴─────────────┘         │
│                          │                                │
│                  ┌───────▼────────┐                       │
│                  │  cli.lua       │                       │
│                  │  (vim.system)  │                       │
│                  └───────┬────────┘                       │
└──────────────────────────┼────────────────────────────────┘
                           │
                  ┌────────▼────────┐
                  │   rm CLI        │  ← redmine-core 패키지
                  │   (Python)      │
                  └────────┬────────┘
                           │
                  ┌────────▼─────────────┐
                  │  Redmine REST API    │
                  └──────────────────────┘

         [파일 시스템: .redmine/task.md, .redmine/comment-draft.md 등]
                  ↑                      ↑
                  │                      │
              CLI write              Compose 버퍼 read/write
```

플러그인이 알아야 할 외부 인터페이스는 두 개뿐:
- `rm` CLI 프로세스 호출 (5절)
- `redmine path` 가 알려주는 파일 경로 (8절)

---

## 4. 설치

### 의존성

- **필수**: Neovim 0.10+ (`vim.system`, `vim.json`, `vim.ui.open` 사용)
- **필수**: `rm` CLI가 PATH에 존재하거나 설정에 명시
- **선택**: `nvim-telescope/telescope.nvim` (picker 어댑터, 미구현 시 `vim.ui.select`)

### lazy.nvim 스펙

```lua
{
  'willysk73/redmine.nvim',
  cmd = {
    'Rm', 'Rminbox', 'Rmcomment', 'Rmpost',
    'Rmfetch', 'Rmstatus', 'Rmprogress', 'Rmlog', 'Rmassign',
  },
  keys = {
    { '<leader>ri', '<cmd>Rminbox<cr>',  desc = 'Redmine: inbox' },
    { '<leader>ro', '<cmd>Rm<cr>',       desc = 'Redmine: 현재 일감' },
    { '<leader>rc', '<cmd>Rmcomment<cr>', desc = 'Redmine: 코멘트 작성' },
  },
  opts = {},
}
```

`opts = {}`는 기본 설정 사용. 자세한 옵션은 5절.

---

## 5. 설정

### 기본값 전체

```lua
require('redmine').setup({
  -- CLI 실행 명령. PATH에 있다면 'rm'으로 충분.
  cli = 'rm',

  ----------------------------------------------------------------------
  -- 글로벌 키맵
  ----------------------------------------------------------------------
  keymaps = {
    -- false 또는 nil로 두면 해당 매핑 비활성
    inbox    = '<leader>ri',
    open     = '<leader>ro',
    comment  = '<leader>rc',
    status   = '<leader>rs',
    timelog  = '<leader>rt',
    assign   = '<leader>ra',

    -- 버퍼 로컬 키맵
    inbox_buffer = {
      open    = '<CR>',
      refresh = 'r',
      filter  = 'f',
      search  = '/',
      close   = 'q',
    },
    issue_buffer = {
      comment         = 'cc',
      timelog         = 'tt',
      status          = 'ss',
      progress        = 'pp',
      assign          = 'aa',
      open_attachment = 'oo',
      refresh         = 'r',
      hard_refresh    = 'R',  -- 캐시 무시
      close           = 'q',
    },
    compose_buffer = {
      post            = '<leader>p',
      post_no_confirm = '<leader>P',
      discard         = '<leader>x',
    },
  },

  ----------------------------------------------------------------------
  -- Compose 버퍼 동작
  ----------------------------------------------------------------------
  compose = {
    -- post 시 잘라낼 마커 패턴 (Lua 정규식)
    cutoff_pattern = '^<!%-%-.*━━━.*%-%->%s*$',
    confirm_post   = true,
    -- post 직후 처리: 'archive' | 'delete'
    after_post     = 'archive',
  },

  ----------------------------------------------------------------------
  -- Inbox 버퍼
  ----------------------------------------------------------------------
  inbox = {
    -- 'open' | 'all' | 'mine'
    default_filter = 'open',
    columns        = { 'id', 'tracker', 'status', 'progress', 'subject' },
  },

  ----------------------------------------------------------------------
  -- 버퍼 열기 전략
  ----------------------------------------------------------------------
  ui = {
    -- 'split' | 'vsplit' | 'tab' | 'float' | 'edit'
    open_strategy    = 'split',
    compose_strategy = 'vsplit',
    inbox_strategy   = 'edit',
  },

  ----------------------------------------------------------------------
  -- 알림
  ----------------------------------------------------------------------
  notify = {
    -- 'minimal' | 'verbose'
    level = 'minimal',
  },
})
```

### 사용자 정의 예시

```lua
require('redmine').setup({
  keymaps = {
    inbox = false,           -- 글로벌 inbox 매핑 안 만듦
    issue_buffer = {
      timelog = false,       -- tt 매핑 안 만듦
    },
  },
  ui = {
    open_strategy = 'tab',   -- issue 버퍼를 새 탭으로
  },
})
```

---

## 6. 명령

| 명령 | 인자 | 동작 |
|---|---|---|
| `:Rm` | 없음 | ID 감지 성공 → issue 버퍼; 실패 → inbox |
| `:Rm <id>` | issue ID | 해당 issue 버퍼 강제 |
| `:Rminbox` | 없음 | inbox 강제 |
| `:Rmcomment` | `[<id>]` | compose 버퍼 (id 생략 시 감지) |
| `:Rmpost` | 없음 | 현재 compose 버퍼 post |
| `:Rmfetch` | `[<id>]` | task 파일 갱신 (Claude 등 외부 컨텍스트 용도) |
| `:Rmstatus` | `[<name>]` | 상태 변경 (인자 없으면 picker) |
| `:Rmprogress` | `[<n>]` | 진척률 변경 (0~100, 없으면 prompt) |
| `:Rmlog` | `[<hours>]` | 시간 기록 (없으면 prompt) |
| `:Rmassign` | `[<user>]` | 담당자 변경 (없으면 picker) |

---

## 7. 버퍼 타입

### 7.1 Inbox 버퍼

**filetype**: `redmine-inbox`
**buftype**: `nofile`
**modifiable**: 렌더 후 `false`
**데이터 소스**: `redmine list --json`
**렌더 예시**:

```
Redmine — 내 일감 (3)        [필터: open]

  #1234  새기능   진행중   60%   이메일 검증 함수 추가
  #1240  버그     신규      0%   로그인 토큰 만료 처리
  #1250  태스크   진행중   30%   사내툴 인스톨러 자동화

q close   r refresh   f filter   /  search   <CR> open
```

**키맵 (buffer-local)**:

| 키 | 동작 |
|---|---|
| `<CR>` | 현재 줄의 issue를 issue 버퍼로 |
| `r` | 재 fetch |
| `f` | 필터 토글 (`open` ↔ `all` ↔ `mine`) |
| `/` | nvim 빌트인 검색 |
| `q` | 닫기 |

**구현 노트**:
- 첫 라인은 헤더(타이틀 + 메타). 일감 줄은 들여쓰기 2칸.
- 상태/우선순위는 `vim.api.nvim_buf_set_extmark`로 색 부여.
- 필터 변경은 헤더만 다시 그리고 데이터 라인은 재호출.

---

### 7.2 Issue 버퍼

**filetype**: `redmine-issue`
**buftype**: `nofile`
**modifiable**: `false`
**데이터 소스**: `redmine fetch <id> --format=display`
**폴딩**: 섹션별 (`foldmethod=expr` 또는 `foldmethod=marker`)
**렌더 예시**:

```
#1234 — 이메일 검증 함수 추가

상태  : 진행중       진척 : 60%
담당  : 김아무개     마감 : 2026-05-15
작성  : 김부사장

▾ 본문
  회원가입 폼에 이메일 검증 함수 추가...
▾ 코멘트 (3)
  ─── 김부사장  2026-04-30 14:23 ─────────
    긴급도 상으로 올리고...
  ...
▸ 첨부 (2)
▸ 관련 (1)

cc 코멘트  tt 시간  ss 상태  pp 진척  aa 담당  oo 브라우저
r refresh  R hard refresh  q 닫기
```

**키맵 (buffer-local)**:

| 키 | 동작 | CLI 호출 |
|---|---|---|
| `cc` | compose 버퍼 split | `redmine path draft --id <id>` |
| `tt` | 시간 기록 prompt → 적용 | `redmine log <id> --hours <h>` |
| `ss` | 상태 picker → 적용 | `redmine meta statuses --issue <id>` → `redmine update <id> --status <id>` |
| `pp` | 진척 input → 적용 | `redmine update <id> --progress <n>` |
| `aa` | 담당 picker → 적용 | `redmine meta members --project <id>` → `redmine assign <id> --user <id>` |
| `oo` | 첨부/링크 브라우저 | `vim.ui.open(url)` |
| `r` | refresh (캐시 사용) | `redmine fetch <id>` |
| `R` | hard refresh | `redmine fetch <id> --no-cache` |
| `q` | 닫기 | — |

**구현 노트**:
- `aa`(담당자)는 picker 첫 항목으로 "― 할당 해제 ―" 추가. 선택 시
  `--user ''`로 호출.
- `ss`는 `allowed_statuses`만 노출 (Redmine 워크플로우 규칙 존중).
- 액션 후 자동 refresh.

---

### 7.3 Compose 버퍼

**filetype**: `redmine-compose` (markdown 상속)
**buftype**: 일반 (실제 파일)
**파일 경로**: `redmine path draft --id <id>`로 결정
**`:w` 동작**: 디스크 저장만. post 안 함.
**post**: `<leader>p` 또는 `:Rmpost`

**파일 구조**:

```markdown
---
id: 1234
status:
progress:
time:
---

[사용자 본문]

<!-- ━━━ 아래는 참고용. post 시 무시됨. ━━━ -->

# #1234 — 이메일 검증 함수 추가

**Status**: 진행중  **Progress**: 60%  **Due**: 2026-05-15

## 본문
회원가입 폼에 이메일 검증...

## 이전 코멘트 (3)
**김부사장** — 2026-04-30
> 긴급도 상으로...
...

## 이번 작업 (git log main..HEAD)
- abc1234 feat: 이메일 검증 함수 추가 (refs #1234)
```

**Frontmatter 필드**:

| 키 | 의미 | 비고 |
|---|---|---|
| `id` | issue ID | 필수. post 대상 결정. |
| `status` | 상태 변경 (선택) | 비어있으면 변경 안 함. |
| `progress` | 진척률 (선택) | 0~100. |
| `time` | 시간 기록 (선택) | 단위 시간(h). 음수/0 무시. |

**키맵 (buffer-local)**:

| 키 | 동작 |
|---|---|
| `<leader>p` | post (confirm 후) |
| `<leader>P` | post (confirm 없이) |
| `<leader>x` | 폐기 (파일 삭제 + 버퍼 닫기) |

**Post 흐름**:

```
1. 버퍼 내용 읽기
2. cutoff_pattern 첫 매치 위치에서 truncate
3. Frontmatter 파싱 (YAML)
4. 본문이 비었으면 abort ("빈 코멘트는 post 안 함")
5. confirm 다이얼로그 (compose.confirm_post=true 시):
     "Issue #1234에 다음 코멘트 post:
      ─────
      [본문 첫 5줄]
      ─────
      변경: status=완료, progress=100, time=4.5h
      [y/n]?"
6. CLI 호출:
     redmine post --file <draft_path>
   (CLI가 frontmatter 파싱·comment·status·progress·log_time 처리)
7. 성공:
   - after_post=archive: 같은 디렉토리의 posted/ 로 이동
   - after_post=delete: 파일 삭제
   - 버퍼 닫기, 동일 issue의 issue 버퍼가 떠있으면 자동 refresh
8. 실패: notify ERROR. 파일·버퍼 그대로 유지.
```

**Syntax**:

```vim
" syntax/redmine-compose.vim
runtime! syntax/markdown.vim

syntax match RedmineCutoff /^<!--.*━━━.*-->/
syntax region RedmineContext start=/^<!--.*━━━.*-->/ end=/\%$/ contains=@Spell

hi default link RedmineCutoff Comment
hi default link RedmineContext NonText
```

**구현 노트**:
- 같은 issue에 대한 compose 버퍼가 이미 떠있으면 새 split 대신 그쪽으로
  포커스.
- 파일이 이미 존재 (Claude가 작성)하면 마커 위 영역은 보존, 아래 컨텍스트만
  최신으로 갱신.
- `<leader>x`는 미저장 변경이 있으면 confirm.

---

## 8. CLI 계약

플러그인이 호출하는 `rm` 서브커맨드와 기대 출력.

| 커맨드 | 인자 | stdout | 비고 |
|---|---|---|---|
| `redmine list` | `--json [--filter open]` | issue 배열 | inbox 버퍼용 |
| `redmine fetch <id>` | `--format=display` | 사람용 텍스트 | issue 버퍼 렌더용 |
| `redmine fetch <id>` | `--format=task` | task.md 형식 | `:Rmfetch` 용 |
| `redmine path <kind>` | `--id <id>`, kind=`task|draft|archive` | 절대 경로 1줄 | 경로 결정은 CLI 책임 |
| `redmine detect` | 없음 | issue ID 1줄 또는 빈 출력 | 현재 cwd 기준 |
| `redmine meta statuses` | `[--issue <id>]` | 상태 JSON 배열 | issue 지정 시 allowed만 |
| `redmine meta members` | `--project <id>` | 멤버 JSON 배열 | |
| `redmine meta priorities` | 없음 | 우선순위 JSON 배열 | M3+ |
| `redmine meta trackers` | 없음 | 트래커 JSON 배열 | M3+ |
| `redmine comment <id>` | `--body <text>` | 결과 JSON | 단순 코멘트 |
| `redmine post` | `--file <path>` | 결과 JSON | frontmatter 포함 종합 post |
| `redmine update <id>` | `--status <id>` 등 | 결과 JSON | 부분 업데이트 |
| `redmine assign <id>` | `--user <id>` | 결과 JSON | 빈 user는 할당 해제 |
| `redmine log <id>` | `--hours <h> [--comment <s>]` | 결과 JSON | 시간 기록 |

**JSON 응답 형태 예시** (`redmine list --json`):

```json
[
  {
    "id": 1234,
    "subject": "이메일 검증 함수 추가",
    "tracker": "새기능",
    "status": "진행중",
    "progress": 60,
    "priority": "보통",
    "due_date": "2026-05-15",
    "project": {"id": 5, "name": "core"}
  }
]
```

**에러 처리**:
- 종료 코드 0: 성공
- 0이 아님: stderr를 `vim.notify(level=ERROR)`로 표시
- 인증 실패: 별도 종료 코드(예: 11) → "인증 실패. `redmine auth`로 토큰 확인" 안내

---

## 9. 파일 시스템 계약

플러그인이 직접 읽고 쓰는 파일은 **compose 버퍼의 draft 파일** 하나뿐.

| 파일 | 경로 결정 | 읽기 | 쓰기 |
|---|---|---|---|
| Draft | `redmine path draft --id <id>` | compose 버퍼 열 때 | `:w` 시 디스크 저장 |
| Task | `redmine path task --id <id>` | 안 함 | 안 함 (CLI가 씀) |
| Archive | `redmine path archive --id <id>` | 안 함 | post 후 이동 시만 |

**경로 형식 (CLI 설정 예)**:

```toml
[paths]
task_file   = "{worktree}/.redmine/task.md"
draft_file  = "{worktree}/.redmine/drafts/comment-draft-{id}.md"
archive_dir = "{worktree}/.redmine/posted"
```

플러그인은 `{worktree}` 등의 변수를 직접 해석하지 않는다.

---

## 10. ID 감지

`redmine detect` 호출 결과를 사용. 플러그인 내부 fallback 없음.

```lua
-- lua/redmine/detect.lua
local M = {}

function M.current(callback)
  require('redmine.cli').run({ 'detect' }, {}, function(out)
    local id = tonumber(vim.trim(out))
    callback(id)  -- nil if 실패
  end)
end

return M
```

`:Rm` 명령은 감지 실패 시 자동으로 inbox로 fallback.

---

## 11. 비동기 처리

모든 CLI 호출은 `vim.system`을 통한 비동기.

```lua
-- lua/redmine/cli.lua
local M = {}

function M.run(args, opts, callback)
  local cmd = vim.list_extend(
    { require('redmine.config').get().cli },
    args
  )
  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        vim.notify(
          ('rm %s 실패: %s'):format(args[1], obj.stderr or '(no stderr)'),
          vim.log.levels.ERROR
        )
        return
      end
      callback(obj.stdout)
    end)
  end)
end

function M.run_json(args, callback)
  M.run(vim.list_extend(args, { '--json' }), {}, function(out)
    local ok, data = pcall(vim.json.decode, out)
    if not ok then
      vim.notify('JSON 파싱 실패', vim.log.levels.ERROR)
      return
    end
    callback(data)
  end)
end

return M
```

**로딩 UX**:
- 버퍼 첫 오픈 시 "⏳ Fetching..." 한 줄 그리고 콜백에서 교체.
- 액션(상태 변경 등) 시 statusline 또는 `vim.notify(level=INFO)`로 진행 표시.

---

## 12. 에러 처리 & 알림

| 상황 | 처리 |
|---|---|
| CLI 종료 코드 ≠ 0 | `vim.notify(stderr, ERROR)` |
| 인증 실패 (코드 11) | "인증 실패. `redmine auth` 확인" |
| JSON 파싱 실패 | `vim.notify('JSON 파싱 실패', ERROR)` + raw 출력 보존 |
| 빈 응답 | "데이터 없음" notify |
| 네트워크 타임아웃 | CLI가 처리. 플러그인은 stderr 그대로 표시 |
| ID 감지 실패 (`:Rm`) | 자동으로 inbox로 fallback (notify 안 함) |
| Compose 본문 비어있음 | "빈 코멘트는 post 안 함" notify |

**알림 레벨** (`notify.level`):
- `minimal`: 에러와 액션 결과만 (예: "#1234 → 완료")
- `verbose`: 진행 단계까지 (예: "fetching...", "parsing...")

---

## 13. 디렉토리 구조

```
redmine.nvim/
├── lua/
│   └── redmine/
│       ├── init.lua          -- setup(), 공개 API
│       ├── config.lua        -- 기본값 + merge
│       ├── cli.lua           -- vim.system 래퍼, JSON 파싱
│       ├── commands.lua      -- :Rm* 등록
│       ├── actions.lua       -- :Rmstatus/:Rmprogress/:Rmlog/:Rmassign 액션
│       ├── detect.lua        -- ID 감지 (`redmine detect` 래퍼)
│       ├── frontmatter.lua   -- YAML 파싱 (post 전 분리, Lua 측)
│       ├── health.lua        -- :checkhealth redmine
│       ├── picker.lua        -- vim.ui.select 래퍼
│       ├── ui/
│       │   ├── inbox.lua     -- inbox 버퍼
│       │   ├── issue.lua     -- issue 상세 버퍼
│       │   └── compose.lua   -- compose 버퍼
│       └── util.lua
├── plugin/
│   └── redmine.lua           -- 명령 lazy 등록
├── ftdetect/
│   └── redmine.lua           -- redmine://* + .redmine/drafts/* 패턴
├── syntax/
│   ├── redmine-inbox.vim
│   ├── redmine-issue.vim
│   └── redmine-compose.vim
├── doc/
│   └── redmine.txt
├── tests/
│   ├── minimal.lua           -- 헤드리스 init (E2E용)
│   └── run_e2e.lua           -- Docker stack 대상 E2E
├── test-stack/
│   ├── docker-compose.yml    -- Redmine 5.1 + Postgres 16 (port 13080)
│   └── seed.rb               -- idempotent seeder (admin token, demo project, fixtures, sample.txt 첨부)
├── CHANGELOG.md
├── LICENSE
├── README.md
└── spec.md
```

---

## 14. 공개 API

```lua
-- 설정
require('redmine').setup(opts)

-- 프로그램 진입
require('redmine').open_inbox()
require('redmine').open_issue(id)
require('redmine').compose(id)

-- 유틸
require('redmine').current_issue_id(callback)  -- async, callback(id|nil)
```

내부 모듈(`require('redmine.cli')` 등)은 비공개. 변경될 수 있음.

---

## 15. 구현 마일스톤

### M1 — 최소 사용 가능 (1~2일)

목표: inbox로 일감 찾고 issue 본문 읽기

- `setup()` + config merge
- `:Rm`, `:Rminbox` 명령
- inbox 버퍼 (읽기 전용, `<CR>`/`q`)
- issue 버퍼 (읽기 전용, `q`)
- 비동기 CLI 래퍼
- ID 감지 (`redmine detect`)
- 기본 syntax

### M2 — 코멘트 워크플로우 (2~3일)

목표: post까지 닫힘

- compose 버퍼 (`:Rmcomment`)
- frontmatter 파서
- `<leader>p` post 동작 (cutoff strip → CLI `redmine post`)
- `<leader>x` 폐기
- compose syntax (cutoff 디밍)
- `:Rmstatus` (picker, allowed_statuses 사용)
- `:Rmprogress`, `:Rmlog`, `:Rmassign`
- issue 버퍼 키맵 `cc`, `tt`, `ss`, `pp`, `aa`

### M3 — 폴리싱 (1~2일)

- inbox 필터/검색 (`f`, `/`)
- issue 폴딩
- 첨부 브라우저 열기 (`oo`)
- hard refresh (`R`)
- `:checkhealth redmine`
- 에러 메시지 정리

### M4 — 선택사항

- telescope 어댑터
- `:RmRecent` (최근 본 issue 히스토리)
- inbox 가상 컬럼/정렬
- 대량 액션 (다중 일감 상태 일괄 변경)

---

## 16. 테스트 전략

### Unit (plenary busted-style)

- `frontmatter.lua`: YAML 파싱·시리얼라이즈
- `compose.lua` strip 함수: cutoff 패턴 다양한 케이스
- `config.lua`: 사용자 옵션 merge

### Integration

- Mock `rm` 스크립트 (고정 JSON 반환)로 PATH override
- 헤드리스 nvim에서 명령 실행 후 버퍼 내용 검증

```bash
# tests/run.sh
PATH="$PWD/tests/mock-bin:$PATH" \
  nvim --headless -u tests/minimal.lua \
       -c "PlenaryBustedDirectory tests {minimal_init = 'tests/minimal.lua'}"
```

### E2E (선택)

실제 Redmine 인스턴스 (회사용 staging) 연동 테스트는 환경 변수
`REDMINE_TEST_URL`, `REDMINE_TEST_TOKEN` 있을 때만.

---

## 부록 A — 전체 키맵 표

| 컨텍스트 | 키 | 동작 |
|---|---|---|
| 글로벌 | `<leader>ri` | inbox |
| 글로벌 | `<leader>ro` | 현재 일감 (감지 → issue, 실패 → inbox) |
| 글로벌 | `<leader>rc` | 코멘트 작성 |
| 글로벌 | `<leader>rs` | 상태 변경 |
| 글로벌 | `<leader>rt` | 시간 기록 |
| 글로벌 | `<leader>ra` | 담당자 변경 |
| Inbox | `<CR>` | 현재 줄 issue 열기 |
| Inbox | `r` | refresh |
| Inbox | `f` | 필터 토글 |
| Inbox | `/` | 검색 |
| Inbox | `q` | 닫기 |
| Issue | `cc` | 코멘트 작성 |
| Issue | `tt` | 시간 기록 |
| Issue | `ss` | 상태 변경 |
| Issue | `pp` | 진척률 변경 |
| Issue | `aa` | 담당자 변경 |
| Issue | `oo` | 커서 라인의 첨부 다운로드 후 OS 핸들러로 열기 (xdg-open / open / start) |
| Issue | `r` | refresh |
| Issue | `R` | hard refresh |
| Issue | `q` | 닫기 |
| Compose | `<leader>p` | post (confirm) |
| Compose | `<leader>P` | post (no confirm) |
| Compose | `<leader>x` | 폐기 |

---

## 부록 B — 의존하는 CLI 인터페이스 요약

플러그인이 작동하려면 `redmine` CLI(`redmine-core` 패키지, `redmine-core >= 0.1.1`)가 다음을 충족해야 한다:

1. **`redmine --version`** — `redmine-core <semver>` 1줄 (`:checkhealth` 가 사용)
2. **`redmine whoami`** — 현재 사용자 1줄. 인증 검증용
3. **`redmine detect`** — cwd 기준 issue ID stdout 1줄, 없으면 빈 출력 + 종료 코드 1
4. **`redmine path <kind> --id <id>`** — kind=`draft|task|archive`, 절대 경로 1줄
5. **`redmine list --json [--filter <f>]`** — issue 배열 JSON
6. **`redmine fetch <id> --format=<display|task|json>`** — 텍스트 / task.md / 원본 JSON
7. **`redmine meta statuses [--issue <id>] --json`** — `[{id, name, is_closed}]`
8. **`redmine meta members --project <id> --json`** — `[{id, name}]`
9. **`redmine post --file <path>`** — frontmatter 파일 받아 종합 처리 (단일 PUT, 단일 journal)
10. **`redmine update <id> --status|--progress <v>`** — 부분 업데이트
11. **`redmine assign <id> --user <id>`** — 빈 user 또는 `none`은 해제
12. **`redmine log <id> --hours <h> [--activity <id>] [--comment <s>]`** — 시간 기록
13. **`redmine suggest assignee --id <id>`** — 직전 댓글 작성자, 없으면 일감 작성자 (compose buffer assignee 기본값)
14. **`redmine attachment download --id <attachment_id> [--issue <issue_id>] [--out <path>] [--force]`** — 첨부 다운로드 후 절대 경로 출력 (idempotent — 이미 있으면 재다운 안 함)

각 명령의 `--json` 옵션은 stdout을 머신 파서블 JSON으로 출력한다.
인증 실패 시 종료 코드 11.

---
