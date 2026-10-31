///|
test "a world's visits, from the dockings in the story" {
  let w = (name : String) => @ships.world_named(name).unwrap()
  let calls = [("Occitan", 1L), ("Oaxaca", 2L), ("Occitan", 4L), ("Tigray", 6L)]
  debug_inspect(
    [
      visits(w("Occitan"), calls, 6),
      visits(w("Oaxaca"), calls, 6),
      visits(w("Kerala"), calls, 6),
      visits(w("The Three Tyrants"), calls, 6),
    ],
    content=(
      #|[
      #|  "You have docked here twice, last 2 crossings ago.",
      #|  "You have docked here once, last 4 crossings ago.",
      #|  "You were commissioned here, and have not docked here since.",
      #|  "You have never docked here.",
      #|]
    ),
  )
}
