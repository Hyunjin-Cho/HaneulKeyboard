# HaneulKeyboard 릴리스 체크리스트

> **기준일:** 2026-10-10 (#85, 기존 #72) · 정식 버전은 실제 배포 날짜 `YYYY.MM.DD`를 사용한다. 규칙의 근거는 줄번호 대신 **코드 심볼**로 적었다 — 그 심볼이 바뀌면 이 문서도 같이 고친다.

## 왜 이 문서가 있나

앱은 GitHub의 최신 릴리스 정보를 정해진 규칙으로 읽는다. 잘못된 버전·자산·응답은 오류 또는 설치 불가 상태가 되므로, 게시 전에 아래 규칙과 실제 업데이트 경로를 함께 확인한다. 현재 로컬 준비 상태는 [빌드 68 기록](releases/2026.9-build68-preparation.md)에 있다.

## 1. 반드시 지킬 규칙

근거는 전부 [`Sources/UpdateDecisions.swift`](../Sources/UpdateDecisions.swift)의 `UpdateDecision`·`CalVer`다.

| 규칙 | 어기면 | 근거 |
|---|---|---|
| **태그 = `MARKETING_VERSION` 그대로** (예: `2026.10.10`). `v` 접두어·정식 태그의 `-beta` 접미어 금지 | 버전을 못 읽음 → 업데이트 없음 | `CalVer.init?` — 이전 설치본 호환을 위해 숫자와 점 2~3칸 허용 |
| **에셋 = 빌드 스크립트가 만든 `HaneulKeyboard_<태그>.zip` 그대로** (이름 변경 금지) | 받을 파일을 못 찾음 → 업데이트 없음 | `assetName(forTag:)`·`selectAsset(in:)` — 정확 일치 |
| **정식 릴리스**(draft·pre-release 아님)로 올리고 "Latest"로 둔다 | 앱이 보는 `/releases/latest`에 안 나옴 | `latestReleaseURL(repository:)`·`parseRelease(_:)` |
| **버전은 직전 릴리스보다 커야** 한다(같으면 안 됨) | 같은 번호 재게시는 업데이트로 안 잡힘 | `availableUpdate(currentVersion:release:)` — `current < latest` |
| **빌드 번호(`CURRENT_PROJECT_VERSION`)도 커야** 한다 | 내려받은 뒤 설치 단계에서 거부 | `isVersionIncrease(...)` — CalVer **와** 빌드 번호 둘 다 |
| 에셋은 **GitHub 릴리스에 직접 첨부**(외부 링크 금지) | 허용 호스트 밖이라 거부 | `allowedHosts` |
| ZIP 200 MiB 이하 / 릴리스 JSON 2 MiB 이하 | 수신 도중 중단·부분 ZIP 정리 | `maxAssetBytes`·`maxReleaseMetadataBytes`·`UpdateTransport` |
| Developer ID 서명(Team은 `signingTeamIdentifier`) + 애플 공증 | 설치 단계에서 거부, 기존 앱 유지 | `codesignRequirement`(애플 앵커 + Team) · `spctl -a -t exec` |

### 버전 번호 고르는 법

- **정식은 `연도.월.일`**이다. 실제 2026년 10월 10일에 게시하는 경우 `2026.10.10`을 쓴다. 날짜는 예시이며 첫 정식 출시일은 아직 확정하지 않았다.
- 과거 `2026.01`~`2026.07`은 순번형 베타 이력이다. 기존 두 칸짜리 내부 설치본과 비교하기 위해 `CalVer`는 2~3칸 파싱을 유지한다. 날짜 유효성을 검사하는 타입은 아니므로 게시자가 실제 날짜를 확인한다.
- **내부 확인용 빌드에 쓴 번호는 정식에 그대로 재사용하지 않는다.** 현재 버전은 `project.yml`, 설치본 버전은 `postinstall_probe.sh`로 읽고 새 번호가 더 큰지 확인한다. 예: `2026.9` → `2026.10.10`은 상승이다.
- **이미 올린 날짜·같은 버전의 에셋을 바꿔치기하지 않는다.** 빌드 번호만 높여도 현재 업데이터는 업데이트로 보지 않는다. 같은 날 두 번째 정식 배포가 필요하면 번호 정책·업데이터 대응을 먼저 합의한다. 임의로 네 번째 칸이나 접미어를 붙이지 않는다.
- 전환 검사는 `Tests/ComposerTests.swift`의 날짜 버전 검사(이전 번호→날짜, 일/월/연도 경계, 파일명 일치, 같은 날짜 재게시 거부)에 있다.

## 2. 순서

### ① 준비

- [ ] 릴리스에 넣을 PR이 전부 main에 머지됐다.
- [ ] `git switch main && git pull` 뒤 `git status`가 깨끗하고, `git rev-parse HEAD`가 `git rev-parse origin/main`과 같다. — 빌드 스크립트는 작업 트리를 검사하지 않는다. 여기서 확인하지 않으면 태그가 가리키는 커밋과 실제로 빌드한 코드가 달라질 수 있다.
- [ ] GitHub CI가 활성화됐고 대상 PR의 **현재 커밋**에서 성공했다. 활성화만으로 이전 커밋 검사가 자동 실행되지는 않는다.
- [ ] `python3 scripts/audit_phonetic_dictionary.py` 통과.
- [ ] `bash scripts/run_ime_tests.sh` 출력이 ` 0 failed`로 끝난다.
- [ ] `bash scripts/run_updater_tests.sh`, 안내 입력을 변경했다면 `bash scripts/run_onboarding_tests.sh`도 통과한다.

### ② 버전 올리기

- [ ] `project.yml`의 `MARKETING_VERSION`(위 규칙대로)과 `CURRENT_PROJECT_VERSION`(+1)을 올려 커밋하고 push한다.
- [ ] **커밋·푸시·머지·태그는 먼저 사용자 승인을 받는다.** 이전 테스트 후보의 버전을 미래 날짜로 미리 바꾸지 않는다.

### ③ 빌드·서명·공증

- [ ] Apple로 앱을 전송하는 공증과 실제 설치는 해당 단계의 승인을 확인한 뒤 수행한다. 현재 2·3·5 작업 범위에는 포함하지 않는다.

- [ ] `ZIP_ONLY=1 scripts/build_notarize_install.sh HaneulKeyboard` — 결과물은 repo 루트의 `HaneulKeyboard_<MARKETING_VERSION>.zip`이다. 스크립트가 서명·공증·staple·Gatekeeper·zip 내용(유니버설·메인 앱/내장 IME의 LICENSE·NOTICE·감사의 글·과거 MIT 원문 동봉)까지 검사하고, 끝에 빌드 산출물의 LaunchServices 등록을 지운다.
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
RELEASE_VERSION=2026.10.10   # 예시: 실제 배포 날짜이자 MARKETING_VERSION과 같은 값
gh release create "$RELEASE_VERSION" "HaneulKeyboard_$RELEASE_VERSION.zip" \
  --target "$(git rev-parse HEAD)" --title "$RELEASE_VERSION" --notes-file <노트 파일> --latest
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
- 게시된 정식 버전의 에셋 바꿔치기 — 새 버전 정책을 충족하는 번호로 게시
- 내부 빌드에 쓴 버전 번호로 릴리스하기
- 빌드한 커밋과 다른 커밋에 태그 달기
