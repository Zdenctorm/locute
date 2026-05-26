import Foundation
import Security

enum SparkleUpdateSupport {
    /// Sparkle's background updater (XPC) requires a real Developer ID / distribution signature.
    /// Ad-hoc and linker-signed local builds can run the app but `startUpdater` fails.
    static var isAvailable: Bool {
        guard let executableURL = Bundle.main.executableURL else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }
        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        ) == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return false
        }
        guard let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String else {
            return false
        }
        return !teamID.isEmpty
    }
}
