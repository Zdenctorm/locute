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
        guard let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty else {
            return false
        }
        return hasDeveloperIDApplicationCertificate(in: info)
    }

    private static func hasDeveloperIDApplicationCertificate(in info: [String: Any]) -> Bool {
        guard let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] else {
            return false
        }
        return certificates.contains { certificate in
            guard let summary = SecCertificateCopySubjectSummary(certificate) as String? else {
                return false
            }
            return summary.contains("Developer ID Application")
        }
    }
}
