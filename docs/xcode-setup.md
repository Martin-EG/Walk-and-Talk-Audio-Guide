# Xcode setup (day 1)

Goal: a SwiftUI app in `ios/` that plays a bundled `hello.wav` on a physical iPhone.

## 1. Create the project

1. Xcode, then File > New > Project.
2. Pick iOS > App, then Next.
3. Fill in:
   - Product Name: `WalkAndTalk`
   - Team: your Apple ID (Add Account... if empty; a free account works for your own device)
   - Organization Identifier: e.g. `com.martinespericueta`
   - Interface: SwiftUI
   - Language: Swift
   - Testing System / Storage: None
4. Next, choose the `ios/` folder in this repo. **Uncheck "Create Git repository"** (the repo already exists). Create.

You get `ios/WalkAndTalk/WalkAndTalk.xcodeproj` plus a `WalkAndTalk/` source folder.
Delete `ios/.gitkeep` afterwards.

## 2. Set iOS 17 minimum

1. Click the blue `WalkAndTalk` project icon at the top of the navigator.
2. Select the **WalkAndTalk** target, General tab.
3. Minimum Deployments > iOS: `17.0`.

## 3. Background Modes

1. Same target, **Signing & Capabilities** tab.
2. Click **+ Capability**, add **Background Modes**.
3. Check **Audio, AirPlay, and Picture in Picture** and **Location updates**.

Why: iOS suspends apps when the screen locks. These modes let the app keep tracking location and play audio in your pocket.

## 4. Location usage descriptions

New Xcode projects have no Info.plist file; the keys live in the target's **Info** tab.

1. Target, **Info** tab, Custom iOS Target Properties.
2. Hover any row, click **+**, add each key (start typing the readable name):

| Key | Value |
| --- | --- |
| Privacy - Location When In Use Usage Description (`NSLocationWhenInUseUsageDescription`) | Walk-and-Talk uses your location to play the story for each stop when you arrive. |
| Privacy - Location Always and When In Use Usage Description (`NSLocationAlwaysAndWhenInUseUsageDescription`) | Walk-and-Talk keeps using your location while your phone is locked so stories play during your walk. |

iOS shows these strings in the permission prompt. Missing strings = the app crashes when it asks for location.

## 5. Add the code and audio

1. Replace the generated `WalkAndTalk/ContentView.swift` contents with `ios/ContentView.swift` from this repo, then delete `ios/ContentView.swift` so there's one copy.
2. Drag `tests/hello.wav` from Finder into the `WalkAndTalk` group in Xcode's navigator.
   - Check **Copy items if needed**.
   - Check target **WalkAndTalk** under "Add to targets". (This is what puts it in the app bundle.)
3. Verify: target, Build Phases, Copy Bundle Resources lists `hello.wav`.

## 6. Run on your iPhone

1. iPhone: Settings > Privacy & Security > **Developer Mode** on (restart when asked). The option appears after you first plug the phone into a Mac with Xcode.
2. Plug in the phone, unlock it, tap Trust.
3. Xcode toolbar: pick your iPhone as the run destination. Press Cmd+R.
4. First run with a free account: iPhone shows "Untrusted Developer". Go to Settings > General > VPN & Device Management, tap your Apple ID, Trust. Run again.
5. Tap **Play hello**. Turn the volume up; the silent switch doesn't matter (`.playback` category).

## Troubleshooting

- "hello.wav not found in app bundle": the file isn't in Copy Bundle Resources (step 5.3).
- Signing error: Signing & Capabilities, check "Automatically manage signing" and that Team is set. Change the bundle identifier if it says it's taken.
