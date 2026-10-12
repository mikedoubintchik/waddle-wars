// App-specific signing bridge. No operation returns a password to its caller.
// Passwords exist only in Security.framework and this process/child environment.
import Foundation
import Security
import LocalAuthentication
import Darwin

let service = "com.blubberandbyte.waddlewars.android.upload"
let account = "waddlewars-upload-v1"
let alias = "waddlewars-upload-v1"
let subject = "Waddle Wars Penguin Panic Android Upload"
let passwordEnvironment = "WADDLE_WARS_UPLOAD_PASSWORD"
let signingRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/WaddleWarsSigning")
    .appendingPathComponent("com.blubberandbyte.waddlewars/android-upload-v1")
var stage = "validating"
var passwordCreated = false
var keyGenerated = false
var backupVerified = false

struct SigningFailure: Error {}

func fail() throws -> Never { throw SigningFailure() }

func publicResult(_ state: String) {
    let result: [String: Any] = ["state": state, "stage": stage,
        "keychain_password_created": passwordCreated, "key_generated": keyGenerated,
        "backup_verified": backupVerified]
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

func exactFile(_ value: String, _ expected: URL, executable: Bool = false) throws -> URL {
    let url = URL(fileURLWithPath: value)
    guard value.hasPrefix("/"), !value.split(separator: "/").contains(".."),
          url.path == expected.path else { try fail() }
    try regular(url, executable: executable)
    return url
}

func noLinks(_ url: URL) throws {
    var path = url.path
    while path != "/" {
        var information = stat()
        if lstat(path, &information) == 0 {
            guard information.st_mode & S_IFMT != S_IFLNK else { try fail() }
        } else if errno != ENOENT { try fail() }
        path = URL(fileURLWithPath: path).deletingLastPathComponent().path
    }
}

func regular(_ url: URL, executable: Bool = false, privateFile: Bool = false) throws {
    try noLinks(url)
    var information = stat()
    guard lstat(url.path, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
          !executable || access(url.path, X_OK) == 0,
          !privateFile || (information.st_uid == getuid() && information.st_mode & 0o777 == 0o600)
    else { try fail() }
}

func privateDirectory(_ url: URL) throws {
    try noLinks(url)
    var information = stat()
    guard lstat(url.path, &information) == 0, information.st_mode & S_IFMT == S_IFDIR,
          information.st_uid == getuid(), information.st_mode & 0o777 == 0o700 else { try fail() }
}

func missing(_ url: URL) throws {
    try noLinks(url)
    var information = stat()
    guard lstat(url.path, &information) != 0, errno == ENOENT else { try fail() }
}

func query() -> [String: Any] {
    return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false]
}

func nonInteractiveQuery() -> [String: Any] {
    var request = query()
    let context = LAContext()
    context.interactionNotAllowed = true
    request[kSecUseAuthenticationContext as String] = context
    return request
}

func itemPresent() throws -> Bool {
    var request = nonInteractiveQuery()
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    let status = SecItemCopyMatching(request as CFDictionary, nil)
    if status == errSecItemNotFound { return false }
    // An interaction-protected existing item must not be overwritten either.
    if status == errSecSuccess || status == errSecInteractionNotAllowed { return true }
    try fail()
}

func createPassword() throws -> String {
    var random = [UInt8](repeating: 0, count: 48)
    guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { try fail() }
    let password = Data(random).base64EncodedString()
    _ = random.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    var request = query()
    request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    request[kSecValueData as String] = Data(password.utf8)
    // SecItemAdd, never SecItemUpdate/Delete: races and duplicate items fail closed.
    guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { try fail() }
    passwordCreated = true
    return password
}

func loadPassword() throws -> String {
    var request = nonInteractiveQuery()
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    // Signing is unattended. A locked/protected Keychain must fail closed,
    // not open an authentication dialog or wait for user interaction.
    var value: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
          let data = value as? Data, let password = String(data: data, encoding: .utf8),
          password.utf8.count == 64,
          Data(base64Encoded: password)?.count == 48 else { try fail() }
    return password
}

func toolEnvironment(_ jdk: URL, password: String) -> [String: String] {
    // Do not inherit JAVA_TOOL_OPTIONS/JDK_JAVA_OPTIONS/_JAVA_OPTIONS or other
    // arbitrary parent variables; Java can echo those into logs before startup.
    return ["PATH": jdk.appendingPathComponent("bin").path + ":/usr/bin:/bin",
            "LANG": "C", "LC_ALL": "C", "TZ": "UTC", passwordEnvironment: password]
}

final class ToolDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var expired = false
    func expire() { lock.lock(); expired = true; lock.unlock() }
    func didExpire() -> Bool { lock.lock(); defer { lock.unlock() }; return expired }
}

func runDiscardingOutput(_ executable: URL, _ arguments: [String], _ environment: [String: String]) throws {
    let child = Process()
    let output = Pipe()
    child.executableURL = executable
    child.arguments = arguments
    child.environment = environment
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = output
    child.standardError = output
    try child.run()
    let deadline = ToolDeadline()
    let timeout = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timeout.schedule(deadline: .now() + 180)
    timeout.setEventHandler {
        if child.isRunning {
            deadline.expire()
            _ = kill(child.processIdentifier, SIGTERM)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
            }
        }
    }
    timeout.resume()
    defer { timeout.cancel() }
    // Raw tool output is never forwarded, persisted, or put into exceptions.
    _ = output.fileHandleForReading.readDataToEndOfFile()
    child.waitUntilExit()
    guard !deadline.didExpire(), child.terminationReason == .exit, child.terminationStatus == 0 else { try fail() }
}

func bootstrap(_ keytoolPath: String, _ storePath: String, _ backupPath: String, _ certificatePath: String) throws {
    let keytool = URL(fileURLWithPath: keytoolPath)
    guard keytoolPath.hasPrefix("/"), !keytoolPath.split(separator: "/").contains(".."),
          keytool.lastPathComponent == "keytool", keytool.deletingLastPathComponent().lastPathComponent == "bin"
    else { try fail() }
    try regular(keytool, executable: true)
    let jdk = keytool.deletingLastPathComponent().deletingLastPathComponent()
    let store = signingRoot.appendingPathComponent("primary/upload.p12")
    let backup = signingRoot.appendingPathComponent("backup/upload.p12")
    let certificate = signingRoot.appendingPathComponent("upload-cert.der")
    guard storePath == store.path, backupPath == backup.path, certificatePath == certificate.path else { try fail() }
    try privateDirectory(signingRoot)
    try privateDirectory(store.deletingLastPathComponent())
    try privateDirectory(backup.deletingLastPathComponent())
    for destination in [store, backup, certificate] { try missing(destination) }
    stage = "checking_keychain"
    guard try !itemPresent() else { try fail() }
    stage = "creating_keychain_password"
    let password = try createPassword()
    let environment = toolEnvironment(jdk, password: password)
    stage = "generating_upload_key"
    try runDiscardingOutput(keytool, ["-genkeypair", "-keystore", store.path,
        "-storetype", "PKCS12", "-alias", alias, "-keyalg", "RSA", "-keysize", "4096",
        "-sigalg", "SHA256withRSA", "-validity", "10000", "-dname", "CN=" + subject,
        "-storepass:env", passwordEnvironment, "-keypass:env", passwordEnvironment, "-noprompt"], environment)
    guard chmod(store.path, 0o600) == 0 else { try fail() }
    try regular(store, privateFile: true)
    keyGenerated = true
    stage = "copying_encrypted_backup"
    try FileManager.default.copyItem(at: store, to: backup)
    guard chmod(backup.path, 0o600) == 0 else { try fail() }
    try regular(backup, privateFile: true)
    guard try Data(contentsOf: store) == Data(contentsOf: backup) else { try fail() }
    backupVerified = true
    stage = "exporting_public_certificate"
    try runDiscardingOutput(keytool, ["-exportcert", "-keystore", store.path, "-storetype", "PKCS12",
        "-alias", alias, "-storepass:env", passwordEnvironment, "-file", certificate.path], environment)
    guard chmod(certificate.path, 0o600) == 0 else { try fail() }
    try regular(certificate, privateFile: true)
    let data = try Data(contentsOf: certificate)
    guard let cert = SecCertificateCreateWithData(nil, data as CFData),
          SecCertificateCopySubjectSummary(cert) as String? == subject,
          let key = SecCertificateCopyKey(cert),
          let attributes = SecKeyCopyAttributes(key) as? [String: Any],
          attributes[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String,
          attributes[kSecAttrKeySizeInBits as String] as? Int == 4096 else { try fail() }
    stage = "complete"
}

// Release signing is deliberately separate from Godot export: Godot 4.7.1
// otherwise copies release passwords into Gradle -P arguments. The launcher
// must export unsigned first, then invoke this fixed jarsigner operation.
func sign(_ jarsignerPath: String, _ unsignedPath: String, _ signedPath: String, _ storePath: String) throws {
    let jarsigner = URL(fileURLWithPath: jarsignerPath)
    guard jarsignerPath.hasPrefix("/"), !jarsignerPath.split(separator: "/").contains(".."),
          jarsigner.lastPathComponent == "jarsigner",
          jarsigner.deletingLastPathComponent().lastPathComponent == "bin" else { try fail() }
    try regular(jarsigner, executable: true)
    let store = try exactFile(storePath, signingRoot.appendingPathComponent("primary/upload.p12"))
    try regular(store, privateFile: true)
    let unsigned = URL(fileURLWithPath: unsignedPath), signed = URL(fileURLWithPath: signedPath)
    guard unsignedPath.hasPrefix("/"), signedPath.hasPrefix("/"),
          !unsignedPath.split(separator: "/").contains(".."), !signedPath.split(separator: "/").contains(".."),
          unsigned.pathExtension == "aab", signed.pathExtension == "aab", unsigned != signed,
          !unsigned.path.hasPrefix(signingRoot.path + "/"), !signed.path.hasPrefix(signingRoot.path + "/")
    else { try fail() }
    try regular(unsigned)
    try noLinks(signed)
    try missing(signed)
    try privateDirectory(signed.deletingLastPathComponent())
    stage = "reading_app_specific_keychain_password"
    let password = try loadPassword()
    let jdk = jarsigner.deletingLastPathComponent().deletingLastPathComponent()
    stage = "signing_aab"
    try runDiscardingOutput(jarsigner, ["-keystore", store.path, "-storetype", "PKCS12",
        "-storepass:env", passwordEnvironment, "-keypass:env", passwordEnvironment,
        "-sigalg", "SHA256withRSA", "-digestalg", "SHA-256", "-signedjar", signed.path,
        unsigned.path, alias], toolEnvironment(jdk, password: password))
    guard chmod(signed.path, 0o600) == 0 else { try fail() }
    try regular(signed, privateFile: true)
    stage = "complete"
}

umask(0o077)
do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["probe"] {
        stage = "checking_keychain"
        publicResult(try itemPresent() ? "item_exists" : "item_absent")
    } else if arguments.count == 5 && arguments[0] == "bootstrap" {
        try bootstrap(arguments[1], arguments[2], arguments[3], arguments[4])
        publicResult("bootstrap_complete")
    } else if arguments.count == 5 && arguments[0] == "sign" {
        try sign(arguments[1], arguments[2], arguments[3], arguments[4])
        publicResult("sign_complete")
    } else { try fail() }
} catch {
    // Never print Error.localizedDescription: child libraries may include
    // credentials or raw subprocess output in error descriptions.
    publicResult("operation_failed")
    exit(1)
}
