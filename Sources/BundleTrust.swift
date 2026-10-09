import Foundation
import Security

/// #67/#68: Team 문자열 일치만으로 신뢰하지 않고 Apple 인증서 체인까지 확인한다.
enum BundleTrust {
    static let debugSkipTeamCheckKey = "haneul.debugSkipTeamCheck"

    static func allowsUnsignedDevelopment(defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        return defaults.bool(forKey: debugSkipTeamCheckKey)
        #else
        return false
        #endif
    }

    static func isSameTeamSignedBundle(at candidate: URL, host: URL = Bundle.main.bundleURL,
                                      defaults: UserDefaults = .standard) -> Bool {
        if allowsUnsignedDevelopment(defaults: defaults) { return true }
        guard let team = teamIdentifier(at: host),
              isAppleSignedBundle(at: host, matchingTeam: team) else { return false }
        return isAppleSignedBundle(at: candidate, matchingTeam: team)
    }

    static func requirement(for team: String) -> SecRequirement? {
        // Team ID를 requirement 언어에 삽입하기 전에 허용 문자/길이를 제한한다.
        guard team.utf8.count == 10,
              team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { return nil }
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    static func isAppleSignedBundle(at url: URL, matchingTeam team: String) -> Bool {
        guard let requirement = requirement(for: team) else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess,
              teamIdentifier(at: url) == team else { return false }
        return true
    }

    static func teamIdentifier(at url: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let fields = info as? [String: Any] else { return nil }
        return fields[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
