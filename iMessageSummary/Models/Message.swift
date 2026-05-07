import Foundation

struct Message: Identifiable, Hashable {
    let rowID: Int64
    let date: Date
    let isFromMe: Bool
    let text: String

    var id: Int64 { rowID }
}
