# redmine.nvim

[English](README.md) · [한국어](README.ko.md)

Neovim용 fugitive 스타일 Redmine UI. [`redmine-core`](#cli-의존성)
CLI 위에 얹은 얇은 래퍼.

- Inbox + 읽기 전용 issue 버퍼 (fugitive 스타일)
- frontmatter 기반 compose 버퍼 — 코멘트 + 상태 + 진척률 + 담당자 +
  시간 기록을 **하나의** PUT (post 한 번 = journal 1개)으로 묶음
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
| `:Rm`                         | cwd/branch 기반 issue 감지 → issue 버퍼; 실패 시 inbox                 |
| `:Rm <id>`                    | 해당 issue 열기                                                        |
| `:Rminbox`                    | inbox 열기 (`inbox.default_filter` 적용, 기본 `open`)                  |
| `:Rminbox <filter>`           | 필터 지정해서 inbox 열기 — `open` / `closed` / `all` / `mine`. 잘못된 값 → ERROR notify, 버퍼 안 열림. `<Tab>` 자동완성 지원. |
| `:Rmcomment [<id>]`           | compose 버퍼 열기 (담당자 자동 추천)                                   |
| `:Rmpost`                     | 현재 compose 버퍼 post (single-PUT, single-journal)                    |
| `:Rmstatus [<id>] [<name>]`   | 상태 변경 (인자 없으면 picker)                                         |
| `:Rmprogress [<id>] [<n>]`    | 진척률 변경                                                            |
| `:Rmlog [<id>] [<h>]`         | 시간 기록                                                              |
| `:Rmassign [<id>] [<user>]`   | 담당자 변경                                                            |
| `:Rmfetch [<id>]`             | task.md 갱신                                                           |

## 버퍼 키맵

- **Inbox**: `<CR>` 열기 · `r` 새로고침 · `f` 필터 picker (`open` / `closed` / `all` / `mine` / cancel) · `q` 닫기
- **Issue**: `r` 새로고침 (캐시 적중 시 캐시 사용) · `R` hard refresh (캐시 우회) ·
  `q` 닫기 · `cc` 코멘트 · `tt` 시간 기록 · `ss` 상태 · `pp` 진척률 · `aa` 담당자 ·
  `oo` 커서 위 첨부 파일 열기
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

## Spec

전체 설계는 [spec.md](spec.md) 참고 (M1~M4).

## 라이선스

MIT — [LICENSE](LICENSE) 참고.
