import Foundation

enum AsyncOperationErrorPolicy {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let bridgedError = error as NSError
        return bridgedError.domain == "Swift.CancellationError" && bridgedError.code == 1
    }

    static func userFacingMessage(for error: Error) -> String? {
        guard !isCancellation(error) else { return nil }
        return error.localizedDescription
    }
}
