# HaneulKeyboard 릴리스 체크리스트

> **기준일:** 2026-10-14 (#85, 기존 #72) · 정식 버전은 실제 배포 날짜 `YYYY.MM.DD`를 사용한다. 규칙의 근거는 줄번호 대신 **코드 심볼**로 적었다 — 그 심볼이 바뀌면 이 문서도 같이 고친다.

## 왜 이 문서가 있나

앱은 GitHub의 최신 릴리스 정보를 정해진 규칙으로 읽는다. 잘못된 버전·자산·응답은 오류 또는 설치 불가 상태가 되므로, 게시 전에 아래 규칙과 실제 업데이트 경로를 함께 확인한다. 현재 후보는 [세션 인계](HANDOFF_2026-10-11_session-recovery.md)와 [남은 작업](remaining-work-2026-10-14.md)에서 확인한다. [빌드 68 기록](releases/2026.9-build68-preparation.md)은 당시 검증 근거로 보존한다.

**2026-10-14 승인 상태:** 로컬 구현·격리 검사는 진행 가능하다. Apple 공증 전송·실제 설치는 사용자가 계속 보류했고, Git 커밋·푸시·머지·태그·게시 승인은 없다. 아래 체크박스는 실행 승인이나 현재 통과 표시가 아니다. 공증을 재개하기 전에는 `PACKAGE_ONLY`·`CANDIDATE_ONLY`도 실행하지 않는다. 두 모드 모두 설치는 생략하지만 공증 파이프라인을 실행하기 때문이다.

## 1. 반드시 지킬 규칙

근거는 전부 [`Sources/UpdateDecisions.swift`](../Sources/UpdateDecisions.swift)의 `UpdateDecision`·`CalVer`다.

| 규칙 | 어기면 | 근거 |
|---|---|---|
| **태그 = 공개 버전** (`MARKETING_VERSION` + `HANEUL_RELEASE_SUFFIX`). 기본판 `2026.10.15`, 핫픽스 `2026.10.15_hotfix`. `v`·`-beta` 금지 | 버전을 못 읽음 → 업데이트 없음 | `CalVer.init?`·`releaseVersion(info:)` |
| **에셋 = 빌드 스크립트가 만든 `HaneulKeyboard_<태그>.zip` 그대로** (이름 변경 금지) | 받을 파일을 못 찾음 → 업데이트 없음 | `assetName(forTag:)`·`selectAsset(in:)` — 정확 일치 |
| **첫 설치 에셋 = `HaneulKeyboard_<태그>.dmg`**, 같은 버전 ZIP도 함께 게시 | DMG만 있으면 앱 안 업데이트 없음 | `scripts/package_dmg.sh`; `selectAsset(in:)` |
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
- **핫픽스는 `_hotfix`만 붙인다**(2026-10-10 사용자 결정). Apple 표준 `CFBundleShortVersionString`은 숫자 날짜로 유지하며, `project.yml`의 `HANEUL_RELEASE_SUFFIX`를 `_hotfix`로 설정해 서명된 `HaneulReleaseSuffix`에 저장한다. `UpdateDecision.releaseVersion(info:)`가 화면·업데이트 비교에 쓸 공개 버전을 만든다. 기본판은 접미어가 빈 문자열이다. 근거: [Apple 버전 형식](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring).
- 같은 날짜 기본판 → 핫픽스 → 다음 날짜 순으로 업데이트한다. **이미 올린 같은 버전의 에셋을 바꿔치기하지 않는다.** 빌드 번호만 높여도 업데이트로 보지 않는다. **하루 기본판1개와 같은 날 핫픽스1개까지**(2026-10-10 사용자 확정). 같은 날 두 번째 기본판/핫픽스는 배포하지 않고 `_hotfix2`도 지원하지 않는다.
- 전환 검사는 `Tests/ComposerTests.swift`의 날짜 버전 검사(이전 번호→날짜, 일/월/연도 경계, 파일명 일치, 같은 날짜 재게시 거부)에 있다.

## 2. 순서

### ① 준비

- [ ] 릴리스에 넣을 PR이 전부 main에 머지됐다.
- [ ] `git switch main && git pull` 뒤 `git status`가 깨끗하고, `git rev-parse HEAD`가 `git rev-parse origin/main`과 같다. — 빌드 스크립트는 작업 트리를 검사하지 않는다. 여기서 확인하지 않으면 태그가 가리키는 커밋과 실제로 빌드한 코드가 달라질 수 있다.
- [ ] GitHub CI가 활성화됐고 대상 PR의 **현재 커밋**에서 성공했다. 활성화만으로 이전 커밋 검사가 자동 실행되지는 않는다.
- [ ] `python3 scripts/audit_phonetic_dictionary.py` 통과.
- [ ] `bash scripts/run_ime_tests.sh` 출력이 ` 0 failed`로 끝난다.
- [ ] `bash scripts/run_input_inference_tests.sh` 통과. 외부 영어 문맥과 정확 복합어의 기본 ON·설정 OFF·한글/개인 사전 보호·미등록 오타 보존을 확인한다(#14/#24/#7).
- [ ] `python3 Tests/run_vocabulary_extension_tests.py` 통과. 사전 확장 출처·실제 입력 도달·한국어 보호를 확인하고 `audit_wordlist.sh`에서 제품 기본 복합어 ON과 `--compound off` 비교를 구분해 남긴다(#16/#17/#74/#77).
- [ ] `bash scripts/run_input_source_indicator_tests.sh` 통과. 별도 안내/Palette는 실제 Caps Lock·외부 앱 포커스·전체화면·멀티모니터·설정OFF도 확인한다(#81).
- [ ] `bash scripts/run_slash_tests.sh` 통과. 기본 ON·설정 OFF·일반 Space 복귀·입력칸 이동은 설치본에서도 확인한다(#87).
- [ ] `bash scripts/run_updater_tests.sh`, 안내 입력을 변경했다면 `bash scripts/run_onboarding_tests.sh`도 통과한다.
- [ ] `python3 scripts/test_postinstall_probe.py` 통과 — 실제 TIS 집계 블록의 enabled/disabled/없음/중복을 확인한다(2026-10-11 리뷰 F-2). 이 검사는 실제 설치 상태의 통과를 뜻하지 않는다.
- [ ] `python3 scripts/test_uninstall.py` 통과 — Swift 공통 코드를 사용하는 CLI 진입점의 실패 전파를 확인한다. 실제 제품 순서의 실패/취소/재생성 시 데이터 보존, 실제 임시 파일·설정 검사는 `run_updater_tests.sh`에서 Debug/Release 모두 통과해야 한다(2026-10-11 승인 B안).
- [ ] README·설정·수동 검사 항목이 현재 코드와 맞는다. 설정의 자동 변환/단축키 변환 분류, 기본 ON/OFF, 7단계 안내, 철자 오류 보존을 확인한다. 로컬 검사와 최신 설치본 실기를 구분해 기록한다.

### ② 버전 올리기

- [ ] `project.yml`의 `MARKETING_VERSION`(날짜), `HANEUL_RELEASE_SUFFIX`(기본 빈 문자열 / 핫픽스 `_hotfix`), `CURRENT_PROJECT_VERSION`(+1)을 확인한다. 공개 태그·ZIP 이름에는 접미어를 포함한다.
- [ ] **커밋·푸시·머지·태그는 먼저 사용자 승인을 받는다.** 이전 테스트 후보의 버전을 미래 날짜로 미리 바꾸지 않는다.

### ③ 빌드·서명·공증

- [ ] Apple로 앱을 전송하는 공증과 실제 설치는 사용자가 보류를 해제한 뒤 수행한다. 로컬 검토 ZIP에는 `NOT-NOTARIZED`를 표시하고 설치용 DMG와 구분한다.

- [ ] `python3 -m venv .tools/dmg` 후 `.tools/dmg/bin/python -m pip install -r scripts/requirements-dmg.txt`로 포장 도구 준비. `PACKAGE_ONLY=1 bash scripts/build_notarize_install.sh HaneulKeyboard`로 첫 설치용 `HaneulKeyboard_<공개 버전>.dmg`와 업데이트용 `.zip`·각 `.sha256`을 만든다. 앱/DMG는 따로 서명·공증·staple·Gatekeeper, DMG는 원본 앱/배경/위치 대조, ZIP는 추출본 고지/서명 검사를 거친다. 설치는 하지 않는다. `ZIP_ONLY=1`은 호환 이름이다.
- [ ] **기존 같은 공개 이름 파일은 덮어쓰지 않는다.** 공증된 설치 테스트 후보는 `CANDIDATE_ONLY=1 bash scripts/build_notarize_install.sh HaneulKeyboard`로 `.build/candidates/<버전>-b<빌드>/`에 DMG·ZIP·체크섬을 만든다. 별도 DerivedData를 쓰고 설치는 건너뛴다. 정식 게시용은 `PACKAGE_ONLY=1`로 루트에 만든다. 무서명 화면 검사만 필요할 때는 `.tmp/`의 별도 preview 이름을 사용한다.
- 타겟은 항상 `HaneulKeyboard`(메인 앱)다. IME 단독 zip은 배포물이 아니다(스크립트가 막는다).

### ④ 설치·실기기 확인

- [ ] 기존 설치본을 앱의 **설정 → 앱 관리 → 하늘키보드 전체 제거…** 로 지운다.
- [ ] DMG를 더블클릭해 설치 화면에서 메인 앱을 Applications로 드래그한다. 복사 후 응용 프로그램 폴더의 앱을 실행하고 DMG를 꺼낸다. 사용자 소유 앱은 자동 업데이트를 암호 없이 교체하고 root 소유면 관리자 암호 창이 뜬다(`UpdateDecision.replaceStrategy`). `ls -ld /Applications/HaneulKeyboard.app`으로 소유자를 확인한다.
- [ ] 앱 실행 → **설정 → 앱 관리 → 입력기 설치** → 시스템 설정에서 입력 소스 추가.
- [ ] `bash scripts/postinstall_probe.sh` 전 항목 ✓, 마지막 집계 ✗ 0, 종료코드 0. 입력 소스 disabled/없음/중복이면 실패로 집계한다.
- [ ] B안의 설치 → 입력기만 제거 → 재설치 → 전체 제거 → 재설치, 실패 시 재시도·Finder 자동 정리·업데이트 중복 방지 실기 기록을 남긴다. 이 검증 전에는 #90/#86을 닫지 않는다.
- [ ] [`docs/manual-test-checklist.md`](./manual-test-checklist.md)의 활성 절에서 이번 릴리스에 걸린 검사를 확인한다. 맨 아래 과거 후보별 기록의 빌드·디자인을 현재 합격 기준으로 사용하지 않는다.

### ⑤ 릴리스 노트

- [ ] 직전 릴리스 이후 머지된 PR·닫힌 티켓으로 초안을 쓴다(`git log <직전 태그>..HEAD --merges --oneline`). 형식은 직전 릴리스 본문을 따른다: 요약 한 줄 → 지원 OS → 기능별 절 → 설치 → 개인정보 한 줄.
- 로컬 준비 초안: [`upcoming-release-draft-2026-10-14.md`](releases/upcoming-release-draft-2026-10-14.md). 미커밋 후보를 근거로 작성했으므로 실제 설치 검증·머지·공개 날짜 확정 뒤 최종 릴리스와 다시 대조한다.
- [ ] 개인정보 문구는 [`PRIVACY.md`](../PRIVACY.md) 2·9번과 맞춘다. 2026.07 노트의 "네트워크 전송·저장 없음"은 이제 틀린 문장이다 — 업데이트 확인이 GitHub에 접속한다(보내는 데이터는 없고, 끌 수 있다).

### ⑥ 게시 — 🔴 오너가 직접

```bash
RELEASE_VERSION=2026.10.10   # 예시: 실제 배포 날짜이자 MARKETING_VERSION과 같은 값
gh release create "$RELEASE_VERSION" "HaneulKeyboard_$RELEASE_VERSION.dmg" "HaneulKeyboard_$RELEASE_VERSION.dmg.sha256" \
  "HaneulKeyboard_$RELEASE_VERSION.zip" "HaneulKeyboard_$RELEASE_VERSION.zip.sha256" \
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

  태그가 새 버전이고 `HaneulKeyboard_<태그>.dmg`·`.zip`·각 체크섬이 정확히 있어야 한다. 같은 날짜 기본판/핫픽스가 이미 있으면 재게시하지 않는다.
- [ ] **자동 업데이트 실전 확인** — 직전 버전(업데이터가 들어 있는 빌드)을 설치한 Mac에서 설정 → 버전·업데이트 → `지금 확인` → 새 버전이 뜨는지 → `업데이트` → 재실행 뒤 앱 버전이 바뀌고 IME도 새 빌드로 갱신됐는지(`bash scripts/postinstall_probe.sh` 1번).
- [ ] 이상하면 **릴리스를 지우지 말고** 원인부터 본다. 지우고 다시 올리면 이미 받은 사람과 번호가 꼬인다.

### ⑧ 홍보 — 🔴 오너

- 2026.07 이하 사용자는 업데이터가 없는 버전이라 **이번 한 번은 직접 받아야** 한다. 그들에게 닿는 통로는 홍보뿐이다.

## 하지 말 것

- 태그에 `v` 붙이기 · zip 이름 바꾸기 · pre-release/draft로 올리기
- 게시된 정식 버전의 에셋 바꿔치기 — 새 버전 정책을 충족하는 번호로 게시
- 내부 빌드에 쓴 버전 번호로 릴리스하기
- 빌드한 커밋과 다른 커밋에 태그 달기
