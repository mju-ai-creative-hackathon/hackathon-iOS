import Foundation

struct User: Identifiable, Hashable {
    let id: UUID = UUID()
    let username: String
    let avatarURL: URL
    var isVerified: Bool = false
}

