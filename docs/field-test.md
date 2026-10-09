# Field test: mexicali2, full route

Date: 2026-10-__ · Start time: ____ · Battery at start: ____ % · Weather: ____

Setup checklist (before leaving):

- [ ] Fresh build on the phone from `main`
- [ ] Location permission is **Always** (Debug info shows it)
- [ ] Airplane mode on before tapping **Start walk**
- [ ] Phone volume up, headphones or speaker decided
- [ ] Second phone or camera charged for footage

Rules for filling this in: one row per stop, written **at the stop** (or within a minute). Timing means where you were when the story started:

- **early**: still well outside, you couldn't see the place yet
- **right**: at the entrance or within a few steps
- **late**: you were already past it or had to stand around waiting

Audio and story scores are 1–5.

| # | Stop | Played (yes/no) | Timing (early/right/late) | Audio quality (1–5) | Story accuracy (1–5) | Notes (what was wrong, clock time) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Parque Gran Hacienda | | | | | |
| 2 | Parque Mágica | | | | | |
| 3 | Juventud 2000 | | | | | |
| 4 | Jardines de Cecyte Xochimilco | | | | | |
| 5 | Parque Hacienda del Real | | | | | |

For a story you mark ≤ 3 on accuracy, note the exact wrong claim (for example "says it has a lake, it doesn't"). That's what drives the prompt fix.

## After the walk

- Total time (Start walk to Stop walk): ____
- Battery used: ____ % (start ____ % to end ____ %)
- Best moment:
- What surprised me:
- What broke:

Then:

1. Tap **Stop walk** first (that writes the `closest` rows), then **Export trigger log**, then Save to Files or AirDrop.
2. Save it as `docs/field-test/trigger-log-YYYY-MM-DD.csv`.
3. Paste this filled sheet and the CSV into the chat.

### Reading the trigger log

`time,event,stop_id,stop_name,distance_m,accuracy_m`, one line per event:

| Event | Meaning | What it diagnoses |
| --- | --- | --- |
| `walk_start` / `walk_end` | One walk; the file keeps every walk in order | Ignore earlier simulator walks |
| `enter` | First fix inside the stop's radius (35 m), at **any** accuracy | Gap from `enter` to `trigger` = lag from the 2-fix rule plus the accuracy filter |
| `trigger` | Engine chose the stop: 2 fixes in a row, accuracy ≤ 25 m, inside radius | Distance shows how deep inside the radius it fired |
| `closest` | Written at walk end, per stop: nearest fix and that fix's accuracy | Missed stop: closest > 35 m means the radius is too small or the pin is off; closest < 35 m with accuracy > 25 means the filter is too strict |

## Demo video: 6 shots, 90 seconds

| # | Time | Shot | Capture | Notes |
| --- | --- | --- | --- | --- |
| 1 | 0:00–0:10 | **Hook.** Walking up to a park, phone nowhere in sight, a story starts. Caption: "My city, narrated by an AI that runs on my laptop. No internet." | Second phone, chest height, following from behind. Grab 3+ takes. | Lead with the payoff. Record clean audio of the story starting. |
| 2 | 0:10–0:25 | **Tour building on the Mac.** Terminal running `build_tour.py`: Overpass, then Wikipedia, then Gemma writing a story, then Piper voicing it. | Screen recording (⌘⇧5) plus a phone shot of the Mac for texture. | Speed it up 4–8×. Freeze for one second on a generated story line. |
| 3 | 0:25–0:32 | **Airplane mode on.** Control Center, tap the plane icon, the status bar shows ✈. | Screen recording on the iPhone, or a close-up over the shoulder. | Proof that it's offline. Keep the ✈ in view for a beat. |
| 4 | 0:32–0:40 | **Start walk, lock, pocket.** Tap Start walk, press the side button, phone slides into a pocket. | Close-up, steady, good light. | One continuous take. |
| 5 | 0:40–1:15 | **Walking while 2–3 stories play.** Wide shots of the street and the parks, with the narration as the audio track. Include one trigger moment where you visibly react or look up. | Second phone or gimbal; wide and medium shots. | Record the phone's audio separately (screen recording with audio, or a clip-on mic) for a clean voice track. |
| 6 | 1:15–1:30 | **System diagram.** OSM + Wikipedia → Gemma (Ollama) → Piper → tour pack → iPhone (GPS trigger, offline). End card: repo link, "open models only". | Animated slide or screen recording of the diagram. | The README/walk-test diagram is the source; redraw it cleanly for video. |

Photos (at least 5): the phone in a pocket at a stop, each park entrance sign, the Mac terminal mid-build, the debug panel showing distance and accuracy, and the ✈ status bar with the location pill.
