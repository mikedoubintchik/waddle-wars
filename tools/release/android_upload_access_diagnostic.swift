// Read-only access check for the EXISTING Waddle Wars upload-password item.
// No key creation, item update/delete, credential export, signing or upload.
// Data stays inside this process; output contains fixed categories/OSStatus only.
// A separate diagnostic caller may have a different Keychain code requirement
// from the pinned signer. Success is NOT proof of signer access or key usability.
import Foundation
import Security
import LocalAuthentication
import Darwin

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["--non-interactive"] || arguments == ["--interactive"] else {
    FileHandle.standardError.write(Data("Use --non-interactive or --interactive.\n".utf8))
    exit(2)
}
let interactive = arguments == ["--interactive"]
let context = LAContext()
context.interactionNotAllowed = !interactive
let request: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.blubberandbyte.waddlewars.android.upload",
    kSecAttrAccount as String: "waddlewars-upload-v1",
    kSecAttrSynchronizable as String: false,
    kSecMatchLimit as String: kSecMatchLimitOne,
    kSecReturnData as String: true,
    kSecUseAuthenticationContext as String: context,
]
var value: CFTypeRef?
let status = SecItemCopyMatching(request as CFDictionary, &value)
var category: String
var formatValid = false
if status == errSecSuccess {
    if let data = value as? Data, let password = String(data: data, encoding: .utf8),
       password.utf8.count == 64, Data(base64Encoded: password)?.count == 48 {
        category = "access_succeeded_format_valid"
        formatValid = true
    } else {
        category = "access_succeeded_format_invalid"
    }
} else if status == errSecInteractionNotAllowed {
    category = "authentication_interaction_required"
} else if status == errSecAuthFailed {
    category = "authentication_failed"
} else if status == errSecItemNotFound {
    category = "exact_item_not_found"
} else if status == errSecUserCanceled {
    category = "authentication_canceled"
} else {
    category = "keychain_query_failed"
}
value = nil
context.invalidate()
let result: [String: Any] = [
    "kind": "read_only_waddle_upload_access_diagnostic",
    "keychain_status": status,
    "failure_category": category,
    "interaction_allowed": interactive,
    "credential_format_valid": formatValid,
    "credential_returned": false,
    "keychain_item_modified": false,
    "signer_access_proven": false,
]
if let output = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data([10]))
}
exit(formatValid ? 0 : 1)
