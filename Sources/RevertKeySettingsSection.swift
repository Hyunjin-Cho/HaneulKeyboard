import AppKit
import SwiftUI

/// 설정 → "되돌리기 키" + "앱별 자동 변환 끄기" 두 절. (#54, 2026-09-21)
///
/// `SettingsView`의 `Section("입력")` 바로 뒤에 붙는다. 본문을 이 파일로 뺀 이유: 같은 시기에
/// 다른 절(개인 사전)이 `SettingsView.swift`에 들어가고 있어 충돌 면을 줄이려고.
/// 저장 키·후보 목록·판정은 IME와 공유하는 `IMESources/RevertKey.swift`·
/// `IMESources/AutoConvertPolicy.swift`(양쪽 타겟에 포함)가 단일 진실이고, 여기는 화면과
/// defaults 쓰기만 한다.
struct RevertKeySettingsSection: View {
    /// IME 도메인 — `SettingsView.imeDefaults`와 같은 이유로 `UserDefaults.standard`가 아니다
    /// (IME 헬퍼는 자기 도메인 `com.hyunjincho.inputmethod.haneul`만 읽는다).
    private static let imeDefaults = UserDefaults(suiteName: "com.hyunjincho.inputmethod.haneul")

    @State private var revertKey: RevertKey = RevertKey.resolve(
        rawValue: RevertKeySettingsSection.imeDefaults?.string(forKey: RevertKey.defaultsKey))
    @State private var disabledIDs: [String] =
        RevertKeySettingsSection.imeDefaults?.stringArray(forKey: AutoConvertPolicy.disabledAppsKey) ?? []
    @State private var showingAppPicker = false
    /// "실행 중인 앱에서 추가..."를 누른 순간의 스냅샷 — 시트가 열려 있는 동안 목록이 흔들리지 않게.
    @State private var runningApps: [RunningApp] = []

    var body: some View {
        Section("되돌리기 키") {
            Picker("변환 되돌리기 키", selection: $revertKey) {
                ForEach(RevertKey.allCases, id: \.self) { key in
                    Text(key.displayName).tag(key)
                }
            }
            .onChange(of: revertKey) { _, newValue in
                Self.imeDefaults?.set(newValue.rawValue, forKey: RevertKey.defaultsKey)
            }
            Text("영타가 자동으로 바뀐 직후 이 키를 누르면 원래 한글로 되돌리고, 다시 누르면 영어로 돌아옵니다. 고른 조합은 시스템이나 다른 앱의 단축키와 겹칠 수 있어요 — 겹치면 다른 조합을 고르세요. (Control+Space는 macOS의 입력 소스 전환 키라 목록에 없습니다.)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Terminal·Ghostty 같은 터미널 앱에서는 되돌리기가 동작하지 않습니다 — 입력된 글자가 곧바로 셸에 넘어가 입력기가 회수할 수 없어요. 자동 변환 자체는 정상 동작합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("앱별 자동 변환 끄기") {
            Text("아래 앱에서는 한글 모드로 영어를 쳐도 자동으로 바꾸지 않습니다. (위 \"영타 자동 변환\"이 꺼져 있으면 목록과 무관하게 모든 앱에서 바꾸지 않습니다.)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if disabledIDs.isEmpty {
                Text("끈 앱이 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(disabledIDs, id: \.self) { bundleID in
                    let name = Self.displayName(forBundleID: bundleID)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name ?? bundleID)
                            if name != nil {
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            update(AutoConvertPolicy.removing(bundleID, from: disabledIDs))
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(name ?? bundleID) 목록에서 제거")
                    }
                }
            }

            Button("실행 중인 앱에서 추가...") {
                runningApps = RunningApp.snapshot()
                showingAppPicker = true
            }
            .sheet(isPresented: $showingAppPicker) {
                RunningAppPickerSheet(apps: runningApps, disabledIDs: $disabledIDs) { bundleID in
                    update(AutoConvertPolicy.adding(bundleID, to: disabledIDs))
                }
            }
        }
    }

    /// 화면 상태와 IME defaults를 함께 바꾼다 — 목록 변경 경로는 이 하나뿐.
    private func update(_ newList: [String]) {
        disabledIDs = newList
        Self.imeDefaults?.set(newList, forKey: AutoConvertPolicy.disabledAppsKey)
    }

    /// 목록에 저장된 bundle ID의 표시 이름. 실행 중이면 그 이름, 아니면 LaunchServices가 아는
    /// 앱 번들의 파일 표시명(확장자 없이·현지화). 둘 다 없으면 nil → 화면엔 bundle ID만.
    static func displayName(forBundleID bundleID: String) -> String? {
        let workspace = NSWorkspace.shared
        if let running = workspace.runningApplications.first(where: {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
        }), let name = running.localizedName {
            return name
        }
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }
}

/// 실행 중인 일반 앱(Dock에 뜨는 `.regular`)의 이름·bundle ID. 메뉴바 전용(`.accessory`,
/// HaneulKeyboard 자신 포함)·백그라운드(`.prohibited`) 프로세스는 뺀다 — 그런 앱엔 텍스트 필드가
/// 없거나 있어도 사용자가 "그 앱"이라고 인지하지 못한다.
struct RunningApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    static func snapshot(workspace: NSWorkspace = .shared) -> [RunningApp] {
        var seen = Set<String>()
        var apps: [RunningApp] = []
        for app in workspace.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty,
                  seen.insert(bundleID.lowercased()).inserted else { continue }
            apps.append(RunningApp(bundleID: bundleID, name: app.localizedName ?? bundleID))
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// "실행 중인 앱에서 추가..." 시트. 목록은 부모가 넘긴 스냅샷이고, 이미 추가된 앱은 버튼 대신
/// "추가됨"으로 보인다(부모 상태를 Binding으로 보므로 추가 즉시 갱신).
private struct RunningAppPickerSheet: View {
    let apps: [RunningApp]
    @Binding var disabledIDs: [String]
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("실행 중인 앱")
                .font(.headline)
            Text("Dock에 보이는 앱만 나옵니다. 끄고 싶은 앱을 먼저 실행해 두세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if apps.isEmpty {
                Text("실행 중인 앱이 없습니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(apps) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isDisabled(app.bundleID) {
                            Text("추가됨")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("추가") { onAdd(app.bundleID) }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 440, height: 380)
    }

    private func isDisabled(_ bundleID: String) -> Bool {
        !AutoConvertPolicy.allowed(globalEnabled: true, disabledIDs: disabledIDs, clientBundleID: bundleID)
    }
}
