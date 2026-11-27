import Foundation

/// Where the app downloads its films. Claude updates this file every Tuesday evening.
enum Feed {
    static let repo = "benjaminrenard19/paris-cinema"
    static let url = URL(string: "https://raw.githubusercontent.com/\(repo)/main/data/paris-cinema.json")!
    static let page = URL(string: "https://github.com/\(repo)")!
    /// Sloth Cinema in the browser (docs/ on GitHub Pages), to share until the app is on TestFlight or the App Store.
    static let web = URL(string: "https://benjaminrenard19.github.io/paris-cinema/")!
}
