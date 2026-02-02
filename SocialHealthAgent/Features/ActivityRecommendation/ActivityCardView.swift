import SwiftUI

/// Displays the personalized activity recommendation
/// This is the "payoff" screen showing the AI-generated event
struct ActivityCardView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var showCard = false

    private var activity: GeneratedActivity {
        sessionManager.session.generatedActivity ?? GeneratedActivity.sample
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "F5F0EB"), Color(hex: "E8E0D5")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("We found something for you")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "7A9E7E"))

                    Text("Your Perfect Match")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "3D3D3D"))
                }
                .padding(.top, 40)
                .opacity(showCard ? 1 : 0)
                .offset(y: showCard ? 0 : -20)

                // Activity Card
                VStack(alignment: .leading, spacing: 20) {
                    // Title and vibe
                    VStack(alignment: .leading, spacing: 8) {
                        Text(activity.title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "3D3D3D"))
                            .lineLimit(3)

                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text(activity.vibe)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "7A9E7E"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "7A9E7E").opacity(0.15))
                        .cornerRadius(8)
                    }

                    // Description
                    Text(activity.description)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "555555"))
                        .lineSpacing(4)

                    Divider()
                        .background(Color(hex: "E0E0E0"))

                    // Who's invited
                    DetailRow(
                        icon: "person.3.fill",
                        title: "Who's invited",
                        value: activity.targetAudience
                    )

                    // When
                    DetailRow(
                        icon: "calendar",
                        title: "When",
                        value: activity.datetime
                    )

                    // Where
                    DetailRow(
                        icon: "mappin.circle.fill",
                        title: "Where",
                        value: activity.location
                    )

                    Divider()
                        .background(Color(hex: "E0E0E0"))

                    // Price
                    HStack {
                        Text("Price per person")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "666666"))

                        Spacer()

                        Text(sessionManager.formattedPrice)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "3D3D3D"))
                    }
                }
                .padding(24)
                .background(Color.white)
                .cornerRadius(24)
                .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 8)
                .padding(.horizontal, 20)
                .opacity(showCard ? 1 : 0)
                .offset(y: showCard ? 0 : 40)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Yes button
                    Button(action: {
                        sessionManager.recordActivityResponse(accepted: true)
                        sessionManager.showThankYou()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            Text("Yes, I'd attend (\(sessionManager.formattedPrice))")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(hex: "7A9E7E"))
                        .cornerRadius(16)
                    }

                    // No button
                    Button(action: {
                        sessionManager.recordActivityResponse(accepted: false)
                        sessionManager.showThankYou()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 18))
                            Text("Not for me")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "888888"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color(hex: "F0F0F0"))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .opacity(showCard ? 1 : 0)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
                showCard = true
            }
        }
    }
}

/// A row showing event details
struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "7A9E7E"))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "999999"))

                Text(value)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "3D3D3D"))
            }
        }
    }
}

#Preview {
    ActivityCardView(sessionManager: SessionManager())
}
