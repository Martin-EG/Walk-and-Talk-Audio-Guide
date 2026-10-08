# Walk-and-Talk Audio Guide — MVP

Oct 7, 2026 · @Martin

## Overview

An iOS app that narrates the places around you while you walk, so the phone stays in your pocket. Before the walk, it downloads nearby points of interest and uses open-weight models to write and voice a short story for each one. During the walk, it plays each story when you get close, fully offline.

**Deadline:** Oct 11, 2026, 11:59 PM PDT, the same as Mexicali time. The submission is a DEV post, and writing quality is weighted most, so the plan builds on the Mac first and saves Sunday for the write-up.

**Touch Grass fit:** the open model and open TTS produce every word the user hears, and the screen is used only to start the tour.

**The demo succeeds if:**

- A tour of at least 8 stops downloads while online.
- With airplane mode on and the phone pocketed, stories play automatically as you walk past each stop.
- No story repeats, and audio keeps playing with the screen locked.
- All text and audio comes from open models running locally.

## MVP scope

With four days, the open models run on your Mac to build the tour pack, and the iPhone app only plays it back offline. Running the model on the iPhone moves to stretch.

| Priority | Feature |
| --- | --- |
| Must | Mac pipeline fetches OSM points of interest along a chosen route |
| Must | Fetch a Wikipedia summary per point when one exists |
| Must | Gemma, run locally with Ollama, writes a 30–45 second story per point from those facts only |
| Must | Open TTS (Piper or Kokoro) voices each story; output is a tour pack of JSON plus audio |
| Must | iOS app plays a stop's audio when you come within its trigger radius, fully offline |
| Must | Background location and audio, working with the screen locked |
| Must | You walk the route for real and write about how it went |
| Stretch | Run Gemma on the iPhone with MLX Swift, so the whole pipeline is on-device |
| Stretch | Lock-screen now-playing controls and tone presets |
| Out | Voice Q&A, accounts, backend, map routing, Android |

## System design

&#91;embedded content: System design · prep phase online, walk phase offline\]

The network is only needed during prep: once the tour pack is bundled in the app, the walk loop reads from the phone and needs no signal. The two highlighted boxes are the open models, and they are what makes the app work.

## Tech stack

| Layer | Choice | Why |
| --- | --- | --- |
| Tour pipeline | Python scripts on your Mac | Fastest to build and debug in four days |
| LLM | Gemma, the size your Mac runs comfortably, via Ollama | Open weights, runs locally, free, and qualifies for Best Use of Gemma |
| TTS | Piper or Kokoro, run locally | Open, free, works offline |
| Points of interest | OpenStreetMap via the Overpass API | Open data |
| Place text | Wikipedia REST summary endpoint | Open data |
| Tour pack | tour.json plus one audio file per stop, bundled into the app | No server needed |
| Walk app | SwiftUI, CoreLocation, AVFoundation | Native background location and audio |
| Stretch | MLX Swift running Gemma on the iPhone | Whole pipeline on-device |

## Setup

Do this tonight (Wednesday) so Thursday starts on the pipeline, not installs. Check each tool's current README for install steps.

**Accounts and repo**

- [x] Create the public GitHub repo now: the rules require the project to start inside the Oct 5–11 window
- [x] DEV account ready, and the challenge's submission template opened so you know its sections

**Mac pipeline**

- [x] Ollama installed and one Gemma prompt answered locally
- [x] Python environment with requests and your TTS package (`.venv`, Python 3.9, `requests` + `piper-tts`)
- [x] One test sentence rendered to audio and played (`tests/hello.wav`, "Hello from the trail")

**Xcode project**

- [x] New SwiftUI app, iOS 17+, running on your physical iPhone (`ios/WalkAndTalk`, plays bundled hello.wav)
- [x] Background Modes: Audio, and Location updates
- [x] Info.plist: location usage descriptions for "when in use" and "always"

**Models (download on your Mac first)**

- [x] Gemma pulled in Ollama, at the size your Mac runs comfortably (`gemma3:4b`, 3.3 GB, ~2.5–5 s per short reply)
- [x] One Piper or Kokoro voice for local use, in English or Spanish to match your demo (Piper `en_US-lessac-medium`)
- [ ] Stretch only: a 4-bit Gemma in MLX format for running on the iPhone

**Setup results (Wed Oct 7)**

- `python pipeline/check_env.py`: 4/4 PASS (LLM, TTS, Overpass, Wikipedia)
- Settings live in `pipeline/config.py`; test point is still a placeholder (SF Ferry Building) until the demo route is picked
- Xcode walkthrough saved in `docs/xcode-setup.md`
- First commit pushed (`fddaf69`)

**Repo structure**

- `pipeline/` — fetch\_pois.py, fetch\_wiki.py, write\_stories.py (Gemma), narrate.py (TTS), build\_tour.py
- `tours/<route>/` — tour.json plus the audio files
- `ios/` — the SwiftUI walk app: TourLoader, LocationTracker, ProximityEngine, AudioPlayer, WalkView
- `README.md` — what it is, how to run it, models, licenses, credits

## Build sequence

Four days: build on Thursday and Friday, walk on Saturday, write on Sunday. Each checklist is the must-have bar for that day.

### Thu Oct 8 — Tour pipeline on the Mac

- [ ] Pick the demo route: 1–2 km with at least 8 named places, and check its OSM and Wikipedia coverage
- [ ] fetch\_pois.py and fetch\_wiki.py: get the places and summaries, rank them, keep 8–12 stops
- [ ] write\_stories.py: Gemma prompt for 80–110 words, second person, facts from the input only
- [ ] narrate.py: one audio file per story
- [ ] build\_tour.py writes the tour pack; listen to every story and fix the prompt
- [ ] Commit and push

### Fri Oct 9 — Walk app on the iPhone

- [ ] Load the tour pack from the app bundle
- [ ] LocationTracker with background updates and a distance filter
- [ ] ProximityEngine: nearest unplayed stop within 30–40 m, confirmed by two consecutive GPS fixes
- [ ] AudioPlayer: one story at a time, never overlapping, each marked played
- [ ] One screen: Start walk, current stop, stops left
- [ ] Quick test around the block with the screen locked

### Sat Oct 10 — Walk it for real

- [ ] Walk the full route in airplane mode, early morning or after sunset to avoid the heat
- [ ] Fix bugs, then tune the trigger radius and story length
- [ ] Record the demo video
- [ ] Take photos and notes on how the walk went; the challenge gives bonus points for this
- [ ] Stretch only if everything above is done: Gemma on the iPhone with MLX Swift

### Sun Oct 11 — Write and submit (due 11:59 PM PDT)

- [ ] README: what it is, how to run the pipeline and the app, models, licenses, credits
- [ ] Draft the DEV post in the template (outline below), with the diagram and photos
- [ ] Upload the video and check the link
- [ ] Publish by early evening, not at 11:50 PM

## Daily prompts

Paste these into your AI coding tool at the start of each session. Start every prompt with the project context block below, then work through the acceptance checklist before calling the day done. Replace anything in \[brackets\].

**Project context (paste first, every day)**

```text
Project: Walk-and-Talk, an offline audio walking tour for the DEV "Touch Grass" challenge. Deadline: Oct 11, 11:59 PM PDT.

How it works: Python scripts on my Mac fetch points of interest from OpenStreetMap (Overpass API) and Wikipedia summaries. Gemma, running locally through Ollama, writes a short story per stop. Piper or Kokoro, running locally, voices each story. The output is a tour pack: tour.json plus one audio file per stop. A SwiftUI iOS app bundles the pack and plays each story when I walk within range, fully offline.

Rules:
- Only open models generate story text and audio. No paid or closed AI APIs, no backend, no accounts.
- Keep code simple and readable. Favor one clear file over clever abstractions.
- I'm a JavaScript/React developer learning Swift: explain Swift-specific choices in one or two lines.
- Before writing code, tell me your plan in a few bullets. After, tell me exactly how to run and verify it.

Repo layout: pipeline/ (Python), tours/<route>/ (tour packs), ios/ (Xcode project), docs/ (notes, field test), README.md
```

### Wed night — Setup prompt

```text
[Project context]

Today's goal: prove every tool works end to end before tomorrow. The GitHub repo already exists and is cloned at [path].

Do this:
1. Create the repo layout from the context, a README stub, and a .gitignore for Python, Xcode, and macOS.
2. Create pipeline/config.py with the Ollama model name ([gemma model tag]), TTS engine and voice, default language, and default trigger radius (35 m).
3. Create pipeline/requirements.txt and pipeline/check_env.py. The script must:
   - Send one prompt to Gemma through Ollama's local HTTP API and print the reply and the seconds taken.
   - Render "Hello from the trail" with the TTS engine to tests/hello.wav and print the file's duration.
   - Run one Overpass query and one Wikipedia REST summary request for [lat, lon] and print the number of places and the article title.
   - Print a clear PASS or FAIL line for each check.
4. Walk me step by step through creating the Xcode project in ios/: SwiftUI app, iOS 17, Background Modes (Audio, Location updates), and Info.plist location usage descriptions.
5. Give me a ContentView with one button that plays a bundled hello.wav with AVAudioPlayer.

Acceptance checklist:
- [x] python pipeline/check_env.py prints PASS for LLM, TTS, Overpass, and Wikipedia
- [x] hello.wav plays on the Mac and sounds clear
- [x] The iOS app runs on my physical iPhone and plays hello.wav
- [x] Background Modes and location strings are set in the project
- [x] First commit pushed
```

### Thu Oct 8 — Tour pipeline prompt

```text
[Project context]

Today's goal: one command that builds a complete tour pack for my demo route. Center: [lat, lon]. Radius: [meters]. Language: [en or es].

Build these in pipeline/, one step per file:
1. fetch_pois.py: Overpass query for named places with tags such as historic=*, tourism=attraction|museum|artwork|viewpoint, amenity=place_of_worship|theatre, leisure=park, or any feature with a wikipedia or wikidata tag. Save id, name, lat, lon, and tags to stops_raw.json.
2. fetch_wiki.py: for each place, use its wikipedia tag if present, otherwise search by name and keep only a confident match. Fetch the REST summary and store the extract and URL. Cache every response on disk so reruns are fast.
3. rank.py: score places (Wikipedia text, historic tags, spread along the route), drop duplicates within 25 m, keep the best 8–12, and order them as a walkable loop (nearest-neighbor is fine).
4. write_stories.py: call Gemma through Ollama with these rules:
   - 80–110 words, second person, present tense
   - Open with something the listener can see from where they stand
   - Include one surprising fact
   - Use ONLY the facts provided; never add dates, numbers, or names that aren't in the input
   - If the facts are thin, describe what's visible and keep it short instead of inventing
   - Retry once if the word count is out of range
5. narrate.py: render each story with the TTS engine and convert to .m4a (AAC) with ffmpeg to keep files small.
6. build_tour.py: run steps 1–5 and write tours/[route]/tour.json with route name, language, and per stop: id, name, lat, lon, radius_m (35), audio file, duration_s, story text, source URLs. Log each step's time to tours/[route]/build_log.txt; I'll quote these numbers in my post.

Also add pipeline/validate_tour.py that checks tour.json against these rules and fails loudly.

Acceptance checklist:
- [ ] python pipeline/build_tour.py --route [name] --lat --lon --radius --lang builds the pack from scratch
- [ ] 8–12 stops, no two within 25 m of each other
- [ ] Every story is 80–110 words
- [ ] I've read every story against its source and none contains an invented fact
- [ ] Every audio file plays, is under 60 seconds, and sounds clear
- [ ] validate_tour.py passes
- [ ] A rerun uses the cache and finishes noticeably faster
- [ ] build_log.txt has timings for every step
- [ ] Committed and pushed
```

### Fri Oct 9 — Walk app prompt

```text
[Project context]

Today's goal: the iPhone plays each story once as I walk up to it, offline, with the screen locked.

Input: tours/[route]/tour.json and its audio files. Here is a sample of tour.json: [paste 2 stops]

Build these in ios/:
1. Models and TourLoader: decode tour.json from the app bundle. Add the tour folder as a folder reference so the audio ships with the app.
2. LocationTracker (CLLocationManager, @Observable): request Always authorization, allowsBackgroundLocationUpdates = true, pausesLocationUpdatesAutomatically = false, best accuracy, distanceFilter of 5 m.
3. ProximityEngine as plain Swift with no UIKit or CoreLocation dependency, so it's easy to test: ignore fixes with horizontal accuracy worse than 25 m; find the nearest unplayed stop within its radius; require 2 consecutive qualifying fixes before triggering; trigger each stop once.
4. AudioPlayer: AVAudioSession category .playback, active for the whole walk; a queue so stories never overlap; mark each stop played when its audio starts.
5. WalkView: Start and Stop walk buttons, the current stop's name, "X of N stops", and the last story's text in large type. Add a debug toggle showing distance to the nearest stop and GPS accuracy.
6. A GPX file through all the stops for Xcode's location simulation.
7. Unit tests for ProximityEngine: inside the radius, GPS jitter at the edge, an already-played stop, two stops close together, and a poor-accuracy fix.

Acceptance checklist:
- [ ] All ProximityEngine unit tests pass
- [ ] Simulated GPX walk plays every stop once, in order, with no overlapping audio
- [ ] On my iPhone in airplane mode with the screen locked, a stop plays when I walk up to it
- [ ] Stop walk ends both audio and location updates
- [ ] No crash or audio glitch in a 20-minute session
- [ ] Committed and pushed
```

### Sat Oct 10 — Field test prompt

Use this prompt in two parts: before the walk, and after you come back.

```text
[Project context]

Today's goal: walk the full route for real, fix what breaks, and capture material for the post.

Before I leave:
1. Add a trigger log to the app: each trigger writes time, stop id, distance, and GPS accuracy to a file, plus a button that exports it with the share sheet.
2. Make me a field-test sheet in docs/field-test.md with one row per stop: name, played (yes/no), trigger timing (early, right, late), audio quality, story accuracy, notes. Add an "after the walk" section: total time, battery used, best moment, what surprised me, what broke.
3. Give me a 6-shot list for a 90-second demo video: the hook, the tour building on the Mac, airplane mode turned on, pocketing the phone, walking while 2–3 stories play, and the system diagram.

After the walk (I'll paste my notes and the exported log):
4. Diagnose every missed, early, or late trigger and propose specific changes to radius, accuracy filter, or the 2-fix rule.
5. For stories I flagged, suggest prompt fixes and regenerate only those stops.
6. Apply the fixes and tell me which 3 stops to re-test.

Acceptance checklist:
- [ ] Full route walked in airplane mode; every stop played, or I know why it didn't
- [ ] Trigger log exported and saved to docs/field-test/
- [ ] Field-test sheet filled in while it's fresh
- [ ] Fixes applied and re-tested on at least 3 stops
- [ ] Raw footage for every shot and at least 5 photos
- [ ] Stretch, only if all of the above is done: Gemma generating one story on the iPhone with MLX Swift
```

### Sun Oct 11 — Write-up prompt

```text
[Project context]

Today's goal: publish the DEV submission. Writing quality is the most heavily weighted judging criterion, so the post is the main deliverable today.

I'll paste: my field-test sheet and notes, build_log.txt timings, 2–3 sample stories, the repo URL, and the video link.

1. README.md: what it is in two sentences, a screenshot or GIF, the architecture diagram, quick start for the pipeline and the iOS app, models and data used with their licenses (Gemma terms of use, the TTS voice license, OpenStreetMap ODbL attribution, Wikipedia CC BY-SA), credits, and a "Commits after the deadline" section.
2. A DEV post draft using the template's sections in order: What I Built, Demo, Code, How I Built It, Why Does Open Innovation Matter?, My Agent Session, Prize Categories (Best Use of Gemma).
   Writing rules:
   - Open with one specific moment from my real walk, in first person
   - Use concrete numbers from my logs (build time, stops, story length, battery)
   - Include an honest "what broke and how I fixed it" part
   - In the open-innovation section, be specific: works with no signal, free to run, location never leaves my devices, model and voice are swappable. Contrast with cloud tour apps in general without naming or bashing anyone.
   - 1,000–1,500 words, short paragraphs, no hype words like "revolutionary" or "game-changer"
3. An edit pass: cut about 15%, check every technical claim against the code, and list anything I need to verify.

Acceptance checklist:
- [ ] Every template section filled, with the devchallenge and hf26challenge tags
- [ ] The post includes the video, the diagram, the repo embed, and at least 2 real photos from the walk
- [ ] The open-innovation section names specific benefits, not generalities
- [ ] Licenses and attributions are listed in the post or README
- [ ] Every link works when opened logged out
- [ ] A fresh read-through, ideally by someone else, finds no confusing paragraph
- [ ] Published by 6 PM, leaving a buffer before 11:59 PM PDT
```

## Demo and submission

The submission is a DEV post built from the challenge's template, written in English, since non-English posts can't win prizes. Writing quality is weighted most, so treat the post as the main deliverable.

**Post outline (the template's sections)**

1. **What I Built:** tours keep you staring at a screen; this one talks while your phone stays in your pocket. Say who it's for.
2. **Demo:** the video, plus a GIF or screenshots of the app.
3. **Code:** embed the GitHub repo.
4. **How I Built It:** the system diagram, the pipeline steps, the Gemma prompt, and what you changed after the real walk.
5. **Why Does Open Innovation Matter?:** free to run, no API keys, the walk works with no signal, your location never leaves your own devices, and you can swap the model or voice.
6. **My Agent Session (optional):** link the AI coding sessions you used, saved with DevRelay.
7. **Prize Categories:** Best Use of Gemma.

Add a short story of the real walk: what worked, what surprised you, what broke.

**Video (about 90 seconds)**

1. Hook: "The best city tour is the one where you never look at your phone."
2. The tour pack building on the Mac.
3. Airplane mode on, on camera.
4. Pocket the phone and walk while two or three stories play over street footage.
5. The system diagram, naming each open model.

**Submission checklist**

- [ ] Post uses the template, with the devchallenge and hf26challenge tags
- [ ] Video link works
- [ ] Public repo with README, model list, licenses, and credits
- [ ] Any commit after the deadline is noted in the README
- [ ] Published before Oct 11, 11:59 PM PDT

## Risks and fallbacks

| Risk | Fallback |
| --- | --- |
| Running out of time | Drop every stretch item; the pipeline plus a real walk is a complete entry |
| Thin Wikipedia coverage on the route | Choose a more historic route, or let Gemma write from OSM tags only |
| Gemma invents facts | Prompt only from fetched facts, and ban dates and numbers that aren't in the input |
| iOS stops background location | Request "always" access, keep the audio session active, test with the screen locked on Friday |
| GPS jitter triggers the wrong stop | Require two consecutive fixes inside the radius before playing |
| TTS sounds robotic | Swap between Piper and Kokoro, or try another voice |
| Heat during the test walk | Walk early morning or after sunset |
