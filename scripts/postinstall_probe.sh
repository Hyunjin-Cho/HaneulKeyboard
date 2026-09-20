#!/bin/bash
# postinstall_probe.sh — 빌드·설치 직후 "기계가 볼 수 있는" 항목을 자동 확인한다. (#52, 2026-09-20)
#
# 사용:  bash scripts/postinstall_probe.sh            # 읽기 전용 — 아무것도 바꾸지 않는다
#
# 왜: 자동 테스트(run_ime_tests.sh)는 "자판 → 글자"만 검사한다. 설치·등록·서명·연동 같은
# 몸통은 수동 체크리스트(docs/manual-test-checklist.md)에만 있어 매번 손으로 눌러야 했고,
# 그래서 검증·릴리스가 밀렸다(2026-09-20 회의). 여기서 확인되는 항목은 체크리스트에서 뺀다.
#
# 항목: 1 버전 일치  2 서명·Gatekeeper·staple  3 입력 소스 등록·enabled·중복
#       4 LaunchServices 등록 경로(메인 앱은 /Applications 하나뿐이어야 — 리뷰 F-4 전제)
#       5 최근 30분 로그 error  6 #32 연동 기록(haneul.mainAppPath / FileID)
# 출력: 항목별 ✓/✗ 한 줄, 마지막에 집계. 하나라도 ✗면 종료코드 1.
set -uo pipefail
cd "$(dirname "$0")/.."

pass=0; fail=0
ok() { echo "  ✓ $1"; pass=$((pass + 1)); }
ng() { echo "  ✗ $1"; fail=$((fail + 1)); }

MV=$(grep -E '^[[:space:]]*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BV=$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
APP="/Applications/HaneulKeyboard.app"
IME="/Library/Input Methods/HaneulKeyboardIM.app"
[ -d "$IME" ] || IME="$HOME/Library/Input Methods/HaneulKeyboardIM.app"
MAIN_ID="com.hyunjincho.haneulkeyboard"
IME_ID="com.hyunjincho.inputmethod.haneul"

echo "■ 1. 버전 — project.yml = $MV / $BV"
for b in "$APP" "$IME"; do
  if [ -d "$b" ]; then
    v=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$b/Contents/Info.plist" 2>/dev/null)
    n=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$b/Contents/Info.plist" 2>/dev/null)
    if [ "$v" = "$MV" ] && [ "$n" = "$BV" ]; then ok "$b = $v/$n"
    else ng "$b = ${v:-없음}/${n:-없음} (기대 $MV/$BV) — 새 빌드가 아직 설치되지 않았거나 옛 사본"; fi
  else
    ng "$b 없음"
  fi
done

echo "■ 2. 서명·Gatekeeper·staple"
for b in "$APP" "$IME"; do
  [ -d "$b" ] || continue
  if codesign --verify --deep --strict "$b" 2>/dev/null; then ok "codesign  $b"; else ng "codesign  $b"; fi
  if spctl -a -t exec "$b" 2>/dev/null; then ok "Gatekeeper $b"; else ng "Gatekeeper $b (노타리 미완?)"; fi
done
# staple은 최상위 앱에만 붙는다(내부 IME 번들은 별도 staple 불가).
if [ -d "$APP" ]; then
  if xcrun stapler validate "$APP" >/dev/null 2>&1; then ok "staple    $APP"; else ng "staple    $APP"; fi
fi

# 3·4는 Swift 한 조각으로 시스템에 직접 묻는다(읽기 전용). 컴파일 몇 초.
PROBE="$(mktemp -d)/probe.swift"
cat > "$PROBE" <<'SWIFT'
import AppKit
import Carbon
let mainID = CommandLine.arguments[1], imeID = CommandLine.arguments[2]
// 3. 입력 소스
if let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] {
    for s in list {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyBundleID) else { continue }
        let bid = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        guard bid == imeID else { continue }
        let sid = (TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
        let en = (TISGetInputSourceProperty(s, kTISPropertyInputSourceIsEnabled)).map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) } ?? false
        let sel = (TISGetInputSourceProperty(s, kTISPropertyInputSourceIsSelected)).map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) } ?? false
        print("TIS\t\(sid)\t\(en ? "enabled" : "disabled")\t\(sel ? "selected" : "-")")
    }
}
// 4. LaunchServices
for id in [mainID, imeID] {
    for u in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id) { print("LS\t\(id)\t\(u.path)") }
}
SWIFT
OUT=$(swift "$PROBE" "$MAIN_ID" "$IME_ID" 2>/dev/null)
rm -rf "$(dirname "$PROBE")"

echo "■ 3. 입력 소스(TIS)"
tis_lines=$(printf '%s\n' "$OUT" | grep -c '^TIS' || true)
if [ "$tis_lines" -eq 0 ]; then ng "우리 입력 소스가 TIS 목록에 없음"
else
  printf '%s\n' "$OUT" | grep '^TIS' | while IFS=$'\t' read -r _ sid en sel; do
    if [ "$en" = "enabled" ]; then ok "$sid $en $sel"; else ng "$sid $en (설정에서 켜야 함)"; fi
  done
  dup=$(printf '%s\n' "$OUT" | grep '^TIS' | cut -f2 | sort | uniq -d | wc -l | tr -d ' ')
  [ "$dup" -eq 0 ] && ok "입력 소스 중복 행 없음" || ng "입력 소스 중복 행 $dup (Tahoe 캐시 중복 — 재부팅 필요)"
fi

echo "■ 4. LaunchServices 등록 경로"
main_urls=$(printf '%s\n' "$OUT" | awk -F'\t' -v id="$MAIN_ID" '$1=="LS" && $2==id {print $3}')
main_n=$(printf '%s\n' "$main_urls" | grep -c . || true)
if [ "$main_n" -eq 1 ] && [ "$main_urls" = "$APP" ]; then ok "메인 앱 = $APP 하나 (F-4 전제 충족)"
else ng "메인 앱 등록 ${main_n}개 — 자기 정리 판정이 흐려짐:"; printf '%s\n' "$main_urls" | sed 's/^/      /'; fi
ime_bad=$(printf '%s\n' "$OUT" | awk -F'\t' -v id="$IME_ID" '$1=="LS" && $2==id {print $3}' | grep -vE '^(/Library/Input Methods/|'"$HOME"'/Library/Input Methods/|/Applications/HaneulKeyboard\.app/Contents/Helpers/)' || true)
if [ -z "$ime_bad" ]; then ok "IME 등록 경로는 설치본·임베드뿐(빌드 산출물 없음)"
else ng "IME가 빌드 산출물 경로로도 등록됨(입력 소스 중복 위험) — lsregister -u 로 정리:"; printf '%s\n' "$ime_bad" | sed 's/^/      /'; fi

echo "■ 5. 로그(최근 30분, subsystem $MAIN_ID)"
errs=$(/usr/bin/log show --predicate "subsystem == \"$MAIN_ID\" AND messageType == error" --last 30m --style compact 2>/dev/null | grep -vc '^Timestamp' || true)
[ "${errs:-0}" -eq 0 ] && ok "error 0건" || ng "error ${errs}건 — /usr/bin/log show --predicate 'subsystem == \"$MAIN_ID\"' --last 30m"

echo "■ 6. #32 연동 기록(IME 설정 도메인)"
rec_path=$(defaults read "$IME_ID" haneul.mainAppPath 2>/dev/null || true)
rec_id=$(defaults read "$IME_ID" haneul.mainAppFileID 2>/dev/null || true)
real_id=$(stat -f %i "$APP" 2>/dev/null || true)
if [ "$rec_path" = "$APP" ] && [ -n "$rec_id" ] && [ "$rec_id" = "$real_id" ]; then ok "haneul.mainAppPath=$rec_path, FileID 일치($rec_id)"
elif [ -z "$rec_path" ]; then ng "기록 없음 — 새 앱을 한 번 실행해야 기록됨(#32는 실행 시 기록)"
else ng "기록 불일치: path=$rec_path fileID=${rec_id:-없음} (실제 $real_id) — 앱을 다시 실행하면 갱신"; fi

echo "── 집계: ✓ $pass / ✗ $fail"
[ "$fail" -eq 0 ]
