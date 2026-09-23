# HaneulKeyboard 릴리스 체크리스트

> **기준일:** 2026-09-23 (#72) · GitHub Release를 올릴 때마다 이 순서를 따른다. 규칙의 근거는 줄번호 대신 **코드 심볼**로 적었다 — 그 심볼이 바뀌면 이 문서도 같이 고친다.

## 왜 이 문서가 있나

2026-09-21(#19)부터 앱이 스스로 새 버전을 찾는다. 앱은 GitHub에 **"최신 릴리스가 뭐냐"만** 묻고, 답이 정해진 형식이 아니면 에러 없이 **"업데이트 없음"으로 처리**한다. 그래서 릴리스를 한 번 잘못 올리면 아무 경고도 없이 **모든 사용자에게 업데이트 알림이 사라진다.** 아래 규칙이 그 형식이다.

## 1. 반드시 지킬 규칙

근거는 전부 [`Sources/UpdateDecisions.swift`](../Sources/UpdateDecisions.swift)의 `UpdateDecision`·`CalVer`다.

| 규칙 | 어기면 | 근거 |
|---|---|---|
| **태그 = `MARKETING_VERSION` 그대로** (예: `2026.09`). `v2026.09`·`HaneulKeyboard 2026.09` 금지 | 버전을 못 읽음 → 업데이트 없음 | `CalVer.init?` — 숫자와 점만, 2~3칸 |
| **에셋 = 빌드 스크립트가 만든 `HaneulKeyboard_<태그>.zip` 그대로** (이름 변경 금지) | 받을 파일을 못 찾음 → 업데이트 없음 | `assetName(forTag:)`·`selectAsset(in:)` — 정확 일치 |
| **정식 릴리스**(draft·pre-release 아님)로 올리고 "Latest"로 둔다 | 앱이 보는 `/releases/latest`에 안 나옴 | `latestReleaseURL(repository:)`·`parseRelease(_:)` |
| **버전은 직전 릴리스보다 커야** 한다(같으면 안 됨) | 같은 번호 재게시는 업데이트로 안 잡힘 | `availableUpdate(currentVersion:release:)` — `current < latest` |
| **빌드 번호(`CURRENT_PROJECT_VERSION`)도 커야** 한다 | 내려받은 뒤 설치 단계에서 거부 | `isVersionIncrease(...)` — CalVer **와** 빌드 번호 둘 다 |
| 에셋은 **GitHub 릴리스에 직접 첨부**(외부 링크 금지) | 허용 호스트 밖이라 거부 | `allowedHosts` |
| 에셋 크기 200MB 이하 | 거부 | `maxAssetBytes` |
| Developer ID 서명(Team은 `signingTeamIdentifier`) + 애플 공증 | 설치 단계에서 거부, 기존 앱 유지 | `codesignRequirement`(애플 앵커 + Team) · `spctl -a -t exec` |

### 버전 번호 고르는 법

- CalVer `연도.릴리스[.핫픽스]`(README "버전 체계"). 두 번째 칸은 그해 몇 번째 릴리스인지다(월이 아님).
- **내부 확인용 빌드에 쓴 번호는 릴리스에 다시 쓰지 않는다.** 내부 빌드를 설치한 Mac은 그 번호를 "현재 버전"으로 갖고 있어서, 같은 번호의 릴리스를 업데이트로 보지 않는다. 예) `2026.08`은 내부 빌드 50·51이 썼으므로 다음 릴리스는 `2026.09` 이상이어야 한다.
- **이미 올린 릴리스를 고칠 때는 에셋을 바꿔치기하지 말고 핫픽스 칸을 올린다**(`2026.09` → `2026.09.01`). 에셋만 교체하면 이미 업데이트한 사람은 번호가 같아서 수정본을 영영 못 받는다.

## 2. 순서

### ① 준비

- [ ] 릴리스에 넣을 PR이 전부 main에 머지됐다.
- [ ] `git switch main && git pull` 뒤 `git status`가 깨끗하고, `git rev-parse HEAD`가 `git rev-parse origin/main`과 같다. — 빌드 스크립트는 작업 트리를 검사하지 않는다. 여기서 확인하지 않으면 태그가 가리키는 커밋과 실제로 빌드한 코드가 달라질 수 있다.
- [ ] `bash scripts/run_ime_tests.sh` 출력이 ` 0 failed`로 끝난다.

### ② 버전 올리기

- [ ] `project.yml`의 `MARKETING_VERSION`(위 규칙대로)과 `CURRENT_PROJECT_VERSION`(+1)을 올려 커밋하고 push한다.

### ③ 빌드·서명·공증

- [ ] `ZIP_ONLY=1 scripts/build_notarize_install.sh HaneulKeyboard` — 결과물은 repo 루트의 `HaneulKeyboard_<MARKETING_VERSION>.zip`이다. 스크립트가 서명·공증·staple·Gatekeeper·zip 내용(유니버설·LICENSE 동봉)까지 검사하고, 끝에 빌드 산출물의 LaunchServices 등록을 지운다.
- [ ] ⚠️ 같은 버전으로 다시 돌리면 **기존 zip을 지우고** 새로 만든다. 옛 zip이 필요하면 먼저 이름을 바꿔 둔다(`.gitignore`의 `/HaneulKeyboard_*.zip`이 커밋을 막아 준다).
- 타겟은 항상 `HaneulKeyboard`(메인 앱)다. IME 단독 zip은 배포물이 아니다(스크립트가 막는다).

### ④ 설치·실기기 확인

- [ ] 기존 설치본을 앱의 **설정 → 고급 → 전체 제거...** 로 지운다.
- [ ] `ditto -x -k HaneulKeyboard_<버전>.zip /Applications/` — **sudo 없이.** 앱이 사용자 소유여야 자동 업데이트가 관리자 암호 없이 교체한다(`UpdateDecision.replaceStrategy` — 사용자 소유면 원자적 교체, root 소유면 관리자 암호 창). `ls -ld /Applications/HaneulKeyboard.app`으로 소유자를 확인한다.
- [ ] 앱 실행 → **설정 → 일반 → 입력기 설치** → 시스템 설정에서 입력 소스 추가.
- [ ] `bash scripts/postinstall_probe.sh` 전 항목 ✓.
- [ ] [`docs/manual-test-checklist.md`](./manual-test-checklist.md)에서 이번 릴리스에 걸린 절을 확인한다.

### ⑤ 릴리스 노트

- [ ] 직전 릴리스 이후 머지된 PR·닫힌 티켓으로 초안을 쓴다(`git log <직전 태그>..HEAD --merges --oneline`). 형식은 직전 릴리스 본문을 따른다: 요약 한 줄 → 지원 OS → 기능별 절 → 설치 → 개인정보 한 줄.
- [ ] 개인정보 문구는 [`PRIVACY.md`](../PRIVACY.md) 2·9번과 맞춘다. 2026.07 노트의 "네트워크 전송·저장 없음"은 이제 틀린 문장이다 — 업데이트 확인이 GitHub에 접속한다(보내는 데이터는 없고, 끌 수 있다).

### ⑥ 게시 — 🔴 오너가 직접

```bash
V=2026.09   # MARKETING_VERSION과 같은 값
gh release create "$V" "HaneulKeyboard_$V.zip" \
  --target "$(git rev-parse HEAD)" --title "$V" --notes-file <노트 파일> --latest
```

- `--target`에는 **빌드한 커밋**을 준다(①에서 확인한 HEAD). `--target main`은 그사이 main이 움직이면 다른 커밋에 태그를 단다.
- `--draft`·`--prerelease`를 붙이지 않는다.

### ⑦ 게시 직후 확인

- [ ] 앱이 보는 그대로 확인한다:

  ```bash
  curl -s https://api.github.com/repos/Hyunjin-Cho/HaneulKeyboard/releases/latest \
    | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r["tag_name"], [a["name"] for a in r["assets"]])'
  ```

  태그가 새 버전이고, 에셋 목록에 `HaneulKeyboard_<태그>.zip`이 **정확히** 있어야 한다.
- [ ] **자동 업데이트 실전 확인** — 직전 버전(업데이터가 들어 있는 빌드)을 설치한 Mac에서 설정 → 업데이트 → `지금 확인` → 새 버전이 뜨는지 → `업데이트` → 재실행 뒤 앱 버전이 바뀌고 IME도 새 빌드로 갱신됐는지(`bash scripts/postinstall_probe.sh` 1번).
- [ ] 이상하면 **릴리스를 지우지 말고** 원인부터 본다. 지우고 다시 올리면 이미 받은 사람과 번호가 꼬인다.

### ⑧ 홍보 — 🔴 오너

- 2026.07 이하 사용자는 업데이터가 없는 버전이라 **이번 한 번은 직접 받아야** 한다. 그들에게 닿는 통로는 홍보뿐이다.

## 하지 말 것

- 태그에 `v` 붙이기 · zip 이름 바꾸기 · pre-release/draft로 올리기
- 게시된 릴리스의 에셋 바꿔치기 — 고치려면 핫픽스 번호로 새 릴리스
- 내부 빌드에 쓴 버전 번호로 릴리스하기
- 빌드한 커밋과 다른 커밋에 태그 달기
