import Foundation
import Security

/// Generic-password storage for the manually entered provider credentials
/// (session cookies, API keys, bearer tokens).
///
/// One item per provider under a shared service name, so revoking a single
/// provider never disturbs the others and `security find-generic-password`
/// can be used to inspect them.
public enum Keychain {
    public static let service = "bar.quota.QuotaBar"

    public static func read(account: String, service: String = Keychain.service) -> String? {
        KeychainSession.read(account: account, service: service)
    }

    /// Upserts the item. Returns false when the keychain refuses the write, so
    /// callers can surface a real error instead of silently dropping the secret.
    @discardableResult
    public static func write(_ value: String, account: String, service: String = Keychain.service) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            KeychainSession.store(value, account: account, service: service)
            return true
        }
        guard status == errSecItemNotFound else { return false }

        var insert = base
        insert[kSecValueData as String] = data
        // Available without an unlocked login keychain prompt after the first
        // unlock, and never synced to iCloud — these are machine-local sessions.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        insert[kSecAttrSynchronizable as String] = false
        insert[kSecAttrLabel as String] = "QuotaBar — \(account)"
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { return false }
        KeychainSession.store(value, account: account, service: service)
        return true
    }

    @discardableResult
    public static func delete(account: String, service: String = Keychain.service) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            KeychainSession.forget(account: account, service: service)
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Why a read came back empty. A rebuilt app is a new signature, so an
    /// item this app saved last time is still there but this process is not
    /// on its access list — that is `.denied`, not `.missing`.
    enum Lookup {
        case found(String)
        case missing
        case denied
    }

    static func lookup(account: String, service: String = Keychain.service) -> Lookup {
        switch KeychainSession.silent(account: account, service: service) {
        case let .found(value): return .found(value)
        case .missing: return .missing
        case .denied: return .denied
        }
    }
}

/// One prompt per keychain item for this launch. Later refreshes reuse what
/// the first read already unlocked, so a timer does not ask for the password again.
enum KeychainSession {
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]
    /// Asked already, and there is nothing to keep: missing, or the user said no.
    private static var settled: Set<String> = []
    private static var inflight: [String: DispatchGroup] = [:]

    static func read(account: String, service: String) -> String? {
        let key = "\(service)\n\(account)"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        if settled.contains(key) {
            lock.unlock()
            return nil
        }
        if let group = inflight[key] {
            lock.unlock()
            group.wait()
            lock.lock()
            let hit = cache[key]
            lock.unlock()
            return hit
        }
        let group = DispatchGroup()
        group.enter()
        inflight[key] = group
        lock.unlock()

        let value = unlock(account: account, service: service)
        lock.lock()
        if let value { cache[key] = value } else { settled.insert(key) }
        inflight[key] = nil
        lock.unlock()
        group.leave()
        return value
    }

    static func store(_ value: String, account: String, service: String) {
        let key = "\(service)\n\(account)"
        lock.lock()
        cache[key] = value
        settled.remove(key)
        lock.unlock()
    }

    static func forget(account: String, service: String) {
        let key = "\(service)\n\(account)"
        lock.lock()
        cache[key] = nil
        settled.remove(key)
        lock.unlock()
    }

    fileprivate static func silent(account: String, service: String) -> Keychain.Lookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = LocalCredentials.KeychainUI.withoutPrompts {
            SecItemCopyMatching(query as CFDictionary, &result)
        }
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty
            else { return .missing }
            return .found(value)
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            return .denied
        default:
            return .missing
        }
    }

    /// Silent read first. A dialog only if this process has not asked for this
    /// item yet; the answer is kept until quit.
    private static func unlock(account: String, service: String) -> String? {
        switch silent(account: account, service: service) {
        case let .found(value): return value
        case .missing: return nil
        case .denied: return KeychainTool.readBlocking(account: account, service: service)
        }
    }
}

/// Indirection so tests can exercise `ConfigStore` without touching the real
/// login keychain (which would prompt, and would leak between test runs).
public protocol CredentialStorage: Sendable {
    func read(account: String) -> String?
    @discardableResult func write(_ value: String, account: String) -> Bool
    @discardableResult func delete(account: String) -> Bool
}

public struct KeychainStorage: CredentialStorage {
    public init() {}
    public func read(account: String) -> String? { Keychain.read(account: account) }
    @discardableResult public func write(_ value: String, account: String) -> Bool {
        Keychain.write(value, account: account)
    }
    @discardableResult public func delete(account: String) -> Bool {
        Keychain.delete(account: account)
    }
}

/// Reads one of this app's own items through `/usr/bin/security` when
/// `SecItemCopyMatching` cannot. An ad-hoc rebuild is a new signature, so the
/// login keychain stops trusting the app that created the item and the direct
/// read comes back empty — which is how the saved Codex accounts vanish after
/// a local install. The tool is trusted once the user allows it, and a refusal
/// is remembered so a refresh does not ask again.
enum KeychainTool {
    private static let lock = NSLock()
    private static var declined: Set<String> = []
    /// errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled.
    private static let refusals: Set<Int32> = [36, 51, 128]

    static func read(account: String, service: String = Keychain.service) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: readBlocking(account: account, service: service))
            }
        }
    }

    static func readBlocking(account: String, service: String) -> String? {
        lock.lock()
        let skip = declined.contains(account)
        lock.unlock()
        guard !skip, FileManager.default.isExecutableFile(atPath: "/usr/bin/security") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let status = process.terminationStatus
        guard status == 0 else {
            if refusals.contains(status) {
                lock.lock()
                declined.insert(account)
                lock.unlock()
            }
            return nil
        }
        let data = textSecret(output)
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    /// `-w` prints the secret and a newline, as hex when the bytes are not text.
    private static func textSecret(_ output: Data) -> Data {
        var bytes = output
        while let last = bytes.last, last == 0x0A || last == 0x0D { bytes.removeLast() }
        guard let text = String(data: bytes, encoding: .utf8), !text.isEmpty,
              text.first != "{", text.first != "[",
              text.count % 2 == 0, text.allSatisfy(\.isHexDigit)
        else { return bytes }
        var decoded = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return bytes }
            decoded.append(byte)
            index = next
        }
        return decoded
    }
}

/// In-memory stand-in used by the test suite.
public final class MemoryCredentialStorage: CredentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    public init(_ seed: [String: String] = [:]) {
        items = seed
    }

    public func read(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return items[account]
    }

    @discardableResult public func write(_ value: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items[account] = value
        return true
    }

    @discardableResult public func delete(account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items[account] = nil
        return true
    }
}
