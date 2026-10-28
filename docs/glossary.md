# glossary

- **cast entry**: a ship's source notes, written from its figure in the
  novel: traits, relationships by pennant, star, other names. Never shown to
  players or fed to the running game.
- **epithet**: a ship's English name (`The Tigress`). Ships use epithets for
  themselves and each other.
- **conventional name**: a ship's Chinese name (`顧大嫂`), the source
  figure's conventional name in Chinese. The interface uses it to identify
  the ship; ships never use it.
- **title**: a ship's full identifier, pennant plus conventional name plus
  epithet (`EF-147 顧大嫂 The Tigress`). What a ship is formally called;
  shorter references use the name that matches the language of the text.
- **portrait**: a ship's private third-person character study, made from its
  cast entry. Every face is made from it.
- **face**: a first-person file made from the portrait for one reader in the
  running game: `captain.md`, `voice.md`, `voyage.md`.
- **draft**: a generated portrait or face, kept in a ship's `drafts/` with
  its generation record. Regenerated freely.
- **canon**: the approved file for a stage, beside the cast entry. Written by
  approving a draft, or by hand; never overwritten by a run.
- **gate**: the check that model text passes before a player sees it. A
  classifier model reads the text against `content/gate/policy.md` and
  returns a verdict, clean or violation, with the quote that decided it.
- **post**: a crew member's current assignment: ship work (drive, hull) or
  their craft. Held while away. See [gameplay](gameplay.md).
- **craft**: what a crew member's hours on the craft post make: refits for
  engineers, works for artists. Changeable at any time.
- **regard**: the ship's record of what each crew member did, computed in
  core and weighted by the ship's authored values.
- **rank**: a crew member's public standing aboard, set by regard. Grants no
  authority yet.
- **watch**: a promise to hold the current post for a stated time, up to
  what the crew member's rank allows. Counts a quarter more hand; breaking it
  costs regard.
- **standing order**: a post to take when a later phase begins. Fires at the
  phase boundary, so no one has to be present.
- **demand**: a call for crew-hours on one post before its phase ends:
  breach, flare or salvage. Fixed at departure.
- **refit**: a permanent change to a ship's fit, built by engineers: baffles,
  plating, injectors or coils.
- **work**: what an artist makes, six crew-hours each. Delivered at port,
  where works bring recruits.
- **recruit**: an NPC who joins at port for works delivered and works ship
  posts only.
- **docking**: settling an arrived crossing into the ship that leaves port
  (`Crossing::dock`).
- **temperament**: the scripted stand-in for a ship's model choices: what it
  asks for and which refit it proposes. Bold, careful, social or sly.
- **band**: one of four hull ranges that set the drive's highest setting.
