import Foundation

public struct SystemDependency: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let expectedPath: String
    public let isPresent: Bool

    public init(id: String, displayName: String, expectedPath: String, isPresent: Bool) {
        self.id = id
        self.displayName = displayName
        self.expectedPath = expectedPath
        self.isPresent = isPresent
    }
}
