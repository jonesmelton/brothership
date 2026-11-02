# accessibility

Idle games are one of the genres blind and low vision players already play in numbers, and the game's other ancestor, the MUD, has been part of blind gaming culture for decades. These players are who the game is for. They are the design center, not an accommodation. Anything that makes the game better for them is in scope now, not later.

Sighted players get the same game, presented with the same care. We assume everyone plays on a phone. Judges will likely play on a desktop, so that has to work too.

## commitments

- **Every part of the game can be played with a screen reader**, on a phone, without looking at the screen. A feature that can't isn't finished.
- **Every part of the game can be played at large text sizes and high zoom** without scrolling sideways or losing information.
- **Nothing depends on seeing**: no information carried only by color, position, shape, icon or animation.
- **Nothing depends on timing**: no prompt that has to be answered within a window, no state that's only visible for a moment.
- **No audio is required.** Speech from the player's own screen reader is the audio channel, so the text has to work as speech.
- **The player decides what interrupts them.** An idle game produces events whether or not anyone is listening. The player controls which ones are spoken as they happen and which wait in the log.

## the approach

### the text is the game

Game state is an event stream and every view of it is rendered from that stream (see [decisions](decisions.md)). Every event has a sentence. That sentence is written first, and it is the primary form of the event: what a screen reader speaks, what goes in the log, and what the visual layout is built around. Visual presentation can add to the sentence, such as a bar next to a number or emphasis on a name, but it never says something the sentence doesn't.

If the log, read top to bottom as plain text, is enough to understand and play the game, the game is accessible in substance. Everything after that is presentation.

### speech is a scarce resource

Listening is slower than looking and can't be skimmed. Each word spoken costs the player time, and each announcement interrupts them.

- **Put the important part first.** "Hull breach on the Black Whirlwind" rather than "The Black Whirlwind reports that it has suffered a hull breach".
- **Say it once.** No label that repeats a heading, no "button" in a button's name, no decorative text.
- **Keep numbers short.** Round them, use the same units everywhere, and don't give precision the player can't use.
- **Give every event a priority.** Three levels: interrupt (needs the player's attention now; rare), announce (spoken when the screen reader is idle), and log only. Most events are log only.
- **Summarize when the player comes back.** "While you were away" is a short summary with the details in the log, not a replay.

The ships are voiced by language models, which are verbose by default. Generated text is held to a length budget and screened for anything that reads badly aloud: markdown, emoji, lists of symbols, ASCII art. A ship's line has to be worth hearing.

### pull, not just push

Players shouldn't have to catch an announcement to know what's happening. The current state of the ship, crew and anything in progress can be asked for at any time, in one place, in a predictable order. Announcements tell the player something changed; the status view tells them where things stand.

### structure does the work

Screen reader users move around a page by headings, landmarks, lists and controls, not by reading everything. Visual readers scan by the same structure. So:

- Use native elements: real headings, buttons, lists and tables. Custom widgets are a last resort.
- Keep each screen short and its structure the same every time. Things don't move, reorder or appear in new places without the player asking.
- Give every screen one obvious place to start reading.
- Keep tables for actual tabular data, small enough to navigate cell by cell.

### low vision

- Text scales with the system text size, and layouts reflow to a single column at any size.
- Color contrast meets WCAG AA at minimum. Color is never the only way information is shown.
- Touch targets are large and spaced apart.
- No information only on hover or long press.
- Respect reduced motion. Animation is never needed to understand what happened.
- Nothing fixed to the screen that eats space when zoomed in. The bar of pages is fixed only on viewports tall enough to spare it, and in the flow otherwise.

### phones first, desktop too

Single column, operable with standard VoiceOver and TalkBack gestures. No custom gestures, no dragging. On desktop the same layout has to be fully operable by keyboard, with a visible focus indicator, and readable with VoiceOver on macOS and NVDA on Windows.

### sighted players

Without sound, typography and layout carry the presentation for sighted players. This is not in tension with the above: a clear hierarchy, short front-loaded text, and stable layout are what makes information easy to scan. The visual design is a careful presentation of the same structure, not a separate design with an accessible copy behind it.

## how we decide

When a choice comes up:

1. **Does it make the screen reader experience worse?** Then it doesn't ship, however much it improves the visual one.
2. **Is there a version that's smaller and fully accessible?** Ship that instead of a bigger one that's partly accessible. Cut scope, not access.
3. **Build the text path first.** Event, sentence, priority, and screen reader behavior come before visual design for any feature. The visual layer is built on top of a working text version, never the other way round.

A feature is done when:

- every event it produces has a sentence and a priority,
- it can be played start to finish with VoiceOver on iOS with Screen Curtain on (three-finger triple tap), so the screen is dark,
- it works at the largest system text size and at 400% browser zoom with no horizontal scrolling,
- it's keyboard operable on desktop,
- automated checks (axe or similar) report nothing new.

## testing, and its limits

The game is playtested by blind and low vision users and by automated checks. Author testing is done as a sighted, competent screen reader user on iOS, with the screen off. This catches broken controls, missing labels, bad focus order, and announcements that are dropped or garbled.

That does not cover the range of daily screen reader use: screen readers, speech rates, tolerance for verbosity, navigation routes and sensitivity to repetition all differ between users. We correct for this by erring towards brevity and by following established conventions rather than inventing interaction patterns.

Known risk: live region announcements in Safari on iOS are unreliable. They can be dropped, cut off, or queued badly when several arrive together. The announcement system is the core of the game for screen reader players, so it gets tested on a real device first, before the game is built around it.

`document.ariaNotify(text, { priority })` is the mitigation. It has been Baseline since September 2026 (Chrome 141, Firefox 150, Safari on iOS 27) and queues speech after the current utterance (`normal`) or interrupts it (`high`), without depending on a DOM mutation being noticed. The client uses it where it exists, mapping interrupt to `high` and announce to `normal`, and sends each batch as one string because some screen readers speak only the most recent call. Where it does not exist, the client falls back to the two live regions, and never uses both for the same text. The risk stands for those browsers, and for how each screen reader treats a `high` call, which has not been tested on a device.

## optional sounds and type

Sounds are off by default and never required. When the player turns them on in Settings, a short tone marks each happening that is read aloud: a tone for an announcement, a two-note figure for an interrupt, a softer one for a ship's line. The sentence is still in the log and in the announcement. No cue plays for what the read-aloud setting leaves out. The audio context starts after a gesture, and each cue stays under 400 ms and 0.2 gain.

The Type setting switches every Latin face to Atkinson Hyperlegible Next, for readers who find the book faces hard to read. The default is the book voice.
