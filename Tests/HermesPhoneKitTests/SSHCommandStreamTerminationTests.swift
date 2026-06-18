import NIOCore
import Testing

@testable import HermesPhoneKit

struct SSHCommandStreamTerminationTests {
    @Test
    func normalRemoteChannelEndingsAreExpectedAfterVerifiedCompletion() {
        #expect(SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(ChannelError.inputClosed))
        #expect(SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(ChannelError.eof))
        #expect(SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(ChannelError.alreadyClosed))
        #expect(SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(ChannelError.ioOnClosedChannel))
        #expect(SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(ChannelError.outputClosed))
    }

    @Test
    func unrelatedFailuresRemainFatal() {
        #expect(!SSHCommandStreamTermination.isExpectedAfterRemoteCompletion(TestFailure.brokenTransport))
    }

    private enum TestFailure: Error {
        case brokenTransport
    }
}
