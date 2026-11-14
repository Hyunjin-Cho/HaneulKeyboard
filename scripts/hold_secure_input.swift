// 2026-11-12 (#224, 리뷰 input-core-F-2): 다른 앱이 켜 둔 "보안 입력"이 하늘키보드의 한글 조합을 막는지 실기기에서 확인하는 도구.
//
// 배경: 입력기는 키마다 macOS의 보안 입력 여부(IsSecureEventInputEnabled)를 보고, 켜져 있으면 조합하지 않고 키를 그대로 넘긴다
// (비밀번호 칸 보호). 그런데 이 값은 지금 입력칸이 아니라 **세션 전체** 값이다 — 뒤에 있는 다른 프로그램이 켜 둔 채 남아 있어도 참이다.
// 그때 macOS가 평범한 입력칸의 키를 입력기에 보내는지는 실제로 켜 봐야 안다. 이 도구는 보안 입력을 켠 채 기다리는 작은 프로그램이다.
// 앱·입력기 타깃에 들어가지 않는다(project.yml과 무관). 네트워크·파일 쓰기·키 기록은 하지 않는다.
//
// 사용법 (터미널, 저장소 루트에서):
//   swift scripts/hold_secure_input.swift          # 기본 30초
//   swift scripts/hold_secure_input.swift 60       # 60초
//   끝나면(또는 Ctrl+C) 보안 입력을 끄고 종료한다. 프로세스가 끝나면 macOS도 이 프로그램이 켠 보안 입력을 거둔다.
//
// 확인 순서:
//   1) 위 명령을 실행하고 "보안 입력 켜짐"이 찍히는지 본다.
//      (다른 터미널에서 `ioreg -l -w 0 | grep SecureInput` 을 치면 kCGSSessionSecureInputPID 에 이 프로그램 번호가 보인다.)
//   2) 시간이 끝나기 전에 TextEdit(새 문서)으로 옮겨, 하늘키보드 한글 모드에서 `dkssud` + Space 를 친다.
//   3) 판정:
//      - 화면에 `dkssud ` 처럼 영문(ABC 글자)이 그대로 들어가면 → **재현**(다른 앱의 보안 입력이 모든 앱의 한글 조합을 막는다).
//      - `안녕 ` 이 들어가면 → 재현 안 됨(macOS가 이 상태에서는 다른 앱 입력칸을 막지 않거나, 입력기가 보는 값이 다르다).
//      - 아예 아무 글자도 안 들어가면 → 그 결과를 그대로 적어 알려 준다(다른 원인).
//   4) 도구를 끝낸 뒤(시간 만료 또는 Ctrl+C) 같은 TextEdit에서 `dkssud` + Space 가 `안녕 ` 으로 돌아오는지 확인한다.
//   결과는 docs/manual-test-checklist.md 「다른 앱이 켠 전역 보안 입력」 항목에 적는다.
//   2026-11-14: 재현됐고, 오너 결정으로 입력기 판정은 좁히지 않고 메뉴바 메뉴에서 알린다 — 경위는 `isSecureInputActive` 주석과 #224.

import Carbon
import Foundation

let requested = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 30
let seconds = min(max(requested, 1), 600)   // 실수로 오래 켜 두지 않게 10분을 넘기지 않는다

func finish(_ reason: String) -> Never {
    DisableSecureEventInput()
    print("보안 입력 끔(\(reason)). 지금 세션 보안 입력: \(IsSecureEventInputEnabled() ? "켜짐(다른 프로그램이 켜 둠)" : "꺼짐")")
    exit(0)
}

// Ctrl+C·종료 신호에도 끄고 나간다. 신호 처리기 안에서는 직접 끄지 않고 메인 큐에서 끈다.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler { finish("Ctrl+C") }
interrupt.resume()
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { finish("종료 신호") }
terminate.resume()

print("지금 세션 보안 입력(켜기 전): \(IsSecureEventInputEnabled() ? "켜짐" : "꺼짐")")
EnableSecureEventInput()
print("보안 입력 켜짐 — 프로세스 번호 \(ProcessInfo.processInfo.processIdentifier), \(Int(seconds))초 동안 유지한다.")
print("이제 TextEdit으로 옮겨 하늘키보드 한글 모드에서 dkssud + Space 를 쳐 본다(영문이 그대로 나오면 재현).")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish("\(Int(seconds))초 지남") }
dispatchMain()
