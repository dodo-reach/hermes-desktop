import Foundation
import NIOCore

enum SSHCommandStreamTermination {
    static func isExpectedAfterRemoteCompletion(_ error: Error) -> Bool {
        if let channelError = error as? ChannelError {
            switch channelError {
            case .inputClosed, .eof, .alreadyClosed, .ioOnClosedChannel, .outputClosed:
                return true
            default:
                return false
            }
        }

        return false
    }

    static func diagnosticName(for error: Error) -> String {
        "\(String(reflecting: type(of: error))): \(String(describing: error))"
    }
}
