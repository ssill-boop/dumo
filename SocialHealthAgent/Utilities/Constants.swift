import Foundation

/// App-wide configuration constants
enum Constants {
    /// Default price for events (admin-configurable via UserDefaults)
    static var defaultEventPrice: Decimal {
        get {
            let storedPrice = UserDefaults.standard.double(forKey: "eventPrice")
            return storedPrice > 0 ? Decimal(storedPrice) : 20.00
        }
        set {
            UserDefaults.standard.set(Double(truncating: newValue as NSNumber), forKey: "eventPrice")
        }
    }

    /// Minimum conversation duration before user can proceed (5 minutes in seconds)
    static let minimumConversationDuration: TimeInterval = 300 // 5 minutes

    /// OpenAI API endpoint
    static let openAIEndpoint = "https://api.openai.com/v1/chat/completions"

    /// OpenAI model to use
    static let openAIModel = "gpt-4"

    /// System prompt for the conversational voice agent
    static let conversationalAgentPrompt = """
    You are a warm, empathetic social connection coach. Your goal is to have a
    natural 5-minute conversation to understand someone's social health and needs.

    Ask about:
    - What their social life looks like now
    - What they enjoy doing
    - What values matter to them
    - Any life transitions they're navigating
    - What kind of connections they're seeking

    Be genuinely curious. Ask follow-ups. Make them feel heard. Don't interrogate—
    have a real conversation. If they share something vulnerable, validate it.

    Keep responses concise (2-3 sentences) so there's room for back-and-forth.

    Start by warmly greeting them and asking an open-ended question about their social life.
    """

    /// System prompt for generating activity recommendations
    static let activityGeneratorPrompt = """
    Based on this conversation transcript, generate ONE hyper-specific, niche group
    activity that would genuinely excite this person.

    Make it:
    - Small and intimate (4-8 people max)
    - Highly specific to their values/interests/life phase
    - In a real SF Bay Area location
    - Happening within the next 2 weeks
    - Something that creates genuine connection opportunity

    Return ONLY valid JSON matching this schema:
    {
      "title": "string",
      "description": "string (2-3 sentences)",
      "targetAudience": "string (who's invited)",
      "location": "string",
      "datetime": "string",
      "vibe": "string"
    }

    No markdown, no explanation, just the JSON object.
    """
}

/// App color palette - warm, welcoming, intimate
enum AppColors {
    static let primary = "SageGreen"       // Calming sage green
    static let secondary = "WarmNeutral"   // Warm beige/cream
    static let accent = "SoftCoral"        // Soft coral for CTAs
    static let background = "CreamWhite"   // Off-white background
    static let text = "WarmCharcoal"       // Warm dark gray for text
}
