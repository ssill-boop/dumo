import Foundation

struct Message: Identifiable, Hashable {
    let rowID: Int64
    let date: Date
    let isFromMe: Bool
    let text: String
    /// Populated for group-chat fetches so the prompt can attribute who said
    /// what. Always nil for 1:1 fetches and for outgoing messages.
    let senderHandleID: String?

    init(rowID: Int64, date: Date, isFromMe: Bool, text: String, senderHandleID: String? = nil) {
        self.rowID = rowID
        self.date = date
        self.isFromMe = isFromMe
        self.text = text
        self.senderHandleID = senderHandleID
    }

    var id: Int64 { rowID }
}
