import Foundation
import LocalAuthentication

class BiometricAuth {
    /// Authenticate the user. Calls completion with true on success, false on failure.
    /// Uses .deviceOwnerAuthentication policy (Touch ID with password fallback).
    /// maxRetries: number of auth attempts before giving up (default 3)
    /// timeout: seconds before auto-deny (default 60)
    func authenticate(
        reason: String,
        maxRetries: Int = 3,
        timeout: TimeInterval = 60,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let lock = NSLock()
        var completed = false

        func safeComplete(_ success: Bool, _ message: String?) {
            lock.lock()
            guard !completed else {
                lock.unlock()
                return
            }
            completed = true
            lock.unlock()
            DispatchQueue.main.async {
                completion(success, message)
            }
        }

        // Set up timeout
        let timeoutWork = DispatchWorkItem {
            safeComplete(false, "Authentication timed out")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        func attempt(remaining: Int) {
            let context = LAContext()
            var error: NSError?

            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                timeoutWork.cancel()
                let message = error?.localizedDescription ?? "Biometric authentication not available"
                safeComplete(false, message)
                return
            }

            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, evaluateError in
                if success {
                    timeoutWork.cancel()
                    safeComplete(true, nil)
                } else {
                    let retriesLeft = remaining - 1
                    if retriesLeft > 0 {
                        attempt(remaining: retriesLeft)
                    } else {
                        timeoutWork.cancel()
                        let message = evaluateError?.localizedDescription ?? "Authentication failed"
                        safeComplete(false, message)
                    }
                }
            }
        }

        attempt(remaining: maxRetries)
    }
}
