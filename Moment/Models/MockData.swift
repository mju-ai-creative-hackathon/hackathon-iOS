import Foundation

enum MockData {
    static func avatar(_ n: Int) -> URL { URL(string: "https://i.pravatar.cc/150?img=\(n)")! }
    static func photo(_ seed: String) -> URL { URL(string: "https://picsum.photos/seed/\(seed)/1080/1080")! }

    static let me = User(username: "mju_dev", avatarURL: avatar(12))

    static let users: [User] = [
        User(username: "jiwoo.kim", avatarURL: avatar(5)),
        User(username: "seoul_eats", avatarURL: avatar(15), isVerified: true),
        User(username: "minho_travel", avatarURL: avatar(33)),
        User(username: "yuna.daily", avatarURL: avatar(45)),
        User(username: "mju_official", avatarURL: avatar(60), isVerified: true),
        User(username: "dohyun_cam", avatarURL: avatar(51)),
        User(username: "hana.art", avatarURL: avatar(47)),
        User(username: "coffee_lab", avatarURL: avatar(68)),
    ]

}
