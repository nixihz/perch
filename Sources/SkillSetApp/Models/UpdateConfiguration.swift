import Foundation

struct UpdateConfiguration {
    let feedURL: URL
    let publicKey: Data

    init?(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String,
              !feed.contains("$"),
              feed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: feed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              let key = info["SUPublicEDKey"] as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32 else { return nil }
        feedURL = url
        publicKey = bytes
    }
}
