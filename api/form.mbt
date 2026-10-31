///|
/// The fields of an `application/x-www-form-urlencoded` body, in order.
/// moonback decodes query strings this way but does not export it.
fn form_fields(body : String) -> Array[(String, String)] {
  body
  .split("&")
  .filter(pair => pair != "")
  .map(pair => {
    match pair.split_once("=") {
      Some((name, value)) => (form_decode(name), form_decode(value))
      None => (form_decode(pair), "")
    }
  })
  .collect()
}

///|
/// `+` as a space and `%XX` as a byte, the bytes read as UTF-8. A
/// malformed escape is kept as written.
fn form_decode(input : StringView) -> String {
  let chars = input.to_array()
  let bytes = Buffer()
  let mut i = 0
  while i < chars.length() {
    match chars[i] {
      '+' => {
        bytes.write_byte(b' ')
        i += 1
      }
      '%' if i + 2 < chars.length() &&
        hex(chars[i + 1]) is Some(hi) &&
        hex(chars[i + 2]) is Some(lo) => {
        bytes.write_byte((hi * 16 + lo).to_byte())
        i += 3
      }
      c => {
        bytes.write_char_utf8(c)
        i += 1
      }
    }
  }
  @utf8.decode_lossy(bytes.to_bytes())
}

///|
fn hex(c : Char) -> Int32? {
  match c {
    '0'..<='9' => Some(c.to_int() - '0'.to_int())
    'a'..<='f' => Some(c.to_int() - 'a'.to_int() + 10)
    'A'..<='F' => Some(c.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}
