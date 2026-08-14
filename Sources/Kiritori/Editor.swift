import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 図形モデル

enum ToolKind: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, pen, highlight, text, mosaic
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "scribble"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3"
        }
    }

    var label: String {
        switch self {
        case .select: return "選択/移動"
        case .arrow: return "矢印"
        case .line: return "直線"
        case .rect: return "四角"
        case .ellipse: return "楕円"
        case .pen: return "ペン"
        case .highlight: return "ハイライト"
        case .text: return "テキスト(ダブルクリックで再編集)"
        case .mosaic: return "モザイク"
        }
    }
}

struct DrawShape: Identifiable {
    let id = UUID()
    var tool: ToolKind
    var start: CGPoint          // 画像ポイント座標(top-left 原点)
    var end: CGPoint
    var points: [CGPoint] = []  // pen / highlight 用
    var color: Color
    var lineWidth: CGFloat
    var text: String = ""
    var fontSize: CGFloat = 24
    var mosaicImage: CGImage?

    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

// MARK: - モザイク生成

enum Pixelator {
    static func pixelate(_ capture: Capture, rectInPoints: CGRect, block: CGFloat = 14) -> CGImage? {
        let scale = capture.scale
        var px = CGRect(
            x: rectInPoints.minX * scale,
            y: rectInPoints.minY * scale,
            width: rectInPoints.width * scale,
            height: rectInPoints.height * scale
        ).integral
        px = px.intersection(CGRect(x: 0, y: 0, width: capture.cgImage.width, height: capture.cgImage.height))
        guard px.width >= 2, px.height >= 2,
              let crop = capture.cgImage.cropping(to: px) else { return nil }

        let smallW = max(1, Int(px.width / block))
        let smallH = max(1, Int(px.height / block))
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let down = CGContext(
            data: nil, width: smallW, height: smallH,
            bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info
        ) else { return nil }
        down.interpolationQuality = .medium
        down.draw(crop, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let small = down.makeImage() else { return nil }

        guard let up = CGContext(
            data: nil, width: Int(px.width), height: Int(px.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info
        ) else { return nil }
        up.interpolationQuality = .none
        up.draw(small, in: CGRect(x: 0, y: 0, width: px.width, height: px.height))
        return up.makeImage()
    }
}

// MARK: - 描画(プレビューと書き出しで共用)

enum ShapeRenderer {
    static func draw(_ shape: DrawShape, in ctx: inout GraphicsContext) {
        let style = StrokeStyle(lineWidth: shape.lineWidth, lineCap: .round, lineJoin: .round)
        switch shape.tool {
        case .select:
            break

        case .line:
            var p = Path()
            p.move(to: shape.start)
            p.addLine(to: shape.end)
            ctx.stroke(p, with: .color(shape.color), style: style)

        case .arrow:
            let head = arrowHead(from: shape.start, to: shape.end, lineWidth: shape.lineWidth)
            var p = Path()
            p.move(to: shape.start)
            p.addLine(to: shaftEnd(from: shape.start, to: shape.end, lineWidth: shape.lineWidth))
            ctx.stroke(p, with: .color(shape.color), style: style)
            ctx.fill(head, with: .color(shape.color))

        case .rect:
            let p = Path(roundedRect: shape.rect, cornerRadius: 2)
            ctx.stroke(p, with: .color(shape.color), style: style)

        case .ellipse:
            let p = Path(ellipseIn: shape.rect)
            ctx.stroke(p, with: .color(shape.color), style: style)

        case .pen:
            guard shape.points.count > 1 else { break }
            var p = Path()
            p.addLines(shape.points)
            ctx.stroke(p, with: .color(shape.color), style: style)

        case .highlight:
            guard shape.points.count > 1 else { break }
            var p = Path()
            p.addLines(shape.points)
            let hlStyle = StrokeStyle(lineWidth: highlightWidth(shape.lineWidth), lineCap: .round, lineJoin: .round)
            ctx.stroke(p, with: .color(shape.color.opacity(0.35)), style: hlStyle)

        case .text:
            guard !shape.text.isEmpty else { break }
            let t = Text(shape.text)
                .font(.system(size: shape.fontSize, weight: .semibold))
                .foregroundColor(shape.color)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1))
            shadowed.draw(t, at: shape.start, anchor: .topLeading)

        case .mosaic:
            if let m = shape.mosaicImage {
                ctx.draw(Image(decorative: m, scale: 1), in: shape.rect)
            } else {
                ctx.fill(Path(shape.rect), with: .color(.gray.opacity(0.6)))
            }
        }
    }

    static func highlightWidth(_ lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 5, 14)
    }

    /// 選択枠・当たり判定に使うバウンディングボックス(画像ポイント座標)
    static func bounds(of shape: DrawShape) -> CGRect {
        switch shape.tool {
        case .text:
            return textBounds(shape)
        case .pen, .highlight:
            guard let first = shape.points.first else { return shape.rect }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in shape.points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let pad = shape.tool == .highlight ? highlightWidth(shape.lineWidth) / 2 : shape.lineWidth
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -pad, dy: -pad)
        case .line, .arrow:
            return shape.rect.insetBy(dx: -shape.lineWidth, dy: -shape.lineWidth)
        default:
            return shape.rect
        }
    }

    static func textBounds(_ shape: DrawShape) -> CGRect {
        let font = NSFont.systemFont(ofSize: shape.fontSize, weight: .semibold)
        let size = (shape.text as NSString).size(withAttributes: [.font: font])
        return CGRect(origin: shape.start, size: CGSize(width: max(size.width, 10), height: max(size.height, 10)))
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x, aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2
        t = min(max(t, 0), 1)
        return hypot(p.x - (a.x + t * abx), p.y - (a.y + t * aby))
    }

    private static func shaftEnd(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> CGPoint {
        let len = headLength(lineWidth)
        let d = hypot(to.x - from.x, to.y - from.y)
        guard d > len else { return from }
        let ratio = (d - len * 0.8) / d
        return CGPoint(x: from.x + (to.x - from.x) * ratio, y: from.y + (to.y - from.y) * ratio)
    }

    private static func headLength(_ lineWidth: CGFloat) -> CGFloat {
        max(12, lineWidth * 3.5)
    }

    private static func arrowHead(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> Path {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let len = headLength(lineWidth)
        let a1 = angle + .pi * 0.85
        let a2 = angle - .pi * 0.85
        var p = Path()
        p.move(to: to)
        p.addLine(to: CGPoint(x: to.x + cos(a1) * len, y: to.y + sin(a1) * len))
        p.addLine(to: CGPoint(x: to.x + cos(a2) * len, y: to.y + sin(a2) * len))
        p.closeSubpath()
        return p
    }
}

// MARK: - 編集操作(Undo/Redo 用)

enum EditOp {
    case add(DrawShape)
    case remove(DrawShape, Int)
    case edit(DrawShape, DrawShape)   // (変更前, 変更後) 同じ id
}

// MARK: - モデル

final class EditorModel: ObservableObject {
    let capture: Capture

    @Published var shapes: [DrawShape] = []
    @Published var undoStack: [EditOp] = []
    @Published var redoStack: [EditOp] = []
    @Published var tool: ToolKind = .arrow
    @Published var color: Color = .red
    @Published var lineWidth: CGFloat = 3
    @Published var draft: DrawShape?
    @Published var selectedID: UUID?
    @Published var editingTextOrigin: CGPoint?
    @Published var textInput: String = ""
    /// テキスト編集セッションの識別子。TextField をセッションごとに作り直すために使う
    @Published var textSessionID = UUID()

    private enum DragState { case none, moving, drawing }
    private var dragState: DragState = .none
    private var dragStartPoint: CGPoint?
    private var moveOrigin: DrawShape?
    private var editingOriginal: DrawShape?
    private var editingOriginalIndex: Int?

    init(capture: Capture) {
        self.capture = capture
    }

    var pointSize: CGSize { capture.pointSize }

    var selectedShape: DrawShape? {
        guard let selectedID else { return nil }
        return shapes.first { $0.id == selectedID }
    }

    // MARK: ドラッグ

    func dragChanged(at raw: CGPoint) {
        let p = clamp(raw)

        if dragStartPoint == nil {
            dragStartPoint = p
            commitTextIfNeeded()

            // 選択中の図形をつかんだら、どのツールでも移動
            if let sel = selectedShape, hits(sel, p) {
                dragState = .moving
                moveOrigin = sel
                return
            }
            if tool == .select {
                if let idx = hitTest(p) {
                    selectedID = shapes[idx].id
                    moveOrigin = shapes[idx]
                    dragState = .moving
                } else {
                    selectedID = nil
                    dragState = .none
                }
                return
            }
            if tool == .text {
                dragState = .none
                return
            }
            selectedID = nil
            dragState = .drawing
            draft = DrawShape(tool: tool, start: p, end: p, points: [p], color: color, lineWidth: lineWidth)
            return
        }

        guard let start = dragStartPoint else { return }
        switch dragState {
        case .moving:
            guard let origin = moveOrigin, let sel = selectedID,
                  let idx = shapes.firstIndex(where: { $0.id == sel }) else { return }
            shapes[idx] = translated(origin, dx: p.x - start.x, dy: p.y - start.y)
        case .drawing:
            draft?.end = p
            if tool == .pen || tool == .highlight {
                draft?.points.append(p)
            }
        case .none:
            break
        }
    }

    func dragEnded(at raw: CGPoint) {
        let p = clamp(raw)
        defer {
            dragStartPoint = nil
            moveOrigin = nil
            dragState = .none
        }
        guard let start = dragStartPoint else { return }

        switch dragState {
        case .moving:
            guard let origin = moveOrigin, let sel = selectedID,
                  let idx = shapes.firstIndex(where: { $0.id == sel }) else { return }
            let dx = p.x - start.x, dy = p.y - start.y
            if abs(dx) < 0.5, abs(dy) < 0.5 {
                shapes[idx] = origin  // ただのクリック(選択のみ)
                return
            }
            var moved = translated(origin, dx: dx, dy: dy)
            if moved.tool == .mosaic {
                moved.mosaicImage = Pixelator.pixelate(capture, rectInPoints: moved.rect) ?? moved.mosaicImage
            }
            shapes[idx] = moved
            record(.edit(origin, moved))

        case .drawing:
            guard var d = draft else { return }
            draft = nil
            d.end = p
            if d.tool == .pen || d.tool == .highlight {
                d.points.append(p)
                guard d.points.count > 2 else { return }
            } else {
                guard d.rect.width >= 3 || d.rect.height >= 3 else { return }
            }
            if d.tool == .mosaic {
                d.mosaicImage = Pixelator.pixelate(capture, rectInPoints: d.rect)
            }
            shapes.append(d)
            record(.add(d))
            selectedID = d.id  // 描いた直後はそのまま掴んで動かせる

        case .none:
            if tool == .text {
                if let idx = hitTest(p), shapes[idx].tool == .text {
                    beginEdit(shapeAt: idx)  // 既存テキストはクリックで再編集
                } else {
                    editingTextOrigin = p
                    textInput = ""
                    textSessionID = UUID()
                }
            }
        }
    }

    // MARK: テキスト

    /// ダブルクリックで既存テキストを再編集
    func beginEditText(at p: CGPoint) {
        commitTextIfNeeded()
        guard let idx = hitTest(p), shapes[idx].tool == .text else { return }
        beginEdit(shapeAt: idx)
    }

    private func beginEdit(shapeAt idx: Int) {
        let shape = shapes.remove(at: idx)
        editingOriginal = shape
        editingOriginalIndex = idx
        editingTextOrigin = shape.start
        textInput = shape.text
        textSessionID = UUID()
        selectedID = nil
    }

    func commitTextIfNeeded() {
        guard let origin = editingTextOrigin else { return }
        editingTextOrigin = nil
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        textInput = ""

        if let original = editingOriginal {
            let index = min(editingOriginalIndex ?? shapes.count, shapes.count)
            editingOriginal = nil
            editingOriginalIndex = nil
            if trimmed.isEmpty {
                record(.remove(original, index))  // 空にしたら削除
            } else {
                var new = original
                new.text = trimmed
                shapes.insert(new, at: index)
                if new.text != original.text {
                    record(.edit(original, new))  // 変更がなければ履歴に積まない
                }
                selectedID = new.id
            }
            return
        }

        guard !trimmed.isEmpty else { return }
        var shape = DrawShape(tool: .text, start: origin, end: origin, color: color, lineWidth: lineWidth)
        shape.text = trimmed
        shapes.append(shape)
        record(.add(shape))
        selectedID = shape.id
    }

    // MARK: 選択操作

    func deleteSelected() {
        commitTextIfNeeded()
        guard let sel = selectedID, let idx = shapes.firstIndex(where: { $0.id == sel }) else { return }
        let shape = shapes.remove(at: idx)
        record(.remove(shape, idx))
        selectedID = nil
    }

    /// 色選択。図形を選択中ならその色も変える
    func setColor(_ c: Color) {
        color = c
        guard let sel = selectedID, let idx = shapes.firstIndex(where: { $0.id == sel }),
              shapes[idx].color != c else { return }
        let old = shapes[idx]
        var new = old
        new.color = c
        shapes[idx] = new
        record(.edit(old, new))
    }

    func selectTool(_ t: ToolKind) {
        commitTextIfNeeded()
        tool = t
    }

    // MARK: Undo / Redo

    func undo() {
        commitTextIfNeeded()
        guard let op = undoStack.popLast() else { return }
        switch op {
        case .add(let s):
            shapes.removeAll { $0.id == s.id }
        case .remove(let s, let i):
            shapes.insert(s, at: min(i, shapes.count))
        case .edit(let old, _):
            replace(with: old)
        }
        redoStack.append(op)
        sanitizeSelection()
    }

    func redo() {
        guard let op = redoStack.popLast() else { return }
        switch op {
        case .add(let s):
            shapes.append(s)
        case .remove(let s, _):
            shapes.removeAll { $0.id == s.id }
        case .edit(_, let new):
            replace(with: new)
        }
        undoStack.append(op)
        sanitizeSelection()
    }

    private func record(_ op: EditOp) {
        undoStack.append(op)
        redoStack.removeAll()
    }

    private func replace(with shape: DrawShape) {
        guard let idx = shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        shapes[idx] = shape
    }

    private func sanitizeSelection() {
        if let sel = selectedID, !shapes.contains(where: { $0.id == sel }) {
            selectedID = nil
        }
    }

    // MARK: 当たり判定・移動

    private func hitTest(_ p: CGPoint) -> Int? {
        for idx in shapes.indices.reversed() where hits(shapes[idx], p) {
            return idx
        }
        return nil
    }

    private func hits(_ s: DrawShape, _ p: CGPoint) -> Bool {
        let tol = max(8, s.lineWidth + 4)
        switch s.tool {
        case .select:
            return false
        case .rect, .ellipse, .mosaic:
            return s.rect.insetBy(dx: -tol, dy: -tol).contains(p)
        case .line, .arrow:
            return ShapeRenderer.distance(p, toSegment: s.start, s.end) <= tol
        case .pen:
            return polylineHit(s.points, p, tol: tol)
        case .highlight:
            return polylineHit(s.points, p, tol: max(tol, ShapeRenderer.highlightWidth(s.lineWidth) / 2 + 2))
        case .text:
            return ShapeRenderer.textBounds(s).insetBy(dx: -6, dy: -6).contains(p)
        }
    }

    private func polylineHit(_ points: [CGPoint], _ p: CGPoint, tol: CGFloat) -> Bool {
        guard points.count > 1 else { return false }
        for (a, b) in zip(points, points.dropFirst()) {
            if ShapeRenderer.distance(p, toSegment: a, b) <= tol { return true }
        }
        return false
    }

    private func translated(_ s: DrawShape, dx: CGFloat, dy: CGFloat) -> DrawShape {
        var t = s
        t.start.x += dx; t.start.y += dy
        t.end.x += dx; t.end.y += dy
        t.points = t.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return t
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, 0), pointSize.width),
            y: min(max(p.y, 0), pointSize.height)
        )
    }

    /// 注釈込みの最終画像をレンダリングする
    @MainActor
    func renderFinal() -> Capture {
        commitTextIfNeeded()
        let content = AnnotatedImageView(capture: capture, shapes: shapes, draft: nil)
            .frame(width: pointSize.width, height: pointSize.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = capture.scale
        if let cg = renderer.cgImage {
            return Capture(cgImage: cg, scale: capture.scale)
        }
        return capture
    }
}

// MARK: - ビュー

/// ベース画像+図形。画面プレビューと ImageRenderer 書き出しの両方で使う。
/// selectedID は画面プレビュー専用(書き出し時は nil)。
struct AnnotatedImageView: View {
    let capture: Capture
    let shapes: [DrawShape]
    let draft: DrawShape?
    var selectedID: UUID? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: capture.cgImage, scale: capture.scale)
                .resizable()
                .frame(width: capture.pointSize.width, height: capture.pointSize.height)
            Canvas { context, _ in
                for shape in shapes {
                    ShapeRenderer.draw(shape, in: &context)
                }
                if let draft {
                    ShapeRenderer.draw(draft, in: &context)
                }
                if let selectedID,
                   let sel = shapes.first(where: { $0.id == selectedID }) {
                    let r = ShapeRenderer.bounds(of: sel).insetBy(dx: -5, dy: -5)
                    context.stroke(
                        Path(roundedRect: r, cornerRadius: 4),
                        with: .color(.accentColor),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                }
            }
        }
        .frame(width: capture.pointSize.width, height: capture.pointSize.height)
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @FocusState private var textFieldFocused: Bool

    private let swatches: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .frame(minWidth: 560, minHeight: 380)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(ToolKind.allCases) { t in
                    Button {
                        model.selectTool(t)
                    } label: {
                        Image(systemName: t.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(model.tool == t ? Color.accentColor.opacity(0.25) : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.label)
                }
            }

            Divider().frame(height: 18)

            HStack(spacing: 5) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { _, c in
                    Circle()
                        .fill(c)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(
                                model.color == c ? Color.accentColor : Color.primary.opacity(0.2),
                                lineWidth: model.color == c ? 2 : 1
                            )
                        )
                        .onTapGesture { model.setColor(c) }
                }
            }

            Divider().frame(height: 18)

            HStack(spacing: 6) {
                Image(systemName: "lineweight").font(.system(size: 11))
                Slider(value: $model.lineWidth, in: 1...12)
                    .frame(width: 80)
            }

            Divider().frame(height: 18)

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model.undoStack.isEmpty)
                .help("取り消す (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model.redoStack.isEmpty)
                .help("やり直す (⇧⌘Z)")
            Button { model.deleteSelected() } label: { Image(systemName: "trash") }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedID == nil)
                .help("選択した図形を削除 (Delete)")

            Spacer()

            Button {
                Clipboard.copy(model.renderFinal())
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("注釈込みでクリップボードへコピー (⇧⌘C)")

            Button {
                saveWithPanel()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .help("PNG として保存 (⌘S)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let size = model.pointSize
            let fit = min(
                geo.size.width / max(size.width, 1),
                geo.size.height / max(size.height, 1),
                1
            )
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                AnnotatedImageView(
                    capture: model.capture,
                    shapes: model.shapes,
                    draft: model.draft,
                    selectedID: model.selectedID
                )
                .frame(width: size.width, height: size.height)
                .scaleEffect(fit)
                .frame(width: size.width * fit, height: size.height * fit)
                .overlay(textEditor(fit: fit))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            model.dragChanged(at: CGPoint(x: g.location.x / fit, y: g.location.y / fit))
                        }
                        .onEnded { g in
                            model.dragEnded(at: CGPoint(x: g.location.x / fit, y: g.location.y / fit))
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            model.beginEditText(
                                at: CGPoint(x: value.location.x / fit, y: value.location.y / fit)
                            )
                        }
                )
                .shadow(color: .black.opacity(0.25), radius: 8)
            }
        }
    }

    @ViewBuilder
    private func textEditor(fit: CGFloat) -> some View {
        if let origin = model.editingTextOrigin {
            TextField("テキストを入力", text: $model.textInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: max(13, 24 * fit * 0.8)))
                .frame(width: 220)
                .position(x: origin.x * fit + 110, y: origin.y * fit + 14)
                .focused($textFieldFocused)
                .onSubmit { model.commitTextIfNeeded() }
                // セッションごとにフィールドを作り直す。フォーカスは同期的に当てると
                // フィールドエディタの競合でハングすることがあるため必ず非同期で行う
                .id(model.textSessionID)
                .onAppear {
                    DispatchQueue.main.async { textFieldFocused = true }
                }
        }
    }

    private func saveWithPanel() {
        let final = model.renderFinal()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = SettingsStore.shared.saveDirectory
        panel.nameFieldStringValue = SettingsStore.fileName()
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? final.pngData()?.write(to: url)
        }
    }
}

// MARK: - ウィンドウ管理

enum EditorWindowController {
    private static var windows: [NSWindow] = []

    @MainActor
    static func open(_ capture: Capture) {
        let model = EditorModel(capture: capture)
        let hosting = NSHostingController(rootView: EditorView(model: model))

        let size = capture.pointSize
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxSize = CGSize(
            width: screen.visibleFrame.width * 0.85,
            height: screen.visibleFrame.height * 0.85
        )
        let fit = min(maxSize.width / max(size.width, 1), (maxSize.height - 60) / max(size.height, 1), 1)
        let contentSize = CGSize(
            width: max(size.width * fit + 40, 620),
            height: max(size.height * fit + 100, 420)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "編集 - Kiritori"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(contentSize)
        window.isReleasedWhenClosed = false
        window.center()

        windows.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { note in
            if let w = note.object as? NSWindow {
                windows.removeAll { $0 === w }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
