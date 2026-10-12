import Foundation
import StoreKit

// StoreKit verifies device-side signatures; the game's server separately binds
// transactions to accounts and grants ownership. finish() is deliberately absent
// from purchase/restore/update handlers, preserving Apple's unfinished replay.
@MainActor
@objc(WWStoreKitBridge)
public final class WWStoreKitBridge: NSObject {
    @objc public static let shared = WWStoreKitBridge()
    @objc public var eventHandler: ((String, String) -> Void)?

    private var products: [String: Product] = [:]
    private var unfinished: [UInt64: Transaction] = [:]
    private var updatesTask: Task<Void, Never>?
    private var operations: [UUID: Task<Void, Never>] = [:]

    @objc public func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { break }
                self.deliver(result)
            }
        }
        operation { [weak self] in
            for await result in Transaction.unfinished {
                guard !Task.isCancelled, let self else { break }
                self.deliver(result)
            }
        }
    }

    @objc public func stop() {
        eventHandler = nil
        updatesTask?.cancel()
        updatesTask = nil
        for task in operations.values { task.cancel() }
        operations.removeAll()
        unfinished.removeAll()
        products.removeAll()
    }

    @objc(requestProducts:)
    public func requestProducts(_ identifiers: [String]) {
        start()
        operation { [weak self] in
            guard let self else { return }
            do {
                let found = try await Product.products(for: identifiers)
                guard !Task.isCancelled else { return }
                var rows: [[String: Any]] = []
                for product in found where product.type == .nonConsumable {
                    self.products[product.id] = product
                    rows.append([
                        "product_id": product.id,
                        "localized_price": product.displayPrice,
                        "display_name": product.displayName,
                        "description": product.description,
                        "type": "non_consumable"
                    ])
                }
                self.emit("products_received", rows)
            } catch {
                self.failure("Products are unavailable. Please try again.")
            }
        }
    }

    @objc(purchaseProduct:accountToken:)
    public func purchaseProduct(_ identifier: String, accountToken: String) {
        guard let token = UUID(uuidString: accountToken) else {
            failure("Sign in before purchasing.")
            return
        }
        start()
        operation { [weak self] in
            guard let self else { return }
            do {
                let product: Product
                if let cached = self.products[identifier] {
                    product = cached
                } else if let found = try await Product.products(for: [identifier]).first {
                    product = found
                } else {
                    self.failure("This item is unavailable.")
                    return
                }
                guard product.type == .nonConsumable else {
                    self.failure("Unsupported product type.")
                    return
                }
                let result = try await product.purchase(options: [.appAccountToken(token)])
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let verified):
                    switch verified {
                    case .verified(let transaction):
                        guard transaction.productID == identifier,
                              transaction.appAccountToken == token else {
                            self.failure("Purchase account could not be verified.")
                            return
                        }
                        self.deliver(verified)
                    case .unverified:
                        self.failure("Purchase could not be verified.")
                    }
                case .pending:
                    self.emit("purchase_received", ["product_id": identifier, "state": "pending"])
                case .userCancelled:
                    self.emit("purchase_received", ["product_id": identifier, "state": "cancelled"])
                @unknown default:
                    self.failure("Purchase did not complete.")
                }
            } catch {
                self.failure("Purchase did not complete. Please try again.")
            }
        }
    }

    // Explicit restore button only: AppStore.sync may ask for authentication.
    @objc public func restorePurchases() {
        start()
        operation { [weak self] in
            guard let self else { return }
            do {
                try await AppStore.sync()
                for await result in Transaction.currentEntitlements {
                    guard !Task.isCancelled else { return }
                    self.deliver(result)
                }
                guard !Task.isCancelled else { return }
                self.emit("restore_finished", [:])
            } catch {
                self.failure("Purchases could not be restored. Please try again.")
            }
        }
    }

    // Called only after the server's durable, account-bound fulfillment reply.
    @objc(finishTransaction:)
    public func finishTransaction(_ identifier: String) {
        guard let id = UInt64(identifier), let transaction = unfinished[id] else {
            failure("Transaction is not awaiting completion.")
            return
        }
        operation { [weak self] in
            await transaction.finish()
            guard !Task.isCancelled, let self else { return }
            self.unfinished.removeValue(forKey: id)
        }
    }

    private func deliver(_ result: VerificationResult<Transaction>) {
        guard !Task.isCancelled else { return }
        switch result {
        case .verified(let transaction):
            guard transaction.productType == .nonConsumable else { return }
            unfinished[transaction.id] = transaction
            var payload: [String: Any] = [
                "product_id": transaction.productID,
                // String avoids loss of precision in JSON/GDScript doubles.
                "transaction_id": String(transaction.id),
                "original_transaction_id": String(transaction.originalID),
                "signed_transaction": result.jwsRepresentation,
                "state": transaction.revocationDate == nil ? "purchased" : "refunded"
            ]
            if let token = transaction.appAccountToken {
                payload["app_account_token"] = token.uuidString.lowercased()
            }
            emit("purchase_received", payload)
        case .unverified:
            failure("Purchase signature could not be verified.")
        }
    }

    private func operation(_ work: @escaping @MainActor () async -> Void) {
        let id = UUID()
        operations[id] = Task { [weak self] in
            await work()
            self?.operations.removeValue(forKey: id)
        }
    }

    private func failure(_ message: String) { emit("purchase_failed", message) }

    private func emit(_ event: String, _ value: Any) {
        guard eventHandler != nil,
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return }
        eventHandler?(event, text)
    }
}
