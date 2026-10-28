// The voyage track: a picture of the phase sentence, never more than it.
// Hidden from assistive technology. See docs/visual-design.md.

///|
/// One phase of the track, in thousandths: its share of the crossing's
/// length, and how much of it is behind the ship.
struct Stretch {
  phase : @core.Phase
  width : Int64
  done : Int64
}

///|
/// The crossing's three phases, sized by how long each takes at the
/// current setting and filled by the share of each phase's stock spent.
/// The coast is absent when the plan never reaches the cap.
fn stretches(c : @core.Crossing) -> Array[Stretch] {
  let plan = c.plan
  let burn_rate = @math.rate(plan.eta_rate, c.setting()).max(1L)
  let burn = @math.ticks_to_empty(plan.burn, burn_rate)
  let coast = @math.ticks_to_empty(plan.coast, plan.coast_rate.max(1L))
  // The coast takes the rounding, so the widths always sum to 1000.
  let side = if plan.coast > 0L {
    burn * 1000L / (burn * 2L + coast).max(1L)
  } else {
    500L
  }
  let phases : Array[(@core.Phase, Int64, Int64)] = [
    (Burn, side, plan.burn),
    (Coast, 1000L - side * 2L, plan.coast),
    (Approach, side, plan.burn),
  ]
  phases
  .filter(p => p.2 > 0L)
  .map(p => {
    let (phase, width, stock) = p
    let done = if phase < c.phase {
      1000L
    } else if phase == c.phase {
      (stock - c.left) * 1000L / stock
    } else {
      0L
    }
    { phase, width, done, }
  })
}

///|
/// The track, or nothing in port.
fn track(c : @core.Crossing) -> @rabbita.Html {
  let attrs = @html.Attrs::build().aria_hidden("true")
  @html.div(
    class="track",
    attrs~,
    stretches(c).map(s => {
      let now = if s.phase == c.phase { " now" } else { "" }
      @html.div(class="stretch\{now}", style=["flex: \{s.width} 1 0"], [
        @html.div(class="bar", [
          @html.div(
            class="fill",
            style=["width: \{s.done / 10L}.\{s.done % 10L}%"],
            "",
          ),
        ]),
        @html.span(class="label", phase_name(s.phase)),
      ])
    }),
  )
}
