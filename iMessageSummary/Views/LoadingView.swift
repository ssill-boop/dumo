import SwiftUI

struct LoadingView: View {
    let phase: String
    let contactDisplay: String?

    var body: some View {
        VStack(spacing: 12) {
            if let contactDisplay, !contactDisplay.isEmpty {
                Text(contactDisplay)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            ProgressView()
                .controlSize(.small)
            Text(phase)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
