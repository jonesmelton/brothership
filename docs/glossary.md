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
- **gate**: the check that model text passes before a player sees it. A
  classifier model reads the text against `content/gate/policy.md` and
  returns a verdict, clean or violation, with the quote that decided it.
- **officer**: the crew member a player controls. A session's officer is the
  crew id that player's proposals act as. Recruits and other NPC crew are
  crew members but not officers.
- **service number**: an officer's public crew id, minted once as `OF-` and
  seven base32 characters (`OF-7K2M9QX`) and stable for the life of the
  session cookie. It is how the ship knows the officer, and the name other
  officers see in the roster. It is never the session token.
- **session**: a random token in an HttpOnly cookie, mapped to an officer.
  Not an account: clearing the cookie starts a new officer.
- **handle**: the server-issued identifier a ship's model uses for one
  officer, so it can attribute actions and single that officer out. Never
  player-written, and not a display name. Today a letter per crossing, in
  the order hands joined (`@speech.handles`); the model is told never to
  say it aloud.
- **display name**: an officer's name shown to other players. Interface
  text only; a ship's model never sees it.
- **post**: a crew member's current assignment: ship work (drive, hull) or
  their craft. Held while away. See [gameplay](gameplay.md).
- **craft**: what a crew member's hours on the craft post make: refits for
  engineers, works for artists. Changeable at any time.
- **regard**: the ship's record of what each crew member did, computed in
  core and weighted by the ship's authored values.
- **rank**: a crew member's public standing aboard, one of five: ensign,
  lieutenant junior grade, lieutenant, lieutenant commander or commander.
  Held per ship in `Record.rank`, not derived from regard at each lookup.
  `rank_floor` gives the rank regard makes someone eligible for; a
  `Promoted` event moves the held rank one step at arrival, before docking,
  under the caps in `rank_caps`. Grants nothing yet, not even a longer watch.
- **watch**: a promise to hold the current post for a stated time, at least
  an hour, with no upper limit in the rules. The interface offers up to 12
  hours, and rank does not limit it. Counts a quarter more hand; breaking it
  costs regard.
- **standing order**: a post to take when a later phase begins. Fires at the
  phase boundary, so no one has to be present.
- **demand**: a call for crew-hours on one post before its phase ends:
  breach, flare or dust. Fixed at departure.
- **refit**: a permanent change to a ship's fit, built by engineers: baffles,
  plating, injectors or coils.
- **work**: what an artist makes, six crew-hours each. Delivered at port,
  where works bring recruits.
- **recruit**: an NPC who joins at port for works delivered and works ship
  posts only.
- **docking**: settling an arrived crossing into the ship that leaves port
  (`Crossing::dock`).
- **launch**: the port stay, from docking until the stores are loaded and
  the ship departs (`State::launch`).
- **stores**: what a ship loads in port before it can depart, sized by the
  next leg's light-years; hands on the drive load them (`Port.stores`).
- **yard**: the port's mending of the hull, which hands on the hull add to
  until the ship departs.
- **dockhands**: the port's own hands, who load stores and work the yard at
  a floor rate whoever is aboard (`DOCKHANDS`, `YARD_FLOOR`).
- **temperament**: the scripted stand-in for a ship's model choices: what it
  asks for and which refit it proposes. Bold, careful, social or sly. The
  fallback when the mind's call fails, and the whole policy in the
  simulator.
- **mind**: the model that makes a ship's choices on the server: its asks,
  refits and promotions (`@mind.Mind`). A ship with a mind is *minded*.
- **cruise**: the share of its γ cap a ship coasts at, chosen in port for
  the next crossing: full, four fifths or three fifths (`Ship.cruise`, in
  thousandths). A slower cruise arrives later and erodes the hull less.
- **erosion**: what the coast does to the hull, growing with the square of
  the pace. Wear is what the burn does.
- **band**: one of four hull ranges that set the drive's highest setting.
