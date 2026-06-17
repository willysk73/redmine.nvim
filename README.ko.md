# redmine.nvim

[English](README.md) · [한국어](README.ko.md)

Neovim용 fugitive 스타일 Redmine UI. [`redmine-core`](#cli-의존성)
CLI 위에 얹은 얇은 래퍼.

- Inbox + 읽기 전용 issue 버퍼 (fugitive 스타일)
- Pending posts 버퍼 — `.redmine/drafts/`의 미전송 초안을
  fugitive 스타일 listing으로 노출; 일괄 post / discard 가능
- frontmatter 기반 compose 버퍼 — 코멘트 + 상태 + 진척률 + 담당자 +
  시간 기록을 **하나의** PUT (post 한 번 = journal 1개)으로 묶음;
  선택적으로 Reference section이 허용 status + assignee 후보 노출
- picker 기반 단발 명령 (`:Rmstatus`, `:Rmassign`, …)
- issue 버퍼 folding (본문 / 코멘트 / 첨부) + 인메모리 캐시
- 첨부 파일 OS 핸들러 열기 (`oo` → `xdg-open` / `open` / `start`)
- `:checkhealth redmine` — 환경 변수 / CLI / 인증 진단

## 요구사항

- Neovim 0.10+
- `$PATH` 위의 [`redmine-core`](https://github.com/willysk73/redmine-core)
  (플러그인이 shell out 함)

## 설치

lazy.nvim:

```lua
{
  'willysk73/redmine.nvim',
  cmd  = { 'Rm', 'Rminbox', 'Rmcomment', 'Rmpost',
           'Rmstatus', 'Rmprogress', 'Rmlog', 'Rmassign', 'Rmfetch' },
  keys = {
    { '<leader>ri', '<cmd>Rminbox<cr>', desc = 'Redmine: inbox' },
    { '<leader>ro', '<cmd>Rm<cr>',      desc = 'Redmine: 현재 일감' },
  },
  opts = {},
}
```

설치 후 `:checkhealth redmine` 실행 — CLI가 `$PATH`에 있는지, 환경
변수가 placeholder가 아닌지, `whoami`가 성공하는지 검증.

## CLI 의존성

```bash
uv tool install redmine-core    # 권장 (격리, 가장 빠름)
# 또는
pipx install redmine-core
# 또는
pip install --user redmine-core
```

환경 변수 또는 `~/.config/redmine-core/config.toml`로 설정:

```bash
export REDMINE_URL=https://redmine.example.com
export REDMINE_API_KEY=<your-api-key>
redmine whoami    # 연결 확인
```

## 명령어

| 명령                          | 동작                                                                  |
|-------------------------------|-----------------------------------------------------------------------|
| `:Rm`                         | cwd/branch 기반 issue 감지 → issue 버퍼; id 추출 실패 시 **pending posts** 버퍼 |
| `:Rm <id>`                    | 해당 issue 열기                                                        |
| `:Rminbox`                    | inbox 열기 (`inbox.default_filter` 적용, 기본 `open`)                  |
| `:Rminbox <filter>`           | 필터 지정해서 inbox 열기 — `open` / `all` / `mine`. 잘못된 값 → ERROR notify, 버퍼 안 열림. `<Tab>` 자동완성 지원. |
| `:Rmcomment [<id>]`           | compose 버퍼 열기 (담당자 자동 추천)                                   |
| `:Rmpost`                     | compose 버퍼에선 현재 초안 post. pending 버퍼에선 listing 전체 post.   |
| `:Rmpost <id>`                | `<id>`의 초안 파일을 안 열고 직접 post (초안 없으면 에러)              |
| `:Rmpost all`                 | drafts 디렉토리의 모든 초안 post (pending의 `P`와 동일 루프)           |
| `:Rmstatus [<id>] [<name>]`   | 상태 변경 (인자 없으면 picker)                                         |
| `:Rmprogress [<id>] [<n>]`    | 진척률 변경                                                            |
| `:Rmlog [<id>] [<h>]`         | 시간 기록                                                              |
| `:Rmassign [<id>] [<user>]`   | 담당자 변경                                                            |
| `:Rmfetch [<id>]`             | task.md 갱신                                                           |

## 버퍼 키맵

- **Inbox**: `<CR>` 열기 · `r` 새로고침 · `f` 필터 picker (`open` / `all` / `mine` / cancel) · `q` 닫기
- **Issue**: `r` 새로고침 (캐시 적중 시 캐시 사용) · `R` hard refresh (캐시 우회) ·
  `q` 닫기 · `cc` 코멘트 · `tt` 시간 기록 · `ss` 상태 · `pp` 진척률 · `aa` 담당자 ·
  `oo` 커서 위 첨부 파일 열기
- **Pending**: `<CR>` 커서 위 초안을 compose 버퍼로 열기 · `p` 한 개 post ·
  `P` 전부 post · `d` 폐기 · `r` 새로고침 · `q` 닫기 · `i` inbox 으로 이동.
  기본값은 `keymaps.pending_buffer` 아래에서 override 가능.
- **Compose**: `<leader>p` post (확인) · `<leader>P` post (확인 없이) ·
  `<leader>x` 폐기

### Issue 버퍼 folding

본문 · 코멘트 · 첨부가 fold section (`foldmethod=expr`). 첨부는
**기본 닫힘**, 본문/코멘트는 열림. 표준 fold 키 사용: `zc` / `zo`로
한 section 닫기/열기, `zM`으로 전체 닫기, `zR`로 전체 열기.

### 캐시와 hard refresh

플러그인은 issue id + `REDMINE_URL` / `REDMINE_API_KEY` 해시로 키된
인메모리 캐시를 유지. `r`은 fresh일 때 캐시된 버퍼를 반환. `R`
(hard refresh)는 generation 카운터를 올리고 캐시를 우회한 뒤
fresh 결과를 다시 써넣음. 웹 UI나 다른 클라이언트로 외부에서 수정한
뒤 stale data가 아닌지 확실히 하고 싶을 때 `R` 사용.

## Pending posts 버퍼

`.redmine/drafts/`는 아직 post 안 된 compose 초안을 보관 (`:Rmcomment`로
생성, 성공 시 `.redmine/posted/`로 archive). 인자 없는 `:Rm`이 cwd/branch
에서도 issue id를 못 찾으면 `redmine://pending`이 열림 — 그 초안들의
읽기 전용 listing, mtime 기준 최신순 정렬, 한 항목당 frontmatter
change-summary + 본문 미리보기 + 줄 수 + mtime:

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

버퍼 없이 쓸 일이 있다면 `:Rmpost <id>` / `:Rmpost all`이 같은 일을
해줌 (tmux scratch 창, 배치 스크립트 같은 데서 유용).

## Compose 초안

`:Rmcomment <id>`는 frontmatter가 있는 markdown 초안을 엶:

```markdown
---
id: 123
status:                            # 비우면 변경 없음
assignee: Alice                    # 마지막 코멘터로 자동 입력
---


<!-- 커서가 여기 위치; 코멘트 작성 -->


<!-- ━━━ 아래는 참고용. post 시 무시됨. ━━━ -->
(이슈 컨텍스트 — render된 task; post 시 무시됨)
```

frontmatter 변경만 있는 (예: 상태만 바꾸는) 빈 본문도 허용. 단일
PUT가 모든 필드 변경 + 코멘트를 묶기 때문에, 몇 개 필드를 바꾸든
journal 항목은 정확히 **하나**만 생성됨.

### Reference section

cutoff line 아래에 scaffold가 이 이슈의 가능한 status, progress
가이드, assignee 후보 (작성자 + 최근 journal 참여자)를 보여주는
**Reference** section을 덧붙임. 읽기 전용 — `redmine post --file`은
cutoff 아래를 무시함. M4 이전의 가벼운 scaffold를 선호하면 `setup()`
에서 `compose = { reference_section = false }`로 끄면 됨.

## Spec

전체 설계는 [spec.md](spec.md) 참고 (M1~M4).

## 라이선스

MIT — [LICENSE](LICENSE) 참고.
