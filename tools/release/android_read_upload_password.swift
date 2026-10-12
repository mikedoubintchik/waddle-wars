// One-time migration bridge. Writes the existing upload password only to an
// inherited pipe supplied by android_password_vault.py, never stdout/stderr.
import Foundation
import Security
import LocalAuthentication
import Darwin

guard CommandLine.arguments.count == 2,
      let fd = Int32(CommandLine.arguments[1]), fd >= 3 else { exit(1) }
var information = stat()
guard fstat(fd, &information) == 0,
      information.st_mode & S_IFMT == S_IFIFO else { exit(1) }

let context = LAContext()
context.interactionNotAllowed = true
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.blubberandbyte.waddlewars.android.upload",
    kSecAttrAccount as String: "waddlewars-upload-v1",
    kSecAttrSynchronizable as String: false,
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne,
    kSecUseAuthenticationContext as String: context,
]
var value: CFTypeRef?
guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
      let data = value as? Data, data.count == 64,
      let password = String(data: data, encoding: .utf8),
      Data(base64Encoded: password)?.count == 48 else { exit(1) }

let written = data.withUnsafeBytes { bytes -> Int in
    guard let base = bytes.baseAddress else { return -1 }
    return Darwin.write(fd, base, bytes.count)
}
exit(written == data.count ? 0 : 1)
