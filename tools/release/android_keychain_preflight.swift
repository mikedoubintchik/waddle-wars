// Read-only preflight for the existing Waddle Wars Android upload password.
// No password bytes, base64 text, or Keychain error descriptions leave process.
import Foundation
import Security
import LocalAuthentication

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
let status = SecItemCopyMatching(query as CFDictionary, &value)
let passwordValid: Bool
if status == errSecSuccess, let bytes = value as? Data,
   let text = String(data: bytes, encoding: .utf8) {
    passwordValid = text.utf8.count == 64 && Data(base64Encoded: text)?.count == 48
} else {
    passwordValid = false
}
let result: [String: Any] = [
    "state": passwordValid ? "android_password_access_verified" : "android_password_access_failed",
    "keychain_status": status,
    "ready_for_password_read": passwordValid,
]
if let encoded = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
    FileHandle.standardOutput.write(encoded)
    FileHandle.standardOutput.write(Data([10]))
}
exit(passwordValid ? 0 : 1)
