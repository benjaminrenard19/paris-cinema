import Foundation

/// Where the app downloads its films. Claude updates this file every Tuesday evening.
enum Feed {
    static let repo = "benjaminrenard19/paris-cinema"
    static let url = URL(string: "https://raw.githubusercontent.com/\(repo)/main/data/paris-cinema.json")!
    static let page = URL(string: "https://github.com/\(repo)")!
}
