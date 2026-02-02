# Social Health Voice Agent - Setup Guide

Welcome! This guide will help you set up the app in Xcode, even if you've never coded before.

## What You'll Need

1. **A Mac computer** (required for iOS development)
2. **Xcode** - Apple's free development tool
3. **An OpenAI API key** - for the AI conversation features

---

## Step 1: Install Xcode

1. Open the **App Store** on your Mac
2. Search for "Xcode"
3. Click **Get** and then **Install** (it's free but large ~12GB)
4. Wait for it to download and install

---

## Step 2: Get an OpenAI API Key

1. Go to [platform.openai.com](https://platform.openai.com)
2. Sign up or log in
3. Go to **API Keys** in the left sidebar
4. Click **Create new secret key**
5. Copy the key and save it somewhere safe (you'll need it later!)

Note: OpenAI charges for API usage. For testing, it typically costs a few cents per conversation.

---

## Step 3: Create the Xcode Project

1. Open **Xcode**
2. Click **Create a new Xcode project**
3. Select **iOS** at the top
4. Choose **App** and click **Next**
5. Fill in:
   - Product Name: `SocialHealthAgent`
   - Team: Your Apple ID (or skip for now)
   - Organization Identifier: `com.yourname` (any identifier works)
   - Interface: **SwiftUI**
   - Language: **Swift**
6. Click **Next** and choose where to save it
7. Click **Create**

---

## Step 4: Add the Code Files

1. In Xcode, look at the left sidebar (the Project Navigator)
2. Delete the default `ContentView.swift` file that Xcode created
3. Right-click on the `SocialHealthAgent` folder and choose **Add Files to "SocialHealthAgent"...**
4. Navigate to the `SocialHealthAgent` folder from this repo
5. Select all the folders: `App`, `Features`, `Services`, `Models`, `Utilities`
6. Make sure **"Copy items if needed"** is checked
7. Make sure **"Create groups"** is selected
8. Click **Add**

---

## Step 5: Add Your API Key

1. Open `Services/OpenAIService.swift`
2. Find this line near the top:
   ```swift
   return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "YOUR_API_KEY_HERE"
   ```
3. Replace `YOUR_API_KEY_HERE` with your actual OpenAI API key:
   ```swift
   return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "sk-your-actual-key-here"
   ```

---

## Step 6: Configure Permissions

1. In Xcode, click on the project name at the very top of the left sidebar
2. Select your target under "TARGETS"
3. Click the **Info** tab
4. Under "Custom iOS Target Properties", add these two entries:
   - Key: `NSMicrophoneUsageDescription`
     Value: `We need microphone access for voice conversations with our AI coach.`
   - Key: `NSSpeechRecognitionUsageDescription`
     Value: `We use speech recognition to understand what you're saying.`

---

## Step 7: Run the App

1. At the top of Xcode, click the device selector (shows "iPhone 15" or similar)
2. Choose a simulator (like "iPhone 15 Pro")
3. Click the **Play button** (▶) or press `Cmd + R`
4. Wait for the app to build and launch in the simulator

**Note:** Voice features work best on a real device. To test on your iPhone:
1. Connect your iPhone with a cable
2. Select your iPhone in the device dropdown
3. You may need to trust your computer on your phone
4. Click Play to build and run

---

## Troubleshooting

### "No such module" errors
Make sure all files are properly added to the project and the folders show as groups (folder icons) not references (blue folder icons).

### Speech recognition not working in Simulator
The iOS Simulator has limited speech support. Test on a real device for the full experience.

### API errors
- Make sure your API key is correct
- Check that you have credits in your OpenAI account
- Look at the Xcode console (bottom panel) for error messages

### Build errors
- Make sure you're using Xcode 15 or later
- Clean the build: Product → Clean Build Folder (Cmd + Shift + K)
- Then build again: Cmd + B

---

## Project Structure

```
SocialHealthAgent/
├── App/
│   ├── SocialHealthAgentApp.swift    # App entry point
│   └── ContentView.swift             # Main navigation
├── Features/
│   ├── Welcome/                      # Welcome screen
│   ├── VoiceAgent/                   # Voice conversation
│   ├── ActivityRecommendation/       # Activity card
│   └── ThankYou/                     # Confirmation screen
├── Services/
│   ├── SpeechService.swift           # Voice input/output
│   ├── OpenAIService.swift           # AI communication
│   └── SessionManager.swift          # Session tracking
├── Models/
│   ├── GeneratedActivity.swift       # Activity data model
│   └── UserSession.swift             # Session data model
└── Utilities/
    └── Constants.swift               # App configuration
```

---

## Next Steps

Once the app is running:

1. **Test the flow**: Go through the welcome → conversation → activity → thank you flow
2. **Iterate on prompts**: Edit the AI prompts in `Constants.swift` to improve responses
3. **Adjust the UI**: Modify colors and styling in the view files
4. **Test with real users**: Share via TestFlight for feedback

---

## Need Help?

- **Xcode Help**: Help → Xcode Help (in the menu bar)
- **SwiftUI Tutorials**: [Apple's SwiftUI tutorials](https://developer.apple.com/tutorials/swiftui)
- **OpenAI Docs**: [platform.openai.com/docs](https://platform.openai.com/docs)

Good luck with your prototype! 🎉
