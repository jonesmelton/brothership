///|
/// Width of every chart in px; plots start after the label gutter.
const WIDTH : Int32 = 680

///|
const GUTTER : Int32 = 104

///|
const INK : String = "#1a1a1a"

///|
const QUIET : String = "#b8b8b8"

///|
const ACCENT : String = "#b3261e"

///|
/// A linear map from a data range to a pixel range.
struct Scale {
  lo : Double
  hi : Double
  from : Int32
  to : Int32
}

///|
fn Scale::at(self : Scale, v : Double) -> Int32 {
  let span = if self.hi == self.lo { 1.0 } else { self.hi - self.lo }
  let f = ((v - self.lo) / span).clamp(min=0.0, max=1.0)
  self.from + ((self.to - self.from).to_double() * f).round().to_int()
}

///|
fn x_scale(lo : Double, hi : Double) -> Scale {
  { lo, hi, from: GUTTER, to: WIDTH - 8, }
}

///|
/// A series held constant until its next point, as a polyline.
fn step_points(
  points : Array[(Double, Double)],
  x : Scale,
  y : Scale,
) -> Array[(Int32, Int32)] {
  let out = []
  for i, p in points {
    out.push((x.at(p.0), y.at(p.1)))
    if points.get(i + 1) is Some(next) {
      out.push((x.at(next.0), y.at(p.1)))
    }
  }
  out
}

///|
fn label(x : Int32, y : Int32, text : String, fill~ : String = INK) -> @svg.Svg {
  @svg.svg_text(x~, y~, text~, fill~, style=["font-size: 12px"])
}

///|
fn rule(
  x1 : Int32,
  y1 : Int32,
  x2 : Int32,
  y2 : Int32,
  stroke~ : String = QUIET,
) -> @svg.Svg {
  @svg.line(x1~, y1~, x2~, y2~, stroke~, stroke_width=1)
}

///|
/// A graphic with its finding stated in words and its values in a table. The
/// drawing is hidden from screen readers; the caption and table carry it.
fn figure(
  caption : String,
  height : Int32,
  marks : Array[@svg.Svg],
  values : @html.Html,
) -> @html.Html {
  @html.figure([
    @html.div(attrs=@html.Attrs::build().aria_hidden("true"), [
      @svg.svg(
        width=WIDTH,
        height~,
        view_box="0 0 \{WIDTH} \{height}",
        style=["max-width: 100%", "height: auto"],
        marks,
      ),
    ]),
    @html.figcaption(caption),
    @html.details([@html.summary("Values"), values]),
  ])
}

///|
/// A plain table: one header row, then rows of cells; columns after the
/// first are numeric and set flush right.
fn data_table(
  caption : String,
  header : Array[String],
  rows : Array[Array[String]],
) -> @html.Html {
  @html.div(
    class="table-scroll",
    attrs=@html.Attrs::build().role("region").aria_label(caption).tabindex(0),
    [
      @html.table([
        @html.caption(caption),
        @html.thead([
          @html.tr(
            header.mapi((i, h) => {
              @html.th(scope=Col, class=if i == 0 { "" } else { "num" }, h)
            }),
          ),
        ]),
        @html.tbody(
          rows.map(row => {
            @html.tr(
              row.mapi((i, cell) => {
                if i == 0 {
                  @html.th(scope=Row, cell)
                } else {
                  @html.td(class="num", cell)
                }
              }),
            )
          }),
        ),
      ]),
    ],
  )
}
