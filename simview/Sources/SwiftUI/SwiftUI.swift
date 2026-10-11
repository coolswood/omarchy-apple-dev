// Our SwiftUI implementation for Linux, milestone M2 of the simulation
// ladder in docs/IOS-SIMULATION-LINUX.md. The demo app in sdk-free/swiftui
// compiles here unchanged and renders one frame to a PNG on the CPU.
//
// Ours end to end: these declarations, the 5 x 7 bitmap glyphs, the layout
// and raster pass, and the PNG encoder. No Apple source, no third-party code.
//
// Not in this module: real SwiftUI layout, font shaping, animation, Metal,
// and the state write plus touch loop (M3, docs/SIM-INPUT-MODEL.md). State
// and Button actions are stored; M2 never runs them, so the app renders once
// with the initial state.

import Foundation

// MARK: - Public API surface (same shape as sdk-free/swiftui/SwiftUI.swift)

public typealias CGFloat = Double

@resultBuilder
public enum ViewBuilder {
  public static func buildBlock() -> EmptyView { EmptyView() }
  public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
  public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1)
    -> TupleView<(C0, C1)> { TupleView((c0, c1)) }
  public static func buildExpression<Content: View>(_ content: Content) -> Content { content }
}

@resultBuilder
public enum SceneBuilder {
  public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
  public static func buildExpression<Content: Scene>(_ content: Content) -> Content { content }
}

public protocol View {
  associatedtype Body: View
  var body: Self.Body { get }
  func _simSpec() -> Spec
}

public extension View {
  func _simSpec() -> Spec { body._simSpec() }
}

public protocol Scene {
  associatedtype Body: Scene
  var body: Self.Body { get }
  func _simSceneSpec() -> Spec
}

public extension Scene {
  func _simSceneSpec() -> Spec { body._simSceneSpec() }
}

public protocol App {
  associatedtype Body: Scene
  var body: Self.Body { get }
  init()
}

public extension App {
  // Entry point for @main apps: parse --out, render one frame, write the PNG.
  static func main() {
    var path: String?
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
      if a == "--out" { path = it.next() }
    }
    guard let out = path else {
      FileHandle.standardError.write(Data("usage: \(CommandLine.arguments[0]) --out <file.png>\n".utf8))
      exit(2)
    }
    let canvas = Sim.render(Self().body._simSceneSpec())
    do {
      try Sim.writePNG(canvas, to: out)
    } catch {
      FileHandle.standardError.write(Data("simview: \(error)\n".utf8))
      exit(1)
    }
    print("wrote \(out) \(canvas.width)x\(canvas.height)")
  }
}

public struct EmptyView: View {
  public init() {}
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .empty }
}

public struct EmptyScene: Scene {
  public init() {}
  public typealias Body = EmptyScene
  public var body: EmptyScene { EmptyScene() }
  public func _simSceneSpec() -> Spec { .empty }
}

// The render tree the measure and draw passes walk. Public only because the
// protocol requirements above expose it; app code never names it.
public enum Spec {
  case empty
  case text(String)
  indirect case button(Spec)
  indirect case tuple([Spec])
  indirect case vstack(HorizontalAlignment, spacing: Int, children: [Spec])
}

public struct TupleView<T>: View {
  let children: [any View]
  public init(_ value: T) {
    children = Mirror(reflecting: value).children.compactMap { $0.value as? any View }
  }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .tuple(children.map { $0._simSpec() }) }
}

public struct WindowGroup<Content: View>: Scene {
  let content: Content
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
  public typealias Body = EmptyScene
  public var body: EmptyScene { EmptyScene() }
  public func _simSceneSpec() -> Spec { content._simSpec() }
}

public struct HorizontalAlignment {
  enum Kind { case center, leading, trailing }
  let kind: Kind
  public static let center = HorizontalAlignment(kind: .center)
  public static let leading = HorizontalAlignment(kind: .leading)
  public static let trailing = HorizontalAlignment(kind: .trailing)
}

public struct VStack<Content: View>: View {
  let alignment: HorizontalAlignment
  let spacing: Int
  let content: Content
  public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
              @ViewBuilder content: () -> Content) {
    self.alignment = alignment
    self.spacing = spacing.map(Int.init) ?? 0
    self.content = content()
  }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec {
    .vstack(alignment, spacing: spacing, children: Sim.flattened(content._simSpec()))
  }
}

public struct Text: View {
  let content: String
  public init<S: StringProtocol>(_ content: S) { self.content = String(content) }
  public init(verbatim content: String) { self.content = content }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .text(content) }
}

public struct Button<Label: View>: View {
  let action: () -> Void  // stored for M3; M2 renders once and never fires it
  let label: Label
  public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
  }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .button(label._simSpec()) }
}

extension Button where Label == Text {
  public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) {
    self.init(action: action, label: { Text(title) })
  }
}

@propertyWrapper
public struct State<Value> {
  var value: Value
  public init(wrappedValue: Value) { value = wrappedValue }
  public var wrappedValue: Value {
    get { value }
    nonmutating set { fatalError("simview renders once in M2; state writes land with M3") }
  }
  public var projectedValue: Binding<Value> {
    Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
  }
}

public struct Binding<Value> {
  let get: () -> Value
  let set: (Value) -> Void
}

// MARK: - Layout, raster, glyphs, PNG

enum Sim {
  static let screenWidth = 390
  static let screenHeight = 844
  static let black = Pixel(r: 0, g: 0, b: 0)
  static let blue = Pixel(r: 0x00, g: 0x7A, b: 0xFF)  // #007AFF

  static func flattened(_ s: Spec) -> [Spec] {
    if case .tuple(let kids) = s { return kids }
    return [s]
  }

  // MARK: layout

  static func measure(_ s: Spec) -> Size {
    switch s {
    case .empty:
      return Size(w: 0, h: 0)
    case .text(let t):
      return textSize(t)
    case .button(let inner):
      return measure(inner)
    case .tuple(let kids):
      return stackSize(kids, spacing: 0)
    case .vstack(_, let spacing, let kids):
      return stackSize(kids, spacing: spacing)
    }
  }

  static func stackSize(_ kids: [Spec], spacing: Int) -> Size {
    var w = 0
    var h = 0
    for (i, k) in kids.enumerated() {
      let ks = measure(k)
      w = max(w, ks.w)
      h += ks.h + (i > 0 ? spacing : 0)
    }
    return Size(w: w, h: h)
  }

  static func draw(_ s: Spec, in c: inout Canvas, at x: Int, y: Int, width: Int,
                   color: Pixel = black) {
    switch s {
    case .empty:
      break
    case .text(let t):
      drawText(t, in: &c, at: x, y: y, color: color)
    case .button(let inner):
      draw(inner, in: &c, at: x, y: y, width: width, color: blue)
    case .tuple(let kids):
      drawStack(kids, spacing: 0, in: &c, at: x, y: y, width: width, color: color)
    case .vstack(let alignment, let spacing, let kids):
      drawStack(kids, spacing: spacing, in: &c, at: x, y: y, width: width,
                alignment: alignment, color: color)
    }
  }

  static func drawStack(_ kids: [Spec], spacing: Int, in c: inout Canvas,
                        at x: Int, y: Int, width: Int,
                        alignment: HorizontalAlignment = HorizontalAlignment(kind: .center),
                        color: Pixel = black) {
    var cy = y
    for k in kids {
      let ks = measure(k)
      let kx: Int
      switch alignment.kind {
      case .center: kx = x + (width - ks.w) / 2
      case .leading: kx = x
      case .trailing: kx = x + width - ks.w
      }
      draw(k, in: &c, at: kx, y: cy, width: ks.w, color: color)
      cy += ks.h + spacing
    }
  }

  static func render(_ spec: Spec) -> Canvas {
    var c = Canvas(width: screenWidth, height: screenHeight, fill: Pixel.white)
    let s = measure(spec)
    let x = (screenWidth - s.w) / 2
    let y = (screenHeight - s.h) / 2
    draw(spec, in: &c, at: x, y: y, width: s.w)
    return c
  }

  // MARK: glyphs

  struct Size { let w: Int; let h: Int }

  // Hand-drawn 5 x 7 glyphs, rows of 5 bits, only the ASCII the demo apps
  // need. Unknown characters advance one cell and draw nothing.
  enum Font {
    static let glyphWidth = 5
    static let glyphHeight = 7
    static let advance = 6     // glyph plus one column gap
    static let glyphs: [Character: String] = [
      " ": "00000 00000 00000 00000 00000 00000 00000",
      "0": "01110 10001 10011 10101 11001 10001 01110",
      "1": "00100 01100 00100 00100 00100 00100 01110",
      "2": "01110 10001 00001 00010 00100 01000 11111",
      "3": "11111 00010 00100 00110 00001 10001 01110",
      "4": "00010 00110 01010 10010 11111 00010 00010",
      "5": "11111 10000 10000 11110 00001 10001 01110",
      "6": "01110 10000 10000 10111 11001 10001 01110",
      "7": "11111 00001 00010 00100 01000 01000 01000",
      "8": "01110 10001 10001 01110 10001 10001 01110",
      "9": "01110 10001 10001 10011 11101 00001 01110",
      "a": "00000 00000 01110 00001 01111 10001 01111",
      "b": "10000 10000 11110 10001 10001 10001 11110",
      "c": "00000 00000 01110 10000 10000 10000 01110",
      "d": "00001 00001 01111 10001 10001 10001 01111",
      "e": "00000 00000 01110 10001 11111 10000 01110",
      "f": "00110 01001 01000 11100 01000 01000 01000",
      "g": "00000 01111 10001 10001 01111 00001 01110",
      "h": "10000 10000 11110 10001 10001 10001 10001",
      "i": "00100 00000 00100 00100 00100 00100 00100",
      "j": "00010 00000 00010 00010 00010 10010 01100",
      "k": "10000 10010 10100 11000 10100 10010 10001",
      "l": "01100 00100 00100 00100 00100 00100 01110",
      "m": "00000 00000 11110 10101 10101 10101 10101",
      "n": "00000 00000 11110 10001 10001 10001 10001",
      "o": "00000 00000 01110 10001 10001 10001 01110",
      "p": "00000 11110 10001 10001 11110 10000 10000",
      "q": "00000 01111 10001 10001 01111 00001 00001",
      "r": "00000 00000 01110 10001 10000 10000 10000",
      "s": "00000 00000 01111 10000 01110 00001 11110",
      "t": "01000 01000 11100 01000 01000 01000 00110",
      "u": "00000 00000 10001 10001 10001 10011 01101",
      "v": "00000 00000 10001 10001 10001 01010 00100",
      "w": "00000 00000 10001 10001 10101 10101 01010",
      "x": "00000 00000 10001 01010 00100 01010 10001",
      "y": "00000 10001 10001 10001 01111 00001 01110",
      "z": "00000 00000 11111 00010 00100 01000 11111",
      "A": "01110 10001 10001 11111 10001 10001 10001",
      "B": "11110 10001 10001 11110 10001 10001 11110",
      "C": "01110 10001 10000 10000 10000 10001 01110",
      "D": "11100 10010 10001 10001 10001 10010 11100",
      "E": "11111 10000 10000 11110 10000 10000 11111",
      "F": "11111 10000 10000 11110 10000 10000 10000",
      "G": "01110 10001 10000 10111 10001 10001 01110",
      "H": "10001 10001 10001 11111 10001 10001 10001",
      "I": "01110 00100 00100 00100 00100 00100 01110",
      "J": "00111 00010 00010 00010 00010 10010 01100",
      "K": "10001 10010 10100 11000 10100 10010 10001",
      "L": "10000 10000 10000 10000 10000 10000 11111",
      "M": "10001 11011 10101 10101 10001 10001 10001",
      "N": "10001 11001 10101 10011 10001 10001 10001",
      "O": "01110 10001 10001 10001 10001 10001 01110",
      "P": "11110 10001 10001 11110 10000 10000 10000",
      "Q": "01110 10001 10001 10001 10101 10010 01101",
      "R": "11110 10001 10001 11110 10100 10010 10001",
      "S": "01111 10000 10000 01110 00001 00001 11110",
      "T": "11111 00100 00100 00100 00100 00100 00100",
      "U": "10001 10001 10001 10001 10001 10001 01110",
      "V": "10001 10001 10001 10001 01010 01010 00100",
      "W": "10001 10001 10001 10101 10101 10101 01010",
      "X": "10001 10001 01010 00100 01010 10001 10001",
      "Y": "10001 10001 01010 00100 00100 00100 00100",
      "Z": "11111 00001 00010 00100 01000 10000 11111",
      ":": "00000 00100 00100 00000 00100 00100 00000",
      ".": "00000 00000 00000 00000 00000 00000 00100",
      ",": "00000 00000 00000 00000 00000 00100 01000",
      "!": "00100 00100 00100 00100 00100 00000 00100",
      "?": "01110 10001 00001 00010 00100 00000 00100",
      "-": "00000 00000 00000 01110 00000 00000 00000",
      "(": "00010 00100 01000 01000 01000 00100 00010",
      ")": "01000 00100 00010 00010 00010 00100 01000",
    ]
  }

  static func textSize(_ t: String) -> Size {
    Size(w: max(0, t.count * Font.advance - 1), h: Font.glyphHeight)
  }

  static func drawText(_ t: String, in c: inout Canvas, at x: Int, y: Int, color: Pixel) {
    var cx = x
    for ch in t {
      if let glyph = Font.glyphs[ch] {
        for (row, line) in glyph.split(separator: " ").enumerated() {
          for (col, bit) in line.enumerated() where bit == "1" {
            c.set(x: cx + col, y: y + row, color)
          }
        }
      }
      cx += Font.advance
    }
  }

  // MARK: PNG (own encoder: CRC32, Adler32, stored deflate blocks)

  static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
      var v = UInt32(i)
      for _ in 0..<8 { v = (v & 1) != 0 ? 0xEDB88320 ^ (v >> 1) : v >> 1 }
      table[i] = v
    }
    var crc = UInt32(0xFFFF_FFFF)
    for b in bytes { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFF_FFFF
  }

  static func adler32(_ bytes: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for x in bytes {
      a = (a + UInt32(x)) % 65_521
      b = (b + a) % 65_521
    }
    return (b << 16) | a
  }

  static func appendBE32(_ out: inout [UInt8], _ v: UInt32) {
    out.append(UInt8(v >> 24 & 0xFF))
    out.append(UInt8(v >> 16 & 0xFF))
    out.append(UInt8(v >> 8 & 0xFF))
    out.append(UInt8(v & 0xFF))
  }

  static func chunk(_ out: inout [UInt8], _ type: String, _ data: [UInt8]) {
    appendBE32(&out, UInt32(data.count))
    let t = Array(type.utf8)
    out.append(contentsOf: t)
    out.append(contentsOf: data)
    appendBE32(&out, crc32(t + data))
  }

  static func writePNG(_ canvas: Canvas, to path: String) throws {
    var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    var ihdr: [UInt8] = []
    appendBE32(&ihdr, UInt32(canvas.width))
    appendBE32(&ihdr, UInt32(canvas.height))
    ihdr.append(8)   // bit depth
    ihdr.append(6)   // color type RGBA
    ihdr.append(0)   // compression: deflate
    ihdr.append(0)   // filter: adaptive
    ihdr.append(0)   // interlace: none
    chunk(&out, "IHDR", ihdr)

    // Raw scanlines, filter byte 0 each, then a zlib stream of stored
    // (uncompressed) deflate blocks.
    var raw: [UInt8] = []
    raw.reserveCapacity(canvas.height * (1 + canvas.width * 4))
    for y in 0..<canvas.height {
      raw.append(0)
      raw.append(contentsOf: canvas.row(y))
    }
    var idat: [UInt8] = [0x78, 0x01]  // zlib: deflate, 32K window, fastest
    var i = 0
    while i < raw.count {
      let n = min(65_535, raw.count - i)
      idat.append(i + n >= raw.count ? 1 : 0)  // BFINAL, BTYPE 00 = stored
      idat.append(UInt8(n & 0xFF))
      idat.append(UInt8(n >> 8 & 0xFF))
      idat.append(UInt8(~n & 0xFF))
      idat.append(UInt8(~n >> 8 & 0xFF))
      idat.append(contentsOf: raw[i..<i + n])
      i += n
    }
    appendBE32(&idat, adler32(raw))
    chunk(&out, "IDAT", idat)
    chunk(&out, "IEND", [])
    try Data(out).write(to: URL(fileURLWithPath: path))
  }
}

struct Pixel {
  let r: UInt8
  let g: UInt8
  let b: UInt8
  static let white = Pixel(r: 255, g: 255, b: 255)
}

struct Canvas {
  let width: Int
  let height: Int
  var pixels: [UInt8]  // RGBA, one pixel per point

  init(width: Int, height: Int, fill: Pixel) {
    self.width = width
    self.height = height
    pixels = [UInt8](repeating: 0, count: width * height * 4)
    for i in 0..<(width * height) {
      pixels[i * 4] = fill.r
      pixels[i * 4 + 1] = fill.g
      pixels[i * 4 + 2] = fill.b
      pixels[i * 4 + 3] = 255
    }
  }

  func row(_ y: Int) -> ArraySlice<UInt8> {
    pixels[y * width * 4..<(y + 1) * width * 4]
  }

  mutating func set(x: Int, y: Int, _ p: Pixel) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let i = (y * width + x) * 4
    pixels[i] = p.r
    pixels[i + 1] = p.g
    pixels[i + 2] = p.b
    pixels[i + 3] = 255
  }
}
