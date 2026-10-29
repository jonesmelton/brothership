///|
fn tenths(x : Double) -> String {
  let n = (x * 10.0).round().to_int()
  "\{n / 10}.\{n % 10}"
}

///|
test "the worlds lie as their stars do, 13.8 to 25.4 ly apart" {
  let ws = @ships.worlds
  let pairs = []
  for i in 0..<ws.length() {
    for j in (i + 1)..<ws.length() {
      pairs.push("\{ws[i].name} \{ws[j].name} \{tenths(ws[i].distance_to(ws[j]))}")
    }
  }
  debug_inspect(
    pairs,
    content=(
      #|[
      #|  "Kerala Tigray 24.2",
      #|  "Kerala Oaxaca 20.0",
      #|  "Kerala Occitan 15.7",
      #|  "Tigray Oaxaca 21.7",
      #|  "Tigray Occitan 13.8",
      #|  "Oaxaca Occitan 25.4",
      #|]
    ),
  )
}

///|
test "every hop of the itinerary is 8 to 30 ly" {
  for i in 0..<@ships.itinerary.length() {
    let d = @ships.hop(i.to_int64())
    assert_true(d >= 8.0 && d <= 30.0)
  }
}

///|
test "a leg runs from the world of the last docking, and round again" {
  let names = (n : Int64) => {
    let (from, to) = @ships.leg(n)
    "\{from.name} \{to.name}"
  }
  inspect(names(0), content="Kerala Occitan")
  inspect(names(1), content="Occitan Tigray")
  inspect(names(7), content="Oaxaca Kerala")
  inspect(names(8), content="Kerala Occitan")
  // Every pair of worlds is flown.
  let flown : Map[String, Bool] = Map([])
  for i in 0..<@ships.itinerary.length() {
    let (from, to) = @ships.leg(i.to_int64())
    let key = if from.name < to.name {
      from.name + to.name
    } else {
      to.name + from.name
    }
    flown[key] = true
  }
  inspect(flown.length(), content="6")
}

///|
test "the map is drawn in the worlds' plane, true to within 0.05 ly" {
  let ws = @ships.worlds
  for i in 0..<ws.length() {
    for j in (i + 1)..<ws.length() {
      let (x1, y1) = ws[i].on_map()
      let (x2, y2) = ws[j].on_map()
      let drawn = ((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)).sqrt()
      assert_true(
        (drawn - ws[i].distance_to(ws[j])).abs() < 0.05,
        msg="\{ws[i].name} \{ws[j].name}",
      )
    }
  }
}

///|
test "the next plan flies the itinerary's hop" {
  let p = @ships.profiles()[1]
  let plan = p.next_plan(legs=0, coils=0)
  let flown = { ..p.route, distance_ly: @ships.hop(0) }.plan()
  assert_eq(plan, flown)
}
