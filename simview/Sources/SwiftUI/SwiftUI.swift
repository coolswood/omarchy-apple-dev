// Our SwiftUI implementation for Linux, milestone M2 of the simulation
// ladder in docs/IOS-SIMULATION-LINUX.md. The demo app in sdk-free/swiftui
// compiles here unchanged and renders one frame to a PNG on the CPU.
//
// Ours end to end: these declarations, the 5 x 7 bitmap glyphs, the layout
// and raster pass, and the PNG encoder. No Apple source, no third-party code.
//
// Not in this module: real SwiftUI layout, font shaping, animation, Metal.
// M3 adds scripted touch frames. M5 adds vertical scrolling. M6 adds key
// records, text insertion, and text field focus.

import Foundation

// MARK: - Public API surface (same shape as sdk-free/swiftui/SwiftUI.swift)

public typealias CGFloat = Double

@resultBuilder
public enum ViewBuilder {
  public static func buildBlock() -> EmptyView { EmptyView() }
  public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
  public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1)
    -> TupleView<(C0, C1)> { TupleView((c0, c1)) }
  public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2)
    -> TupleView<(TupleView<(C0, C1)>, C2)> { TupleView((TupleView((c0, c1)), c2)) }
  public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(
    _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
  ) -> TupleView<(TupleView<(TupleView<(C0, C1)>, C2)>, C3)> {
    TupleView((TupleView((TupleView((c0, c1)), c2)), c3))
  }
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
  // Entry point for @main apps. Without --frames: render once (M2 behavior).
  // With --frames: run the M3 touch loop, then write the final render.
  static func main() {
    var path: String?
    var framesPath: String?
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
      if a == "--out" { path = it.next() }
      if a == "--frames" { framesPath = it.next() }
    }
    guard let out = path else {
      FileHandle.standardError.write(Data("usage: \(CommandLine.arguments[0]) --out <file.png> [--frames <file.json>]\n".utf8))
      exit(2)
    }
    if let framesFile = framesPath {
      let frames = Sim.loadFrames(framesFile)
      // Every pass rebuilds the whole tree, app included, so each pass
      // creates the @State wrappers in the same order and reclaims the
      // same slots. App-level state then re-renders too.
      let canvas = Sim.run(frames: frames) {
        Sim.beginStatePass()
        let app = Self()
        let scene = app.body
        let (c, p) = Sim.render(scene._simSceneSpec())
        return (c, p, [scene, app])
      }
      do {
        try Sim.writePNG(canvas, to: out)
      } catch {
        FileHandle.standardError.write(Data("simview: \(error)\n".utf8))
        exit(1)
      }
      print("wrote \(out) \(canvas.width)x\(canvas.height)")
    } else {
      Sim.beginStatePass()
      let app = Self()
      let (canvas, _) = Sim.render(app.body._simSceneSpec())
      do {
        try Sim.writePNG(canvas, to: out)
      } catch {
        FileHandle.standardError.write(Data("simview: \(error)\n".utf8))
        exit(1)
      }
      print("wrote \(out) \(canvas.width)x\(canvas.height)")
    }
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
// protocol requirements above expose it; app code never names it. The button
// carries its action so the touch loop can fire it. M4 adds the navigation
// cases: `.link` holds a label and a destination builder until the stack
// rewrites it into a button that pushes; `.titled` carries a navigationTitle;
// `.navstack` draws the bar and holds the screen below it; `.hairline` is a
// 1 point separator line.
public enum Spec {
  case empty
  case text(String)
  indirect case button(Spec, () -> Void)
  indirect case tuple([Spec])
  indirect case vstack(HorizontalAlignment, spacing: Int, children: [Spec])
  indirect case link(Spec, () -> Spec)
  indirect case titled(String, Spec)
  case hairline
  indirect case navstack(String?, (() -> Void)?, Spec)
  indirect case scrollview(Binding<Int>, Spec)
  // M6: a text field. The binding carries the text, the string is the
  // placeholder, the closure fires on Return.
  indirect case textfield(Binding<String>, String, (() -> Void)?)
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
  let action: () -> Void
  let label: Label
  public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.action = action
    self.label = label()
  }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .button(label._simSpec(), action) }
}

extension Button where Label == Text {
  public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) {
    self.init(action: action, label: { Text(title) })
  }
}

// MARK: - Navigation (M4)

// Pushes its destination when tapped. The enclosing NavigationStack rewrites
// the `.link` node into a button whose action appends the destination
// builder to the stack, so the destination is rebuilt on every pass like the
// rest of the tree and its @State stays live. Outside a stack it never lays
// out.
public struct NavigationLink<Label: View, Destination: View>: View {
  let label: Label
  let destination: Destination
  public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.destination = destination()
  }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec {
    .link(label._simSpec(), { [destination] in destination._simSpec() })
  }
}

extension NavigationLink where Label == Text {
  public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> Destination) {
    self.init(destination: destination, label: { Text(title) })
  }
}

// Leading-aligned stack of rows with a separator line between rows. Rows are
// buttons or links laid out like any stack child; the hit area stays the
// label rect, as in M3.
public struct List<Content: View>: View {
  let content: Content
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec {
    let kids = Sim.flattened(content._simSpec())
    var rows: [Spec] = []
    for k in kids {
      rows.append(k)
      rows.append(.hairline)
    }
    return .vstack(HorizontalAlignment(kind: .leading), spacing: 16, children: rows)
  }
}

// A vertical scroll viewport. Dragging changes the content offset.
public struct ScrollView<Content: View>: View {
  @State private var offset = 0
  let content: Content
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .scrollview($offset, content._simSpec()) }
}

// MARK: - Text input (M6)

// A text field. The text lives in a binding the caller owns. A completed
// tap focuses the field; a tap anywhere else blurs it. Typed characters
// append at the caret, which always sits at the end. Backspace removes one
// character and stops at empty. Return fires `onSubmit` when present and
// always blurs. Shift and caps lock are not implemented.
public struct TextField: View {
  let placeholder: String
  let text: Binding<String>
  let onSubmit: (() -> Void)?

  public init(_ placeholder: String, text: Binding<String>,
              onSubmit: (() -> Void)? = nil) {
    self.placeholder = placeholder
    self.text = text
    self.onSubmit = onSubmit
  }

  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .textfield(text, placeholder, onSubmit) }
}

public struct Titled<Content: View>: View {
  let title: String
  let content: Content
  public init(title: String, content: Content) {
    self.title = title
    self.content = content
  }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }
  public func _simSpec() -> Spec { .titled(title, content._simSpec()) }
}

public extension View {
  func navigationTitle(_ title: String) -> Titled<Self> {
    Titled(title: title, content: self)
  }
}

// Holds the pushed screens. `path` stores one destination builder per push;
// each pass rebuilds the top screen through it, so destination @State keeps
// its pooled box and re-renders like root state. The back button pops one
// level; its hit area is its label rect, laid by the bar.
public struct NavigationStack<Content: View>: View {
  @State private var path: [() -> Spec] = []
  let content: Content
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
  public typealias Body = EmptyView
  public var body: EmptyView { EmptyView() }

  // Turns `.link` nodes into buttons that push. Destinations are not walked
  // here; they are rebuilt through the stored builders and rewritten on the
  // pass that shows them, so a pushed link pushes onto the same stack.
  private func pushable(_ s: Spec) -> Spec {
    switch s {
    case .link(let label, let build):
      return .button(label, { self.path.append(build) })
    case .button(let label, let action):
      return .button(pushable(label), action)
    case .tuple(let kids):
      return .tuple(kids.map(pushable))
    case .vstack(let alignment, let spacing, let kids):
      return .vstack(alignment, spacing: spacing, children: kids.map(pushable))
    case .titled(let title, let child):
      return .titled(title, pushable(child))
    default:
      return s
    }
  }

  public func _simSpec() -> Spec {
    let root = pushable(content._simSpec())
    let screen: Spec
    if let build = path.last {
      screen = pushable(build())
    } else {
      screen = root
    }
    let back: (() -> Void)? = path.isEmpty ? nil : { self.path.removeLast() }
    return .navstack(Sim.firstTitle(screen), back, screen)
  }
}

@propertyWrapper
public struct State<Value> {
  // Value cell, pooled by position. Every render pass rebuilds the view
  // tree from scratch, and each pass creates the wrappers in the same
  // order, so a wrapper's creation index names its slot. A box claimed in
  // an earlier pass is reused at the same index, which is how an action
  // closure and the next render share one value. The setter needs no
  // mutable self, which is why it is nonmutating.
  final class Box {
    var value: Value
    init(_ value: Value) { self.value = value }
  }
  var box: Box
  public init(wrappedValue: Value) {
    let i = Sim.nextStateSlot()
    if i < Sim.stateBoxes.count, let reused = Sim.stateBoxes[i] as? Box {
      box = reused
    } else {
      precondition(i == Sim.stateBoxes.count,
                   "simview: state slot \(i) changed shape between renders")
      box = Box(wrappedValue)
      Sim.stateBoxes.append(box)
    }
  }
  public var wrappedValue: Value {
    get { box.value }
    nonmutating set { box.value = newValue }
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
  // Text field box, fixed size. Text wider than the box overflows; the
  // field does not scroll.
  static let fieldWidth = 60
  static let fieldHeight = 9
  // Focus owner: the id of the focused text field, or nil. Set by the
  // touch loop on a completed tap and cleared by blur.
  static var focusField: Int?
  // Field ids, assigned in layout order like button ids.
  static var nextFieldId = 1

  // @State slot pool, see State. beginStatePass() goes with the start of
  // one tree build; wrappers then claim indexes in creation order.
  static var stateBoxes: [AnyObject] = []
  static var stateSlotCursor = 0
  static func beginStatePass() { stateSlotCursor = 0 }
  static func nextStateSlot() -> Int {
    defer { stateSlotCursor += 1 }
    return stateSlotCursor
  }

  static func flattened(_ s: Spec) -> [Spec] {
    if case .tuple(let kids) = s { return kids.flatMap(flattened) }
    return [s]
  }

  // MARK: layout

  static func measure(_ s: Spec) -> Size {
    switch s {
    case .empty:
      return Size(w: 0, h: 0)
    case .text(let t):
      return textSize(t)
    case .button(let inner, _):
      return measure(inner)
    case .tuple:
      return stackSize(flattened(s), spacing: 0)
    case .vstack(_, let spacing, let kids):
      return stackSize(kids.flatMap(flattened), spacing: spacing)
    case .hairline:
      return Size(w: 0, h: 1)
    case .titled(_, let child):
      return measure(child)
    case .link:
      preconditionFailure("simview: NavigationLink outside a NavigationStack")
    case .scrollview:
      return Size(w: screenWidth, h: screenHeight)
    case .textfield:
      return Size(w: fieldWidth, h: fieldHeight)
    case .navstack:
      return Size(w: screenWidth, h: screenHeight)
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

  // One node placed by the layout pass, in draw order. Later nodes draw on
  // top, so hit testing walks them in reverse. Button nodes carry their id
  // and action; their label text is a separate node and does the drawing.
  struct PlacedNode {
    let spec: Spec
    let x: Int
    let y: Int
    let w: Int
    let h: Int
    let color: Pixel
    let buttonId: Int?
    let action: (() -> Void)?
    var fieldId: Int? = nil
  }

  static func layout(_ s: Spec, at x: Int, y: Int, width: Int, color: Pixel,
                     nextButton: inout Int, into out: inout [PlacedNode]) {
    let size = measure(s)
    switch s {
    case .empty:
      break
    case .text:
      out.append(PlacedNode(spec: s, x: x, y: y, w: size.w, h: size.h,
                            color: color, buttonId: nil, action: nil))
    case .button(let inner, let action):
      let id = nextButton
      nextButton += 1
      out.append(PlacedNode(spec: s, x: x, y: y, w: size.w, h: size.h,
                            color: blue, buttonId: id, action: action))
      layout(inner, at: x, y: y, width: size.w, color: blue,
             nextButton: &nextButton, into: &out)
    case .tuple:
      layoutStack(flattened(s), spacing: 0, at: x, y: y, width: width,
                  alignment: HorizontalAlignment(kind: .center), color: color,
                  nextButton: &nextButton, into: &out)
    case .vstack(let alignment, let spacing, let kids):
      layoutStack(kids.flatMap(flattened), spacing: spacing, at: x, y: y,
                  width: width, alignment: alignment, color: color,
                  nextButton: &nextButton, into: &out)
    case .hairline:
      out.append(PlacedNode(spec: s, x: x, y: y, w: max(width, 1), h: 1,
                            color: Pixel.separator, buttonId: nil, action: nil))
    case .titled(_, let child):
      layout(child, at: x, y: y, width: width, color: color,
             nextButton: &nextButton, into: &out)
    case .link:
      preconditionFailure("simview: NavigationLink outside a NavigationStack")
    case .scrollview(let offset, let content):
      out.append(PlacedNode(spec: s, x: x, y: y, w: screenWidth, h: screenHeight,
                            color: color, buttonId: nil, action: nil))
      layout(content, at: 0, y: -offset.get(), width: screenWidth, color: color,
             nextButton: &nextButton, into: &out)
    case .textfield:
      let id = nextFieldId
      nextFieldId += 1
      out.append(PlacedNode(spec: s, x: x, y: y, w: fieldWidth, h: fieldHeight,
                            color: color, buttonId: nil, action: nil, fieldId: id))
    case .navstack(let title, let back, let screen):
      layoutNavStack(title, back, screen, nextButton: &nextButton, into: &out)
    }
  }

  // The navigation bar: 44 points tall, title centered in it, an optional
  // back button whose hit area is its label rect, a separator line at the
  // bar's bottom edge. The screen lays out centered in the area below.
  static let navBarHeight = 44

  static func layoutNavStack(_ title: String?, _ back: (() -> Void)?,
                             _ screen: Spec, nextButton: inout Int,
                             into out: inout [PlacedNode]) {
    if let t = title {
      let size = textSize(t)
      out.append(PlacedNode(spec: .text(t), x: (screenWidth - size.w) / 2,
                            y: (navBarHeight - size.h) / 2, w: size.w, h: size.h,
                            color: black, buttonId: nil, action: nil))
    }
    // The back button: its hit area is its label rect, like every button.
    let backLabel = "< Back"
    let backSize = textSize(backLabel)
    let backX = 12
    let backY = (navBarHeight - backSize.h) / 2
    if let pop = back {
      let id = nextButton
      nextButton += 1
      out.append(PlacedNode(spec: .text(backLabel), x: backX, y: backY,
                            w: backSize.w, h: backSize.h, color: blue,
                            buttonId: id, action: pop))
    }
    out.append(PlacedNode(spec: .hairline, x: 0, y: navBarHeight - 1,
                          w: screenWidth, h: 1, color: Pixel.separator,
                          buttonId: nil, action: nil))
    let size = measure(screen)
    layout(screen, at: (screenWidth - size.w) / 2,
           y: navBarHeight + (screenHeight - navBarHeight - size.h) / 2,
           width: size.w, color: black, nextButton: &nextButton, into: &out)
  }

  static func layoutStack(_ kids: [Spec], spacing: Int, at x: Int, y: Int,
                          width: Int, alignment: HorizontalAlignment,
                          color: Pixel, nextButton: inout Int,
                          into out: inout [PlacedNode]) {
    var cy = y
    for k in kids {
      let ks = measure(k)
      // A separator line spans the stack's content width whatever the
      // alignment, so list rows read as rows.
      if case .hairline = k {
        out.append(PlacedNode(spec: k, x: x, y: cy, w: max(width, 1), h: 1,
                              color: Pixel.separator, buttonId: nil, action: nil))
        cy += 1 + spacing
        continue
      }
      let kx: Int
      switch alignment.kind {
      case .center: kx = x + (width - ks.w) / 2
      case .leading: kx = x
      case .trailing: kx = x + width - ks.w
      }
      layout(k, at: kx, y: cy, width: ks.w, color: color,
             nextButton: &nextButton, into: &out)
      cy += ks.h + spacing
    }
  }

  static func draw(_ placed: [PlacedNode], into c: inout Canvas) {
    for p in placed {
      switch p.spec {
      case .text(let t):
        drawText(t, in: &c, at: p.x, y: p.y, color: p.color)
      case .hairline:
        for y in p.y..<p.y + p.h {
          for x in p.x..<p.x + p.w {
            c.set(x: x, y: y, p.color)
          }
        }
      case .textfield(let text, let placeholder, _):
        let value = text.get()
        if value.isEmpty {
          drawText(placeholder, in: &c, at: p.x, y: p.y, color: Pixel.placeholder)
        } else {
          drawText(value, in: &c, at: p.x, y: p.y, color: p.color)
        }
        for x in p.x..<p.x + p.w {
          c.set(x: x, y: p.y + p.h - 1, Pixel.separator)
        }
        if focusField == p.fieldId {
          let caretX = p.x + (value.isEmpty ? 0 : textSize(value).w + 1)
          for row in 0..<Font.glyphHeight {
            c.set(x: caretX, y: p.y + row, p.color)
          }
        }
      default:
        break
      }
    }
  }

  static func render(_ spec: Spec) -> (Canvas, [PlacedNode]) {
    var c = Canvas(width: screenWidth, height: screenHeight, fill: Pixel.white)
    var placed: [PlacedNode] = []
    var nextButton = 1
    nextFieldId = 1
    let s = measure(spec)
    layout(spec, at: (screenWidth - s.w) / 2, y: (screenHeight - s.h) / 2,
           width: s.w, color: black, nextButton: &nextButton, into: &placed)
    draw(placed, into: &c)
    return (c, placed)
  }

  // The title of a screen: the outermost navigationTitle on it. A pushed
  // screen is rebuilt each pass, so its title is read from its own spec.
  static func firstTitle(_ s: Spec) -> String? {
    if case .titled(let t, _) = s { return t }
    switch s {
    case .button(let label, _):
      return firstTitle(label)
    case .tuple(let kids):
      return kids.lazy.compactMap(firstTitle).first
    case .vstack(_, _, let kids):
      return kids.lazy.compactMap(firstTitle).first
    default:
      return nil
    }
  }

  // MARK: touch input (M3, docs/SIM-INPUT-MODEL.md)

  enum Phase: String {
    case began, moved, ended, cancelled, stationary
  }

  struct FingerRec {
    let finger: Int
    let phase: Phase
    let x: Int
    let y: Int
  }

  struct Frame {
    let tMs: Int
    let fingers: [FingerRec]
    let key: Int?          // USB keyboard usage, page 7
    let insert: Character? // by-character text insertion
  }

  static func framesFail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("frames: \(msg)\n".utf8))
    exit(2)
  }

  static func fingerRec(_ dict: [String: Any], frame i: Int, record j: Int) -> FingerRec {
    func named(_ k: String) -> Int {
      guard let v = dict[k] as? Int else {
        framesFail("frame \(i) finger \(j): missing or non-integer \(k)")
      }
      return v
    }
    let n = named("finger")
    guard (0...9).contains(n) else { framesFail("frame \(i) finger \(j): finger \(n) is out of range 0 to 9") }
    guard let raw = dict["phase"] as? String, let phase = Phase(rawValue: raw) else {
      framesFail("frame \(i) finger \(j): phase must be began, moved, ended, cancelled or stationary")
    }
    return FingerRec(finger: n, phase: phase, x: named("x"), y: named("y"))
  }

  // Loads and validates a frames file. A {"tap": [x, y]} entry expands to a
  // began frame and an ended frame 80 ms apart. M6 adds two record kinds: a
  // {"key": n} frame presses the USB keyboard usage n (page 7), and a
  // {"text": "c"} frame inserts one character. A frame holds at most one of
  // fingers, key, and text. Refuses out-of-order t_ms, naming the frame
  // index.
  static func loadFrames(_ path: String) -> [Frame] {
    guard let data = FileManager.default.contents(atPath: path) else {
      framesFail("cannot read \(path)")
    }
    let obj: Any
    do {
      obj = try JSONSerialization.jsonObject(with: data)
    } catch {
      framesFail("\(path): \(error)")
    }
    guard let arr = obj as? [Any] else { framesFail("\(path): root must be an array") }
    var out: [Frame] = []
    var prevT: Int?
    for (i, item) in arr.enumerated() {
      if let short = item as? [String: Any], let tap = short["tap"] as? [Any] {
        guard tap.count == 2, let x = tap[0] as? Int, let y = tap[1] as? Int else {
          framesFail("frame \(i): tap must be [x, y]")
        }
        let t = (short["t_ms"] as? Int) ?? (prevT ?? 0)
        if let prev = prevT, t < prev { framesFail("frame \(i): t_ms \(t) goes backward (previous \(prev))") }
        out.append(Frame(tMs: t, fingers: [FingerRec(finger: 0, phase: .began, x: x, y: y)],
                         key: nil, insert: nil))
        out.append(Frame(tMs: t + 80, fingers: [FingerRec(finger: 0, phase: .ended, x: x, y: y)],
                         key: nil, insert: nil))
        prevT = t + 80
        continue
      }
      guard let dict = item as? [String: Any] else { framesFail("frame \(i): not an object") }
      guard let t = dict["t_ms"] as? Int else { framesFail("frame \(i): missing t_ms") }
      if let prev = prevT, t < prev { framesFail("frame \(i): t_ms \(t) goes backward (previous \(prev))") }
      if let usage = dict["key"] as? Int {
        guard dict["fingers"] == nil, dict["text"] == nil else {
          framesFail("frame \(i): hold at most one of fingers, key, text")
        }
        guard (0...255).contains(usage) else {
          framesFail("frame \(i): key \(usage) is out of range 0 to 255")
        }
        out.append(Frame(tMs: t, fingers: [], key: usage, insert: nil))
        prevT = t
        continue
      }
      if let s = dict["text"] as? String {
        guard dict["fingers"] == nil else {
          framesFail("frame \(i): hold at most one of fingers, key, text")
        }
        let chars = Array(s)
        guard chars.count == 1 else {
          framesFail("frame \(i): text must hold exactly one character")
        }
        out.append(Frame(tMs: t, fingers: [], key: nil, insert: chars[0]))
        prevT = t
        continue
      }
      guard let list = dict["fingers"] as? [Any], !list.isEmpty else {
        framesFail("frame \(i): fingers must be a non-empty list")
      }
      out.append(Frame(tMs: t, fingers: list.enumerated().map { j, f in
        guard let fd = f as? [String: Any] else {
          framesFail("frame \(i) finger \(j): not an object")
        }
        return fingerRec(fd, frame: i, record: j)
      }, key: nil, insert: nil))
      prevT = t
    }
    return out
  }

  // The touch rules of docs/SIM-INPUT-MODEL.md: the target is fixed at touch
  // down, the whole gesture shares it, and the action fires only when the
  // last finger ends inside that target. A cancelled finger kills the gesture.
  struct Gesture {
    var active = false
    var target: Int?
    var targetField: Int?
    var cancelled = false
    var down: Set<Int> = []
    var startX = 0
    var startY = 0
    var startOffset = 0
    var scroll: (Binding<Int>, Int)?

    mutating func process(_ rec: FingerRec, buttons: [PlacedNode]) -> (() -> Void)? {
      switch rec.phase {
      case .began:
        if !active {
          active = true
          if let node = hitTest(x: rec.x, y: rec.y, placed: buttons) {
            target = node.buttonId
            targetField = node.fieldId
          } else {
            target = nil
            targetField = nil
          }
          cancelled = false
          startX = rec.x
          startY = rec.y
          scroll = buttons.first(where: { node in
            guard case .scrollview = node.spec else { return false }
            return rec.x >= node.x && rec.x < node.x + node.w && rec.y >= node.y && rec.y < node.y + node.h
          }).flatMap { node in
            guard case .scrollview(let binding, let content) = node.spec else { return nil }
            return (binding, max(0, measure(content).h - screenHeight))
          }
          startOffset = scroll?.0.get() ?? 0
          down = []
        }
        down.insert(rec.finger)
        return nil
      case .moved:
        down.insert(rec.finger)
        let dx = rec.x - startX
        let dy = rec.y - startY
        if dx * dx + dy * dy > 64, let (binding, maximum) = scroll {
          cancelled = true
          binding.set(min(max(startOffset - dy, 0), maximum))
        }
        return nil
      case .ended:
        down.remove(rec.finger)
        guard active, !cancelled, down.isEmpty else { return nil }
        // A completed tap focuses a tapped field, or blurs. A cancelled
        // gesture never reaches this point.
        if let f = targetField {
          focusField = f
        } else {
          focusField = nil
        }
        guard let id = target,
              let node = buttons.last(where: { $0.buttonId == id }),
              rec.x >= node.x, rec.x < node.x + node.w,
              rec.y >= node.y, rec.y < node.y + node.h else { return nil }
        return node.action
      case .cancelled:
        down.remove(rec.finger)
        cancelled = true
        return nil
      case .stationary:
        down.insert(rec.finger)
        return nil
      }
    }

    mutating func endIfDone() {
      if down.isEmpty {
        active = false
        target = nil
        targetField = nil
        cancelled = false
        scroll = nil
      }
    }
  }

  static func targetName(_ id: Int?) -> String {
    id.map { "Button#\($0)" } ?? "none"
  }

  // Lists every @State value reachable from the scene and the app, as
  // name:value pairs, by reflection. A wrapper stores its box under the
  // property name with a leading underscore, and the box holds the value.
  // The walk descends into any child that itself has reflective children,
  // which covers view structs, stacks and tuples; leaves like String, Int
  // and closures have none and stop the walk. The scene carries the view
  // tree; the app carries any @State declared on the App struct.
  static func stateDescription(_ roots: [Any]) -> String {
    var parts: [String] = []
    var seen: Set<ObjectIdentifier> = []
    for root in roots {
      collectState(root, into: &parts, seen: &seen)
    }
    return parts.joined(separator: ",")
  }

  static func collectState(_ value: Any, into parts: inout [String],
                           seen: inout Set<ObjectIdentifier>) {
    // Only class instances can form reference cycles. Mirror boxing makes
    // `as? AnyObject` succeed for every value, so the display style decides
    // and the cast below runs only for real class instances.
    if Mirror(reflecting: value).displayStyle == .class {
      let object = value as AnyObject
      if !seen.insert(ObjectIdentifier(object)).inserted {
        return
      }
    }
    for child in Mirror(reflecting: value).children {
      if let label = child.label, label.hasPrefix("_"),
         let box = Mirror(reflecting: child.value).children.first?.value,
         let val = Mirror(reflecting: box).children.first?.value {
        parts.append("\(label.dropFirst()):\(val)")
        continue
      }
      if !Mirror(reflecting: child.value).children.isEmpty {
        collectState(child.value, into: &parts, seen: &seen)
      }
    }
  }

  // Topmost visible element under the point: a button or a text field.
  // Later nodes draw on top, so the walk goes in reverse draw order.
  static func hitTest(x: Int, y: Int, placed: [PlacedNode]) -> PlacedNode? {
    for node in placed.reversed() where node.buttonId != nil || node.fieldId != nil {
      if x >= node.x, x < node.x + node.w, y >= node.y, y < node.y + node.h {
        return node
      }
    }
    return nil
  }

  // One warning line per dropped key or text record.
  static func warn(_ msg: String) {
    print("warning: \(msg)")
  }

  // The live text field targets, keyed by field id, from the last layout.
  struct FieldTarget {
    let text: Binding<String>
    let onSubmit: (() -> Void)?
  }

  static func fieldMap(_ placed: [PlacedNode]) -> [Int: FieldTarget] {
    var out: [Int: FieldTarget] = [:]
    for node in placed {
      guard let id = node.fieldId,
            case .textfield(let text, _, let onSubmit) = node.spec else { continue }
      out[id] = FieldTarget(text: text, onSubmit: onSubmit)
    }
    return out
  }

  // Routes one key record to the focused field only. Usage numbers are USB
  // keyboard (page 7): 40 is Return, 42 is Backspace. Return fires onSubmit
  // when present and always blurs. A key with no focus, or a usage the field
  // does not map, is dropped with a warning line.
  static func routeKey(_ usage: Int, fields: [Int: FieldTarget], tMs: Int) -> String {
    guard let id = focusField, let field = fields[id] else {
      warn("key \(usage) dropped (no focus)")
      return "t=\(tMs) key=\(usage) field=none"
    }
    switch usage {
    case 42:
      field.text.set(String(field.text.get().dropLast()))
    case 40:
      field.onSubmit?()
      focusField = nil
    default:
      warn("key \(usage) dropped (no mapping)")
    }
    let label = focusField.map { "Field#\($0)" } ?? "none"
    return "t=\(tMs) key=\(usage) field=\(label)"
  }

  // Routes one text insertion to the focused field only. The caret sits at
  // the end, so the character appends.
  static func routeText(_ ch: Character, fields: [Int: FieldTarget], tMs: Int) -> String {
    guard let id = focusField, let field = fields[id] else {
      warn("text \(ch) dropped (no focus)")
      return "t=\(tMs) text=\(ch) field=none"
    }
    field.text.set(field.text.get() + String(ch))
    return "t=\(tMs) text=\(ch) field=Field#\(id)"
  }

  // The M3 loop: validate first, then walk the frames. Each frame fires the
  // actions the touch rules allow, routes key and text records to the
  // focused field, rebuilds and re-renders the tree, and logs one line per
  // record after that render succeeds.
  static func run(frames: [Frame], build: () -> (Canvas, [PlacedNode], [Any])) -> Canvas {
    focusField = nil
    var (canvas, placed, roots) = build()
    for node in placed where node.buttonId != nil {
      print("button id=\(node.buttonId!) rect=\(node.x),\(node.y),\(node.w),\(node.h)")
    }
    for node in placed where node.fieldId != nil {
      print("field id=\(node.fieldId!) rect=\(node.x),\(node.y),\(node.w),\(node.h)")
    }
    var gesture = Gesture()
    var fields = fieldMap(placed)
    for frame in frames {
      var lines: [String] = []
      if let usage = frame.key {
        lines.append(routeKey(usage, fields: fields, tMs: frame.tMs)
          + " state=\(stateDescription(roots))")
      } else if let ch = frame.insert {
        lines.append(routeText(ch, fields: fields, tMs: frame.tMs)
          + " state=\(stateDescription(roots))")
      } else {
        for rec in frame.fingers {
          if let action = gesture.process(rec, buttons: placed) {
            action()
          }
          let label = gesture.targetField.map { "Field#\($0)" } ?? targetName(gesture.target)
          lines.append("t=\(frame.tMs) finger=\(rec.finger) \(rec.phase.rawValue) "
            + "(\(rec.x),\(rec.y)) target=\(label) "
            + "state=\(stateDescription(roots))")
        }
      }
      gesture.endIfDone()
      (canvas, placed, roots) = build()
      fields = fieldMap(placed)
      for line in lines {
        print(line + " render=ok")
      }
    }
    return canvas
  }

  // MARK: glyphs

  struct Size { let w: Int; let h: Int }

  // Hand-drawn 5 x 7 glyphs, rows of 5 bits, only the ASCII the demo apps
  // need. The five descender glyphs (g j p q y) carry two extra rows below
  // the baseline, so they are 5 x 9. Unknown characters advance one cell and
  // draw nothing.
  enum Font {
    static let glyphWidth = 5
    static let glyphHeight = 7
    static let descenderExtra = 2
    static let advance = 6     // glyph plus one column gap
    static let descenders: Set<Character> = ["g", "j", "p", "q", "y"]
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
      "g": "00000 00000 01111 10001 10001 10001 01111 00001 01110",
      "h": "10000 10000 11110 10001 10001 10001 10001",
      "i": "00100 00000 00100 00100 00100 00100 00100",
      "j": "00010 00000 00010 00010 00010 00010 00010 10010 01100",
      "k": "10000 10010 10100 11000 10100 10010 10001",
      "l": "01100 00100 00100 00100 00100 00100 01110",
      "m": "00000 00000 11110 10101 10101 10101 10101",
      "n": "00000 00000 11110 10001 10001 10001 10001",
      "o": "00000 00000 01110 10001 10001 10001 01110",
      "p": "00000 00000 11110 10001 10001 10001 11110 10000 10000",
      "q": "00000 00000 01111 10001 10001 10001 01111 00001 00001",
      "r": "00000 00000 01110 10001 10000 10000 10000",
      "s": "00000 00000 01111 10000 01110 00001 11110",
      "t": "01000 01000 11100 01000 01000 01000 00110",
      "u": "00000 00000 10001 10001 10001 10011 01101",
      "v": "00000 00000 10001 10001 10001 01010 00100",
      "w": "00000 00000 10001 10001 10101 10101 01010",
      "x": "00000 00000 10001 01010 00100 01010 10001",
      "y": "00000 00000 10001 10001 10001 01111 00001 00001 01110",
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
      "<": "00010 00100 01000 10000 01000 00100 00010",
      "(": "00010 00100 01000 01000 01000 00100 00010",
      ")": "01000 00100 00010 00010 00010 00100 01000",
    ]
  }

  static func textSize(_ t: String) -> Size {
    let descends = t.contains(where: { Font.descenders.contains($0) })
    return Size(w: max(0, t.count * Font.advance - 1),
                h: Font.glyphHeight + (descends ? Font.descenderExtra : 0))
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
  static let separator = Pixel(r: 0xE5, g: 0xE5, b: 0xE5)  // #E5E5EA-ish
  static let placeholder = Pixel(r: 0x8A, g: 0x8A, b: 0x8A)
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
