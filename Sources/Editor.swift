import AppKit
import CoreImage

private enum EditorTool: Int, CaseIterable {
    case rectangle, oval, line, arrow, pen, mosaic, text, image
    var title:String { ["Rectangle","Oval","Line","Arrow","Pen","Mosaic","Text","Image"][rawValue] }
    var icon:String { ["icon_rectangle","icon_ellipse","icon_line","icon_arrow","icon_pen","mosaic","icon_text","add_Image"][rawValue] }
    var symbol:String { ["rectangle","oval","line.diagonal","arrow.up.right","pencil.tip","square.grid.3x3.fill","textformat","photo"][rawValue] }
    var widthGroup:Int { [.rectangle,.oval,.line].contains(self) ? 0 : rawValue }
    var defaultWidth:CGFloat { self == .arrow ? 8 : self == .text ? 15 : 4 }
}
private struct EditorMark {
    var tool:EditorTool
    var points:[NSPoint]
    var color:NSColor
    var width:CGFloat
    var text:String = ""
    var image:NSImage? = nil
    var imageCornerRadius:CGFloat = 8
    var geometryScale:CGFloat = 1
    var textMeasurementBounds = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
    var rect:NSRect {
        guard let first = points.first else { return .zero }
        if tool == .text {
            let size = textSize
            return NSRect(x:first.x-size.width/2,y:first.y-size.height/2,width:size.width,height:size.height)
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return NSRect(x:xs.min() ?? first.x,y:ys.min() ?? first.y,width:(xs.max() ?? first.x)-(xs.min() ?? first.x),height:(ys.max() ?? first.y)-(ys.min() ?? first.y))
    }
    var textAttributes:[NSAttributedString.Key:Any] { [.font:NSFont.systemFont(ofSize:max(1,width*2)),.foregroundColor:color] }
    var textSize:NSSize {
        let measured = (text.isEmpty ? " " : text as String) as NSString
        let size = measured.boundingRect(with:textMeasurementBounds,options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:textAttributes).size
        return NSSize(width:max(20*geometryScale,ceil(size.width)+10*geometryScale),height:max(width+10*geometryScale,ceil(size.height)))
    }
    func path() -> CGPath {
        let path = CGMutablePath()
        guard let a = points.first else { return path }
        let b = points.last ?? a
        switch tool {
        case .rectangle:
            let radius:CGFloat = rect.height >= 6*geometryScale ? 4*geometryScale : 0
            path.addRoundedRect(in:rect,cornerWidth:radius,cornerHeight:radius)
        case .oval: path.addEllipse(in:rect)
        case .arrow:
            let dx = b.x-a.x, dy = b.y-a.y, length = hypot(dx,dy)
            guard length > 0 else { return path }
            let ux = dx/length, uy = dy/length, headLength = min(length,max(25*geometryScale,width*3.5)), shaft = width/2, headWidth = width*2.5/2
            func point(_ distance:CGFloat,_ side:CGFloat) -> CGPoint { CGPoint(x:a.x+ux*distance-uy*side,y:a.y+uy*distance+ux*side) }
            path.move(to:point(0,shaft)); path.addLine(to:point(length-headLength,shaft)); path.addLine(to:point(length-headLength,headWidth)); path.addLine(to:b)
            path.addLine(to:point(length-headLength,-headWidth)); path.addLine(to:point(length-headLength,-shaft)); path.addLine(to:point(0,-shaft)); path.closeSubpath()
        case .pen,.mosaic,.line:
            path.move(to:a); for p in points.dropFirst() { path.addLine(to:p) }
            if points.count == 1 { path.addLine(to:CGPoint(x:a.x+0.01,y:a.y)) }
        case .text,.image: path.addRect(rect)
        }
        return path
    }
    func hit(_ point:NSPoint,tolerance:CGFloat) -> Bool {
        if tool == .mosaic { return false }
        if tool == .text || tool == .image { return rect.contains(point) }
        if tool == .arrow { return path().contains(point) }
        return path().copy(strokingWithWidth:max(width,tolerance*2),lineCap:.round,lineJoin:.round,miterLimit:10).contains(point)
    }
    func draw(pixelated:NSImage?,sourceSize:NSSize) {
        if tool == .text {
            let cell = NSTextFieldCell(textCell:text)
            cell.isBordered = false; cell.drawsBackground = false; cell.wraps = true; cell.isScrollable = false; cell.usesSingleLineMode = false
            cell.font = NSFont.systemFont(ofSize:max(1,width*2)); cell.textColor = color
            let contentWidth = max(0,rect.width-10*geometryScale)
            let contentHeight = cell.cellSize(forBounds:NSRect(x:0,y:0,width:contentWidth,height:rect.height)).height
            cell.draw(withFrame:NSRect(x:rect.minX+5*geometryScale,y:rect.midY-contentHeight/2,width:contentWidth,height:contentHeight),in:NSView(frame:rect))
            return
        }
        if tool == .image, let image = image {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect:rect,xRadius:imageCornerRadius,yRadius:imageCornerRadius).addClip()
            let ratio = min(rect.width/max(1,image.size.width),rect.height/max(1,image.size.height))
            let size = NSSize(width:image.size.width*ratio,height:image.size.height*ratio)
            image.draw(in:NSRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height))
            NSGraphicsContext.restoreGraphicsState(); return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        if tool == .mosaic {
            if let pixelated = pixelated {
                // No translucent filter layer is exported. The mask replaces source pixels.
                context.setShouldAntialias(false)
                context.addPath(path().copy(strokingWithWidth:width,lineCap:.round,lineJoin:.round,miterLimit:10)); context.clip()
                pixelated.draw(in:NSRect(origin:.zero,size:sourceSize),from:.zero,operation:.copy,fraction:1)
            }
        } else {
            context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor); context.setLineWidth(width); context.setLineCap(.round); context.setLineJoin(.round); context.addPath(path())
            if tool == .arrow { context.fillPath() } else { context.strokePath() }
        }
        context.restoreGState()
    }
}
private enum EditorInteraction {
    case region(NSRect,Int?,NSPoint)
    case move(Int,EditorMark,NSPoint)
    case resize(Int,EditorMark,Int,NSPoint)
    case draw(EditorMark)
}

private final class EditorCanvas:NSView,NSTextFieldDelegate {
    let source:NSImage
    let overlay:Bool
    var outputRect:NSRect
    var marks:[EditorMark] = []
    var tool:EditorTool? = nil
    var color:NSColor = .red
    var width:CGFloat = 4
    var changed:(() -> Void)?
    private(set) var selected:Int?
    private var interaction:EditorInteraction?
    private var pixelated:NSImage?
    fileprivate var textView:NSTextField?
    private var editingIndex:Int?
    init(image:NSImage,overlay:Bool = false,outputRect:NSRect? = nil) {
        self.source = image; self.overlay = overlay; self.outputRect = outputRect ?? NSRect(origin:.zero,size:image.size)
        super.init(frame:.zero)
    }
    required init?(coder:NSCoder) { return nil }
    override var acceptsFirstResponder:Bool { true }
    var imageRect:NSRect {
        if overlay { return bounds }
        let scale = min(1,max(1,bounds.width-48)/max(1,source.size.width),max(1,bounds.height-80)/max(1,source.size.height))
        let size = NSSize(width:source.size.width*scale,height:source.size.height*scale)
        return NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2+20,width:size.width,height:size.height)
    }
    var unitsPerPoint:CGFloat { source.size.width/max(1,imageRect.width) }
    var selectionViewRect:NSRect { viewRect(outputRect) }
    func viewRect(_ rect:NSRect) -> NSRect { let r = imageRect; let s = r.width/max(1,source.size.width); return NSRect(x:r.minX+rect.minX*s,y:r.minY+rect.minY*s,width:rect.width*s,height:rect.height*s) }
    func imagePoint(_ point:NSPoint) -> NSPoint { let r = imageRect; return NSPoint(x:(point.x-r.minX)*unitsPerPoint,y:(point.y-r.minY)*unitsPerPoint) }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedWhite:0.94,alpha:1).setFill(); bounds.fill()
        let r = imageRect
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:r).addClip()
        let t = NSAffineTransform(); t.translateX(by:r.minX,yBy:r.minY); t.scale(by:1/unitsPerPoint); t.concat()
        source.draw(in:NSRect(origin:.zero,size:source.size))
        for (index,mark) in marks.enumerated() where index != editingIndex { mark.draw(pixelated:pixelated,sourceSize:source.size) }
        if case .draw(let mark) = interaction { mark.draw(pixelated:pixelated,sourceSize:source.size) }
        NSGraphicsContext.restoreGraphicsState()
        if overlay {
            let dim = NSBezierPath(rect:r); dim.append(NSBezierPath(rect:selectionViewRect)); dim.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.5).setFill(); dim.fill()
            SelectionChrome.draw(rect:selectionViewRect,handles:marks.isEmpty && tool == nil)
            let label = "\(Int(outputRect.width)) × \(Int(outputRect.height))"
            (label as NSString).draw(at:NSPoint(x:selectionViewRect.minX+5,y:selectionViewRect.maxY+4),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.white])
        }
        if let selected = selected, marks.indices.contains(selected), selected != editingIndex {
            let mark = marks[selected]
            NSColor.white.setStroke(); let border = NSBezierPath(rect:viewRect(mark.rect).insetBy(dx:-2,dy:-2)); border.lineWidth = 1; border.setLineDash([3,3],count:2,phase:0); border.stroke()
            drawHandles(markHandles(mark),color:NSColor(calibratedRed:0.905882,green:0.996078,blue:0.4,alpha:1))
        }
    }
    private func drawHandles(_ points:[NSPoint],color:NSColor) {
        for point in points { let p = viewRect(NSRect(x:point.x,y:point.y,width:0,height:0)).origin; color.setFill(); NSColor.darkGray.setStroke(); let path = NSBezierPath(ovalIn:NSRect(x:p.x-3,y:p.y-3,width:6,height:6)); path.fill(); path.lineWidth = 1; path.stroke() }
    }
    private func handlePoints(_ r:NSRect) -> [NSPoint] { [NSPoint(x:r.minX,y:r.minY),NSPoint(x:r.midX,y:r.minY),NSPoint(x:r.maxX,y:r.minY),NSPoint(x:r.maxX,y:r.midY),NSPoint(x:r.maxX,y:r.maxY),NSPoint(x:r.midX,y:r.maxY),NSPoint(x:r.minX,y:r.maxY),NSPoint(x:r.minX,y:r.midY)] }
    private func markHandles(_ mark:EditorMark) -> [NSPoint] {
        switch mark.tool { case .rectangle,.oval: return handlePoints(mark.rect)
        case .image: return [NSPoint(x:mark.rect.minX,y:mark.rect.minY),NSPoint(x:mark.rect.maxX,y:mark.rect.minY),NSPoint(x:mark.rect.maxX,y:mark.rect.maxY),NSPoint(x:mark.rect.minX,y:mark.rect.maxY)]
        case .arrow: return [mark.points.first ?? .zero,mark.points.last ?? .zero]
        default:return [] }
    }
    private func hitHandle(_ points:[NSPoint],_ point:NSPoint) -> Int? { points.indices.first { hypot(points[$0].x-point.x,points[$0].y-point.y) <= 7*unitsPerPoint } }
    override func mouseDown(with event:NSEvent) { begin(at:imagePoint(convert(event.locationInWindow,from:nil)),clickCount:event.clickCount) }
    override func mouseDragged(with event:NSEvent) { drag(to:imagePoint(convert(event.locationInWindow,from:nil))) }
    override func mouseUp(with event:NSEvent) { end(at:imagePoint(convert(event.locationInWindow,from:nil))) }
    func begin(at point:NSPoint,clickCount:Int = 1) {
        finishText(); window?.makeFirstResponder(self)
        if let index = selected, marks.indices.contains(index), let handle = hitHandle(markHandles(marks[index]),point) {
            interaction = .resize(index,marks[index],handle,point); return
        }
        if let index = marks.indices.reversed().first(where:{ marks[$0].hit(point,tolerance:5*unitsPerPoint) }) {
            selected = index; width = marks[index].width/unitsPerPoint; color = marks[index].color
            if marks[index].tool == .text && clickCount == 2 { startText(index); return }
            interaction = .move(index,marks[index],point); refresh(); return
        }
        selected = nil
        if overlay && marks.isEmpty && tool == nil {
            let handle = hitHandle(handlePoints(outputRect),point)
            if handle != nil || outputRect.contains(point) { interaction = .region(outputRect,handle,point) }
            refresh(); return
        }
        guard outputRect.contains(point), let tool = tool else { refresh(); return }
        let mark = EditorMark(tool:tool,points:tool == .text ? [point] : [point,point],color:color,width:width*unitsPerPoint,imageCornerRadius:8*unitsPerPoint,geometryScale:unitsPerPoint,textMeasurementBounds:source.size)
        if tool == .text { marks.append(mark); selected = marks.count-1; startText(marks.count-1) }
        else { if tool == .mosaic { prepareMosaic() }; interaction = .draw(mark) }
        refresh()
    }
    func drag(to point:NSPoint) {
        guard let interaction = interaction else { return }
        switch interaction {
        case .region(let rect,let handle,let start):
            if let handle = handle { outputRect = resized(rect,handle:handle,point:point).intersection(NSRect(origin:.zero,size:source.size)) }
            else { let dx = min(max(point.x-start.x,-rect.minX),source.size.width-rect.maxX),dy = min(max(point.y-start.y,-rect.minY),source.size.height-rect.maxY); outputRect = rect.offsetBy(dx:dx,dy:dy) }
        case .move(let index,let original,let start):
            let delta = NSPoint(x:point.x-start.x,y:point.y-start.y); var mark = original; mark.points = original.points.map { NSPoint(x:$0.x+delta.x,y:$0.y+delta.y) }; marks[index] = mark
        case .resize(let index,let original,let handle,_):
            var mark = original
            if mark.tool == .arrow { if mark.points.indices.contains(handle) { mark.points[handle] = point } }
            else {
                let mapped = mark.tool == .image ? [0,2,4,6][handle] : handle
                let rect = resized(original.rect,handle:mapped,point:point)
                mark.points = [rect.origin,NSPoint(x:rect.maxX,y:rect.maxY)]
            }
            marks[index] = mark
        case .draw(var mark):
            let p = NSPoint(x:min(max(point.x,outputRect.minX),outputRect.maxX),y:min(max(point.y,outputRect.minY),outputRect.maxY))
            if mark.tool == .pen || mark.tool == .mosaic { mark.points.append(p) } else { mark.points[mark.points.count-1] = p }
            self.interaction = .draw(mark)
        }
        refresh()
    }
    func end(at point:NSPoint) {
        guard let interaction = interaction else { return }
        if case .draw(let mark) = interaction {
            let length = hypot((mark.points.last?.x ?? 0)-(mark.points.first?.x ?? 0),(mark.points.last?.y ?? 0)-(mark.points.first?.y ?? 0))
            if (mark.tool == .pen || mark.tool == .mosaic) ? mark.points.count > 2 : length > (mark.tool == .arrow ? 5*unitsPerPoint : unitsPerPoint) { marks.append(mark) }
        }
        self.interaction = nil; refresh()
    }
    private func resized(_ rect:NSRect,handle:Int,point:NSPoint) -> NSRect {
        var left = rect.minX,right = rect.maxX,bottom = rect.minY,top = rect.maxY
        if [0,6,7].contains(handle) { left = min(point.x,right-1) }
        if [2,3,4].contains(handle) { right = max(point.x,left+1) }
        if [0,1,2].contains(handle) { bottom = min(point.y,top-1) }
        if [4,5,6].contains(handle) { top = max(point.y,bottom+1) }
        return NSRect(x:left,y:bottom,width:right-left,height:top-bottom)
    }
    func undoAction() { finishText(); guard !marks.isEmpty else { return }; marks.removeLast(); selected = nil; interaction = nil; refresh() }
    var canUndo:Bool { !marks.isEmpty }
    func deleteSelected() { guard editingIndex == nil,let index = selected,marks.indices.contains(index) else { return }; marks.remove(at:index); selected = nil; refresh() }
    override func keyDown(with event:NSEvent) { if event.keyCode == 51 || event.keyCode == 117 { deleteSelected() } else { super.keyDown(with:event) } }
    func setWidth(_ value:CGFloat) { width = value; if let index = selected,marks.indices.contains(index) { marks[index].width = value*unitsPerPoint; updateEditingFrame() }; refresh() }
    func setColor(_ value:NSColor) { color = value; if let index = selected,marks.indices.contains(index) { marks[index].color = value; textView?.textColor = value }; refresh() }
    func addImage(_ image:NSImage) {
        finishText()
        let scale = min(1,250*unitsPerPoint/max(1,image.size.width),outputRect.width*0.7/max(1,image.size.width))
        let size = NSSize(width:max(20*unitsPerPoint,image.size.width*scale),height:max(20*unitsPerPoint,image.size.height*scale))
        let origin = NSPoint(x:outputRect.midX-size.width/2,y:outputRect.midY-size.height/2)
        marks.append(EditorMark(tool:.image,points:[origin,NSPoint(x:origin.x+size.width,y:origin.y+size.height)],color:color,width:4*unitsPerPoint,image:image,imageCornerRadius:8*unitsPerPoint,geometryScale:unitsPerPoint)); selected = marks.count-1; refresh()
    }
    func addEmoji(_ text:String) {
        let size = NSSize(width:60*unitsPerPoint,height:60*unitsPerPoint)
        let image = NSImage(size:size); image.lockFocus(); (text as NSString).draw(in:NSRect(origin:.zero,size:size),withAttributes:[.font:NSFont.systemFont(ofSize:48*unitsPerPoint)]); image.unlockFocus(); addImage(image)
    }
    private func prepareMosaic() {
        guard pixelated == nil,let cg = source.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return }
        let input = CIImage(cgImage:cg),context = CIContext(options:[.cacheIntermediates:false])
        let output = input.applyingFilter("CIPixellate",parameters:[kCIInputScaleKey:10]).cropped(to:input.extent)
        if let image = context.createCGImage(output,from:input.extent) { pixelated = NSImage(cgImage:image,size:source.size) }
    }
    private func startText(_ index:Int) {
        editingIndex = index
        let view = NSTextField()
        view.isBordered = false; view.drawsBackground = false
        view.isEditable = true; view.isSelectable = true
        view.usesSingleLineMode = false; view.cell?.wraps = true; view.cell?.isScrollable = false
        view.font = NSFont.systemFont(ofSize:marks[index].width*2/unitsPerPoint)
        view.textColor = marks[index].color; view.stringValue = marks[index].text; view.delegate = self
        textView = view; addSubview(view); updateEditingFrame()
        window?.makeFirstResponder(view)
        if let editor = view.currentEditor() { editor.selectedRange = NSRange(location:view.stringValue.utf16.count,length:0) }
        refresh()
    }
    func controlTextDidChange(_ notification:Notification) {
        guard let index = editingIndex,let view = textView,marks.indices.contains(index) else { return }
        marks[index].text = view.stringValue; updateEditingFrame(); needsDisplay = true
    }
    private func updateEditingFrame() {
        guard let index = editingIndex,marks.indices.contains(index),let view = textView else { return }
        view.font = NSFont.systemFont(ofSize:marks[index].width*2/unitsPerPoint)
        let container = viewRect(marks[index].rect)
        let width = max(0,container.width-10)
        let height = view.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:container.height)).height ?? container.height
        view.frame = NSRect(x:container.minX+5,y:container.midY-height/2,width:width,height:height)
    }
    func finishText() {
        if let index = editingIndex,marks.indices.contains(index),let view = textView {
            marks[index].text = view.stringValue
            if view.stringValue.isEmpty { marks.remove(at:index); selected = nil }
        }
        textView?.removeFromSuperview(); textView = nil; editingIndex = nil; needsDisplay = true
    }
    private func refresh() { needsDisplay = true; changed?() }
    func renderedImage(full:Bool = false) -> CGImage? {
        finishText()
        let w = Int(source.size.width.rounded()),h = Int(source.size.height.rounded())
        guard w > 0,h > 0,let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context = NSGraphicsContext(bitmapImageRep:rep) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        source.draw(in:NSRect(x:0,y:0,width:w,height:h))
        if marks.contains(where:{$0.tool == .mosaic}) { prepareMosaic() }
        for mark in marks { mark.draw(pixelated:pixelated,sourceSize:source.size) }
        context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        guard let image = rep.cgImage else { return nil }
        if full { return image }
        let rect = outputRect.integral.intersection(NSRect(origin:.zero,size:source.size))
        guard rect.width > 0,rect.height > 0 else { return nil }
        return image.cropping(to:NSRect(x:rect.minX,y:source.size.height-rect.maxY,width:rect.width,height:rect.height))
    }
}

private final class ScreenshotEditorWindow:NSWindow {
    var shortcutHandler:((NSEvent)->Bool)?
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { true }
    override func performKeyEquivalent(with event:NSEvent) -> Bool { if shortcutHandler?(event) == true { return true }; return super.performKeyEquivalent(with:event) }
}
private final class EditorToolbar:NSView {
    var manuallyPositioned = false
    var didMove: (() -> Void)?
    private var last:NSPoint?
    override func mouseDown(with event:NSEvent) { last = event.locationInWindow }
    override func mouseDragged(with event:NSEvent) {
        guard let last = last,let superview = superview else { return }; let next = event.locationInWindow
        frame.origin = NSPoint(x:min(max(0,frame.minX+next.x-last.x),max(0,superview.bounds.width-frame.width)),y:min(max(0,frame.minY+next.y-last.y),max(0,superview.bounds.height-frame.height)))
        manuallyPositioned = true; self.last = next; didMove?()
    }
    override func mouseUp(with event:NSEvent) { last = nil }
}

private final class EditorSwatch:NSButton {
    override var allowsVibrancy: Bool { false }
    var swatch = NSColor.red
    var selected = false
    var changed:((EditorSwatch)->Void)?
    override func draw(_ dirtyRect:NSRect) { swatch.setFill(); NSBezierPath(ovalIn:NSRect(x:4,y:4,width:14,height:14)).fill(); if selected { NSColor(calibratedWhite:112/255,alpha:1).setStroke(); let path = NSBezierPath(ovalIn:bounds.insetBy(dx:0.5,dy:0.5)); path.lineWidth = 1; path.stroke() } }
    override func mouseUp(with event:NSEvent) { if bounds.contains(convert(event.locationInWindow,from:nil)) { changed?(self) } }
}
private final class EditorWidthSlider:NSView {
    override var allowsVibrancy: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { "Stroke width" }
    override func accessibilityValue() -> Any? { NSNumber(value: Double(value)) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: 2) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: 25) }
    override func setAccessibilityValue(_ next: Any?) { if let number = next as? NSNumber { apply(CGFloat(number.doubleValue)) } }
    override func accessibilityPerformIncrement() -> Bool { apply(value + 1); return true }
    override func accessibilityPerformDecrement() -> Bool { apply(value - 1); return true }
    private func apply(_ next: CGFloat) { value = min(25, max(2, next)); onChange?(value); needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if [123,125].contains(event.keyCode) { apply(value - 1) }
        else if [124,126].contains(event.keyCode) { apply(value + 1) }
        else { super.keyDown(with: event) }
    }
    var value:CGFloat = 4
    var color = NSColor.red
    var onChange:((CGFloat)->Void)?
    override func draw(_ dirtyRect:NSRect) { let x = (min(25,max(2,value))-2)/23*70; NSColor.white.withAlphaComponent(0.35).setFill(); NSRect(x:x+3,y:7,width:73-x,height:2).fill(); color.setFill(); NSRect(x:0,y:7,width:x+3,height:2).fill(); publicAsset("knob")?.draw(in:NSRect(x:x,y:0,width:6,height:16)) }
    override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(self); update(event) }
    override func mouseDragged(with event:NSEvent) { update(event) }
    private func update(_ event:NSEvent) { let p = convert(event.locationInWindow,from:nil); value = 2+min(70,max(0,p.x-3))/70*23; onChange?(value); needsDisplay = true }
}

final class EditorController:NSWindowController,NSWindowDelegate {
    static var retained:[EditorController] = []
    private let canvas:EditorCanvas
    private let overlay:Bool
    private let screenFrame:NSRect?
    private let toolbar = EditorToolbar()
    private var toolButtons:[NSButton] = []
    private var undoButton = NSButton()
    private var widthMemory:[Int:CGFloat] = [:]
    private var palette:NSView?
    private var popover:NSPopover?
    private var ocrObserver:NSObjectProtocol?
    private var presetImages:[NSImage] = []
    private var saveButton = NSButton()
    private let swatches:[NSColor] = [(255,0,0),(255,87,87),(255,128,2),(121,224,56),(83,130,255),(110,75,255),(255,51,216),(131,131,131),(255,255,255),(0,0,0)].map { NSColor(srgbRed:CGFloat($0.0)/255,green:CGFloat($0.1)/255,blue:CGFloat($0.2)/255,alpha:1) }
    static func open(image:NSImage) { retainAndShow(EditorController(image:image)) }
    static func openCapture(image:NSImage,selection:NSRect,screenFrame:NSRect) { retainAndShow(EditorController(image:image,selection:selection,screenFrame:screenFrame)) }
    private static func retainAndShow(_ controller:EditorController) { retained.append(controller); controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    convenience init(image:NSImage) { self.init(image:image,selection:nil,screenFrame:nil) }
    private init(image:NSImage,selection:NSRect?,screenFrame:NSRect?) {
        let normalized:NSImage
        if let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) { normalized = NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height)) } else { normalized = image }
        overlay = screenFrame != nil; self.screenFrame = screenFrame
        var pixelRect:NSRect? = nil
        if let selection = selection,let frame = screenFrame { let sx = normalized.size.width/max(1,frame.width),sy = normalized.size.height/max(1,frame.height); pixelRect = NSRect(x:selection.minX*sx,y:selection.minY*sy,width:selection.width*sx,height:selection.height*sy) }
        canvas = EditorCanvas(image:normalized,overlay:screenFrame != nil,outputRect:pixelRect)
        let frame = screenFrame ?? NSRect(x:0,y:0,width:1000,height:760)
        let window = ScreenshotEditorWindow(contentRect:frame,styleMask:screenFrame == nil ? [.titled,.closable,.resizable,.miniaturizable] : [.borderless],backing:.buffered,defer:false)
        window.title = "Screen Shoter Open - Editor"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width:800,height:420)
        if screenFrame != nil { window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.isOpaque = true } else { window.center() }
        super.init(window:window); window.delegate = self
        buildUI(); canvas.changed = { [weak self] in self?.updateUI() }
        window.shortcutHandler = { [weak self] event in
            guard let self = self else { return false }
            if event.keyCode == 53 { self.window?.close(); return true }
            guard event.modifierFlags.contains(.command) else { return false }
            if event.keyCode == 36 { self.quickSave(); return true }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": if self.window?.firstResponder is NSTextView { return false }; self.copyImage(); return true
            case "s": self.saveSelected(); return true
            case "z": if self.window?.firstResponder is NSTextView { return false }; self.canvas.undoAction(); return true
            default:return false
            }
        }
        ocrObserver = NotificationCenter.default.addObserver(forName:Notification.Name("RunOCR"),object:nil,queue:.main) { [weak self] _ in guard let self = self,Self.retained.last === self else { return }; self.ocr() }
        updateUI()
    }
    required init?(coder:NSCoder) { return nil }
    deinit { if let observer = ocrObserver { NotificationCenter.default.removeObserver(observer) } }
    func windowWillClose(_ notification:Notification) { canvas.finishText(); Self.retained.removeAll { $0 === self } }
    private func iconButton(_ title:String,_ icon:String,_ symbol:String,_ action:Selector, width:CGFloat = 39) -> NSButton {
        let button = NSButton(title:"",target:self,action:action); button.isBordered = false; button.imagePosition = .imageOnly; button.imageScaling = .scaleNone
        button.image = publicAsset(icon) ?? NSImage(systemSymbolName:symbol,accessibilityDescription:title); button.contentTintColor = .white; button.toolTip = title; button.setAccessibilityLabel(title); button.bezelStyle = .regularSquare
        button.frame = NSRect(x:0,y:0,width:width,height:48); return button
    }
    private func buildUI() {
        guard let root = window?.contentView else { return }; canvas.frame = root.bounds; canvas.autoresizingMask = [.width,.height]; root.addSubview(canvas)
        toolbar.wantsLayer = true; toolbar.layer?.backgroundColor = NSColor(srgbRed:54/255,green:54/255,blue:54/255,alpha:1).cgColor; toolbar.layer?.cornerRadius = 8
        var x:CGFloat = 10
        func add(_ view:NSView,width:CGFloat) { view.frame = NSRect(x:x,y:0,width:width,height:48); toolbar.addSubview(view); x += width }
        let closeSlot = NSView(); let close = iconButton("Close (Esc)","icon_close_normal","xmark",#selector(cancel)); close.frame = NSRect(x:7,y:12,width:24,height:24); closeSlot.addSubview(close); add(closeSlot,width:39)
        for tool in EditorTool.allCases where tool != .image { let button = iconButton(tool.title,tool.icon,tool.symbol,#selector(chooseTool(_:))); button.tag = tool.rawValue; button.setButtonType(.toggle); toolButtons.append(button); add(button,width:39) }
        add(iconButton("Add Image","add_Image","photo",#selector(importPopup(_:))),width:39)
        let divider = NSView(frame:NSRect(x:13,y:16,width:3,height:17)); divider.wantsLayer = true; divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.6).cgColor; divider.layer?.cornerRadius = 2
        let slot = NSView(); slot.addSubview(divider); add(slot,width:30)
        undoButton = iconButton("Undo","icon_redo","arrow.uturn.backward",#selector(undo)); add(undoButton,width:39)
        add(iconButton("To text (OCR)","icon_tools_ocr","text.viewfinder",#selector(ocr)),width:42)
        let translate = iconButton("Translation unavailable in local edition","icon_text 1","character.bubble",#selector(cancel)); translate.isEnabled = false; add(translate,width:42)
        add(iconButton("Record video","icon_tools_record","record.circle",#selector(recordVideo)),width:42)
        add(iconButton("Pin","Icon_tool_pin","pin",#selector(pin)),width:39)
        add(iconButton("Share","icon_share","square.and.arrow.up",#selector(share(_:))),width:39)
        saveButton = iconButton("Save (⌘S)","save_image","square.and.arrow.down",#selector(saveSelected)); saveButton.contentTintColor = Self.confirmColor; let saveSlot = NSView(); saveButton.frame = NSRect(x:-4,y:0,width:60,height:48); saveSlot.addSubview(saveButton); add(saveSlot,width:42)
        let dropdown = iconButton("Save mode","save_arrow","chevron.down",#selector(saveModes(_:))); dropdown.contentTintColor = Self.confirmColor; let dropdownSlot = NSView(); dropdown.frame = NSRect(x:0,y:7,width:9,height:35); dropdownSlot.addSubview(dropdown); add(dropdownSlot,width:9)
        let okSlot = NSView()
        let okLabel = NSTextField(labelWithString:"OK"); okLabel.font = .boldSystemFont(ofSize:19); okLabel.textColor = Self.confirmColor; okLabel.frame = NSRect(x:25,y:13,width:32,height:23); okSlot.addSubview(okLabel)
        let ok = NSButton(title:"",target:self,action:#selector(copyImage)); ok.isBordered = false; ok.frame = NSRect(x:27,y:13,width:28,height:23); ok.toolTip = "Copy (⌘C)"; ok.setAccessibilityLabel("OK: Copy screenshot"); okSlot.addSubview(ok); add(okSlot,width:83)
        toolbar.didMove = { [weak self] in self?.positionPalette() }
        toolbar.frame = NSRect(x:0,y:0,width:768,height:48); root.addSubview(toolbar); refreshSaveMode(); positionToolbar()
    }
    private static let confirmColor = NSColor(srgbRed:231/255,green:254/255,blue:102/255,alpha:1)
    private func refreshSaveMode() { let quick = UserDefaults.standard.bool(forKey:"quickSaveMode"); saveButton.image = publicAsset(quick ? "save_quick_image" : "save_image"); saveButton.toolTip = quick ? "Quick Save (⌘S)" : "Save (⌘S)" }
    @objc private func saveSelected() { if UserDefaults.standard.bool(forKey:"quickSaveMode") { quickSave() } else { saveAs() } }
    @objc private func saveModes(_ sender:NSButton) { let menu = NSMenu(); for (index,title) in ["Save","Quick Save"].enumerated() { let item = NSMenuItem(title:title,action:#selector(selectSaveMode(_:)),keyEquivalent:""); item.target = self; item.tag = index; item.state = UserDefaults.standard.bool(forKey:"quickSaveMode") == (index == 1) ? .on : .off; menu.addItem(item) }; menu.popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.minY),in:sender) }
    @objc private func selectSaveMode(_ sender:NSMenuItem) { UserDefaults.standard.set(sender.tag == 1,forKey:"quickSaveMode"); refreshSaveMode() }
    private func positionToolbar() {
        guard let root = window?.contentView else { return }
        if !toolbar.manuallyPositioned { toolbar.frame.origin = Self.toolbarOrigin(selection:canvas.selectionViewRect,bounds:root.bounds,overlay:overlay) }
        positionPalette()
    }
    private func positionPalette() {
        guard let palette, let root = window?.contentView else { return }
        let below = toolbar.frame.minY - 56
        let y = below >= 0 ? below : toolbar.frame.maxY + 8
        palette.frame.origin = NSPoint(x: min(max(0,toolbar.frame.minX),max(0,root.bounds.width-palette.frame.width)), y: min(max(0,y),max(0,root.bounds.height-palette.frame.height)))
    }
    private static func toolbarOrigin(selection:NSRect,bounds:NSRect,overlay:Bool) -> NSPoint {
        let x = min(max(0,selection.minX),max(0,bounds.width-768))
        var y = overlay ? selection.minY-56 : CGFloat(10)
        if y < 0 { y = min(bounds.height-48,selection.maxY+8) }
        return NSPoint(x:x,y:max(0,y))
    }
    private func updateUI() { undoButton.isEnabled = canvas.canUndo; for button in toolButtons { button.state = canvas.tool?.rawValue == button.tag ? .on : .off; button.wantsLayer = true; button.layer?.backgroundColor = button.state == .on ? NSColor.white.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor; button.layer?.cornerRadius = 5 }; positionToolbar() }
    @objc private func chooseTool(_ sender:NSButton) { canvas.finishText(); guard let tool = EditorTool(rawValue:sender.tag) else { return }; canvas.tool = sender.state == .on ? tool : nil; canvas.width = widthMemory[tool.widthGroup] ?? tool.defaultWidth; updateUI(); if canvas.tool != nil { options(sender) } else { palette?.removeFromSuperview(); palette = nil } }
    @objc private func cancel() { window?.close() }
    @objc private func undo() { canvas.undoAction() }
    @objc private func options(_ sender:NSButton) {
        popover?.close()
        palette?.removeFromSuperview()
        let root = makePalette()
        palette = root
        window?.contentView?.addSubview(root)
        positionPalette()
    }
    private func makePalette() -> NSView {
        let root = NSView(frame:NSRect(x:0,y:0,width:460,height:48)); root.wantsLayer = true; root.layer?.backgroundColor = NSColor(deviceRed:65/255,green:65/255,blue:65/255,alpha:1).cgColor; root.layer?.cornerRadius = 10
        let slider = EditorWidthSlider(frame:NSRect(x:32,y:16,width:76,height:16)); slider.value = canvas.width; slider.color = canvas.color
        slider.onChange = { [weak self] value in guard let self = self else { return }; if let tool = self.canvas.tool { self.widthMemory[tool.widthGroup] = value }; self.canvas.setWidth(value) }
        root.addSubview(slider)
        func sample(x:CGFloat,size:CGFloat) -> NSView { let v = NSView(frame:NSRect(x:x,y:24-size/2,width:size,height:size)); v.wantsLayer = true; v.layer?.cornerRadius = size/2; v.layer?.backgroundColor = canvas.color.cgColor; root.addSubview(v); return v }
        let small = sample(x:16,size:6), large = sample(x:118,size:14)
        let separator = NSView(frame:NSRect(x:148,y:0,width:1,height:48)); separator.wantsLayer = true; separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor; root.addSubview(separator)
        var buttons:[EditorSwatch] = []
        let offsets:[CGFloat] = [0,28,57,85,114,142,171,199,228,256]
        for (index,color) in swatches.enumerated() { let button = EditorSwatch(frame:NSRect(x:165+offsets[index],y:13,width:22,height:22)); button.swatch = color; button.selected = color == canvas.color; button.tag = index; button.target = self; button.action = #selector(changeColor(_:)); button.isBordered = false; button.toolTip = ["Red","Light red","Orange","Green","Blue","Violet","Pink","Gray","White","Black"][index]; button.setAccessibilityLabel(button.toolTip); buttons.append(button); root.addSubview(button) }
        for button in buttons { button.changed = { [weak self,weak root,weak slider,weak small,weak large] chosen in guard let self = self else { return }; self.canvas.setColor(chosen.swatch); for other in root?.subviews.compactMap({ $0 as? EditorSwatch }) ?? [] { other.selected = other === chosen; other.needsDisplay = true }; slider?.color = chosen.swatch; slider?.needsDisplay = true; small?.layer?.backgroundColor = chosen.swatch.cgColor; large?.layer?.backgroundColor = chosen.swatch.cgColor } }
        return root
    }
    @objc private func changeWidth(_ sender:NSSlider) { let value = CGFloat(sender.doubleValue); if let tool = canvas.tool { widthMemory[tool.widthGroup] = value }; canvas.setWidth(value) }
    @objc private func changeColor(_ sender:NSButton) { canvas.setColor(swatches[sender.tag]) }
    @objc private func importPopup(_ sender:NSButton) {
        palette?.removeFromSuperview(); palette = nil
        canvas.finishText(); presetImages = []
        presetImages = (1...5).compactMap { publicAsset("q_\($0)") }
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("emoteAsset"),let urls = try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) { presetImages += urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { NSImage(contentsOf:$0) } }
        let emojis = Self.originalEmojiPresets
        let grid = NSStackView(); grid.orientation = .vertical; grid.spacing = 5; grid.edgeInsets = NSEdgeInsets(top:8,left:8,bottom:8,right:8)
        var items:[NSButton] = []
        for (index,image) in presetImages.enumerated() { let button = NSButton(image:image,target:self,action:#selector(importPreset(_:))); button.tag = index; button.isBordered = false; button.imageScaling = .scaleProportionallyDown; button.toolTip = "Insert sticker \(index+1)"; items.append(button) }
        for emoji in emojis { let button = NSButton(title:emoji,target:self,action:#selector(importEmoji(_:))); button.font = .systemFont(ofSize:24); button.isBordered = false; items.append(button) }
        for start in stride(from:0,to:items.count,by:8) { let row = NSStackView(); row.spacing = 5; for button in items[start..<min(start+8,items.count)] { button.widthAnchor.constraint(equalToConstant:50).isActive = true; button.heightAnchor.constraint(equalToConstant:50).isActive = true; row.addArrangedSubview(button) }; grid.addArrangedSubview(row) }
        let scroll = NSScrollView(frame:NSRect(x:0,y:38,width:452,height:228)); scroll.hasVerticalScroller = true; scroll.documentView = grid; grid.frame = NSRect(x:0,y:0,width:452,height:CGFloat((items.count+7)/8)*55+16)
        let root = NSView(frame:NSRect(x:0,y:0,width:452,height:266)); root.addSubview(scroll)
        let file = NSButton(title:"Local images…",target:self,action:#selector(importFiles)); file.frame = NSRect(x:10,y:6,width:155,height:28); file.bezelStyle = .rounded
        let paste = NSButton(title:"Clipboard",target:self,action:#selector(importClipboard)); paste.frame = NSRect(x:174,y:6,width:174,height:28); paste.bezelStyle = .rounded
        if let image = clipboardImage() { paste.image = image; paste.imagePosition = .imageLeft; paste.imageScaling = .scaleProportionallyDown } else { paste.isEnabled = false }
        root.addSubview(file); root.addSubview(paste); let controller = NSViewController(); controller.view = root
        let popup = NSPopover(); popup.contentViewController = controller; popup.contentSize = root.frame.size; popup.behavior = .transient; popover = popup; popup.show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxY)
    }
    @objc private func importPreset(_ sender:NSButton) { if presetImages.indices.contains(sender.tag) { canvas.addImage(presetImages[sender.tag]) }; popover?.close() }
    @objc private func importEmoji(_ sender:NSButton) { canvas.addEmoji(sender.title); popover?.close() }
    private static let originalEmojiPresets = ["❤️","⛽️","👏","👍","💪","🌟","⬆️","🔥","🎉","😊","😄","😂","😑","😢","😮‍💨","🤫"]
    @objc private func importFiles() {
        popover?.close(); guard let parent = window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.beginSheetModal(for:parent) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { if let image = NSImage(contentsOf:url) { self?.canvas.addImage(image) } }
        }
    }
    private func clipboardImage() -> NSImage? { if let objects = NSPasteboard.general.readObjects(forClasses:[NSImage.self],options:nil) as? [NSImage],let image = objects.first { return image }; if let objects = NSPasteboard.general.readObjects(forClasses:[NSURL.self],options:nil) as? [URL],let url = objects.first { return NSImage(contentsOf:url) }; return nil }
    @objc private func importClipboard() { if let image = clipboardImage() { canvas.addImage(image) }; popover?.close() }
    private func resultImage() -> NSImage? { guard let image = canvas.renderedImage() else { return nil }; return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)) }
    private func finish(_ image:NSImage,notify:Bool = true) {
        guard overlay else { return }
        // Convert view coordinates before closing the editor. Pixels are not points
        // on Retina displays, and secondary displays can have negative origins.
        var info: [String: Any] = [:]
        if let screenFrame { info["screenFrame"] = screenFrame }
        if let window {
            info["sourceFrame"] = window.convertToScreen(canvas.convert(canvas.selectionViewRect, to: nil))
        }
        window?.close()
        if notify { NotificationCenter.default.post(name:Notification.Name("ScreenshotCompleted"),object:image,userInfo:info) }
    }
    @objc private func copyImage() { guard let image = resultImage() else { return }; HistoryPreviewController.copy(image); finish(image) }
    @objc private func saveAs() { guard let image = resultImage() else { return }; SaveController.present(image:image,parentWindow:window,completion:{ [weak self] _ in DispatchQueue.main.async { self?.finish(image,notify:false) } }) }
    @objc private func saveFormat(_ sender:NSMenuItem) { if let format = sender.representedObject as? String { UserDefaults.standard.set(format,forKey:"format") }; saveAs() }
    @objc private func quickSave() { guard let image = resultImage() else { return }; do { _ = try SaveController.quickSave(image:image); finish(image,notify:false) } catch { let alert = NSAlert(); alert.messageText = error.localizedDescription; alert.runModal() } }
    @objc private func ocr() { guard let image = resultImage() else { return }; finish(image,notify:false); OCRController.present(image:image) }
    @objc private func pin() { guard let image = resultImage() else { return }; var frame:NSRect? = nil; if let screen = screenFrame { let r = canvas.selectionViewRect; frame = r.offsetBy(dx:screen.minX,dy:screen.minY) }; finish(image,notify:false); PinController.open(image:image,frame:frame) }
    @objc private func share(_ sender:NSButton) { guard let image = resultImage() else { return }; NSSharingServicePicker(items:[image]).show(relativeTo:sender.bounds,of:sender,preferredEdge:.maxY) }
    @objc private func recordVideo() { window?.close(); NotificationCenter.default.post(name:Notification.Name("StartRecording"),object:nil) }

    /// Reproducible product media: synthetic content rendered by the real editor.
    /// This never captures the desktop or makes an editor window visible.
    static func renderPublicDemo() throws {
        let size = NSSize(width:1000,height:640)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1000,pixelsHigh:640,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0) else { throw NSError(domain:"PublicDemo",code:1) }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        func color(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat) -> NSColor { NSColor(srgbRed:r/255,green:g/255,blue:b/255,alpha:1) }
        func box(_ rect:NSRect,_ fill:NSColor,_ radius:CGFloat = 0) { fill.setFill(); NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill() }
        func text(_ value:String,_ x:CGFloat,_ y:CGFloat,_ font:CGFloat,_ fill:NSColor,_ weight:NSFont.Weight = .regular) {
            (value as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:font,weight:weight),.foregroundColor:fill])
        }
        let ink = color(33,40,56), muted = color(107,116,135), purple = color(117,85,231)
        box(NSRect(origin:.zero,size:size),color(246,247,251))
        box(NSRect(x:0,y:556,width:1000,height:84),ink)
        text("PROJECT NOTES",40,587,15,.white,.semibold)
        text("Workspace / Launch planning",718,589,13,color(180,188,208))
        text("Small tools. Clear thinking.",40,490,31,ink,.bold)
        text("A simple plan for the next release",40,454,17,muted)
        box(NSRect(x:40,y:352,width:920,height:65),.white,12)
        box(NSRect(x:58,y:370,width:7,height:28),purple,3)
        text("THIS WEEK",83,387,11,purple,.bold)
        text("Capture ideas, annotate details, share the result.",83,365,17,ink,.medium)
        let cards:[(CGFloat,String,String,String)] = [(40,"01","Capture","Keep the context."),(352,"02","Annotate","Make the detail obvious."),(664,"03","Share","Send a clear picture.")]
        for (x,number,title,caption) in cards {
            box(NSRect(x:x,y:139,width:296,height:181),.white,12)
            box(NSRect(x:x+20,y:263,width:36,height:36),color(240,235,255),9)
            text(number,x+28,272,13,purple,.semibold)
            text(title,x+20,214,23,ink,.semibold)
            text(caption,x+20,178,15,muted)
        }
        text("LOCAL FIRST",40,79,11,purple,.bold)
        text("No account. No cloud. Your screenshots stay on your Mac.",40,53,15,muted)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = bitmap.cgImage else { throw NSError(domain:"PublicDemo",code:2) }
        let editor = EditorController(image:NSImage(cgImage:cg,size:size))
        guard let root = editor.window?.contentView else { throw NSError(domain:"PublicDemo",code:3) }
        editor.window?.setContentSize(NSSize(width:1048,height:760))
        root.layoutSubtreeIfNeeded()
        var index = 0
        func frame() throws {
            root.needsDisplay = true; editor.canvas.needsDisplay = true
            try writeParityRender(root,name:String(format:"demo-frame-%04d",index))
            index += 1
        }
        func hold(_ count:Int) throws { for _ in 0..<count { try frame() } }
        func draw(_ tool:EditorTool,_ start:NSPoint,_ end:NSPoint,_ count:Int,_ stroke:NSColor,_ width:CGFloat) throws {
            editor.canvas.tool = tool; editor.canvas.color = stroke; editor.canvas.width = width; editor.updateUI()
            editor.canvas.begin(at:start)
            for step in 1...count {
                let t = CGFloat(step)/CGFloat(count)
                editor.canvas.drag(to:NSPoint(x:start.x+(end.x-start.x)*t,y:start.y+(end.y-start.y)*t))
                try frame()
            }
            editor.canvas.end(at:end)
        }
        try hold(10)
        try draw(.rectangle,NSPoint(x:34,y:133),NSPoint(x:342,y:326),15,color(117,85,231),4)
        try hold(8)
        try draw(.arrow,NSPoint(x:600,y:112),NSPoint(x:352,y:219),12,color(255,128,2),6)
        try hold(8)
        editor.canvas.tool = .pen; editor.canvas.color = color(117,85,231); editor.canvas.width = 4; editor.updateUI()
        let start = NSPoint(x:40,y:480)
        editor.canvas.begin(at:start)
        for step in 1...15 {
            let t = CGFloat(step)/15
            editor.canvas.drag(to:NSPoint(x:40+405*t,y:480+sin(t*CGFloat.pi*2)*2))
            try frame()
        }
        editor.canvas.end(at:NSPoint(x:445,y:480))
        editor.canvas.tool = nil; editor.updateUI()
        try hold(12)
        try writeParityRender(root,name:"editor")
        editor.window?.close()
        print("Rendered synthetic production editor demo: \(index) frames at 10 fps")
    }

    static func verifyRendering() throws {
        func require(_ pass:Bool,_ message:String) throws { if !pass { throw NSError(domain:"EditorVerification",code:1,userInfo:[NSLocalizedDescriptionKey:message]) } }
        let handles = SelectionChrome.handleRects(NSRect(x:20,y:30,width:200,height:100))
        try require(handles.count == 8 && handles[0].size == NSSize(width:10,height:10) && handles[1].size == NSSize(width:18,height:9) && handles[3].size == NSSize(width:9,height:18),"Selection handle geometry changed")
        try require(handles[1].midX == 120 && handles[3].midY == 80,"Selection handles lost edge centers")
        let full = toolbarOrigin(selection:NSRect(x:0,y:90,width:1470,height:820),bounds:NSRect(x:0,y:0,width:1470,height:956),overlay:true)
        try require(full == NSPoint(x:0,y:34),"Full selection toolbar anchor changed")
        let right = toolbarOrigin(selection:NSRect(x:1300,y:0,width:100,height:100),bounds:NSRect(x:0,y:0,width:1470,height:956),overlay:true)
        try require(right.x == 702 && right.y == 108,"Toolbar screen clamping changed")
        guard let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:100,pixelsHigh:80,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0) else { throw NSError(domain:"EditorVerification",code:2) }
        for y in 0..<80 { for x in 0..<100 { rep.setColor(y < 40 ? NSColor(deviceRed:0,green:0,blue:1,alpha:1) : NSColor(deviceRed:1,green:1,blue:1,alpha:1),atX:x,y:y) } }
        guard let cg = rep.cgImage else { throw NSError(domain:"EditorVerification",code:3) }
        let layout = EditorController(image:NSImage(cgImage:cg,size:NSSize(width:100,height:80)))
        try require(layout.toolbar.frame.size == NSSize(width:768,height:48) && layout.toolbar.subviews.count == 19,"Original toolbar layout changed")
        try require(layout.toolbar.subviews[9].frame == NSRect(x:361,y:0,width:30,height:48) && layout.toolbar.subviews.last?.frame == NSRect(x:685,y:0,width:83,height:48),"Toolbar separator or OK slot moved")
        try require(layout.toolbar.subviews[0].subviews.first?.frame == NSRect(x:7,y:12,width:24,height:24),"Original close hit area changed")
        try require(layout.toolbar.subviews[16].subviews.first?.frame == NSRect(x:-4,y:0,width:60,height:48),"Original save hit area changed")
        try require(layout.toolbar.subviews[17].subviews.first?.frame == NSRect(x:0,y:7,width:9,height:35),"Original save dropdown hit area changed")
        try require(layout.toolbar.subviews[18].subviews.first is NSTextField && layout.toolbar.subviews[18].subviews.last?.frame == NSRect(x:27,y:13,width:28,height:23),"Original OK label or hit area changed")
        try writeParityRender(layout.toolbar, name: "editor-toolbar")
        layout.options(layout.toolButtons[0])
        try require(layout.palette?.superview === layout.window?.contentView && layout.popover == nil,"Palette must be a plain editor view without native popover material")
        if let palette = layout.palette {
            try require(palette.frame.size == NSSize(width:460,height:48) && palette.layer?.cornerRadius == 10,"Palette geometry changed")
            try writeParityRender(palette,name:"editor-palette")
        }
        layout.window?.close()
        // Exercise the real completion handoff without touching the clipboard or disk.
        let flight = EditorController(image:NSImage(cgImage:cg,size:NSSize(width:100,height:80)),selection:NSRect(x:10,y:20,width:50,height:30),screenFrame:NSRect(x:-1000,y:200,width:100,height:80))
        var emittedSource: NSRect?
        var emittedScreen: NSRect?
        let observer = NotificationCenter.default.addObserver(forName:Notification.Name("ScreenshotCompleted"),object:nil,queue:nil) { note in
            emittedSource = note.userInfo?["sourceFrame"] as? NSRect
            emittedScreen = note.userInfo?["screenFrame"] as? NSRect
        }
        flight.finish(NSImage(cgImage:cg,size:NSSize(width:100,height:80)))
        NotificationCenter.default.removeObserver(observer)
        try require(emittedSource == NSRect(x:-990,y:220,width:50,height:30),"Copy completion lost the captured selection's global point coordinates")
        try require(emittedScreen == NSRect(x:-1000,y:200,width:100,height:80),"Copy completion lost the source display")
        let retinaFlight = EditorController(image:NSImage(cgImage:cg,size:NSSize(width:100,height:80)),selection:NSRect(x:10,y:10,width:25,height:15),screenFrame:NSRect(x:-1000,y:200,width:50,height:40))
        let retinaObserver = NotificationCenter.default.addObserver(forName:Notification.Name("ScreenshotCompleted"),object:nil,queue:nil) { note in
            emittedSource = note.userInfo?["sourceFrame"] as? NSRect
        }
        retinaFlight.finish(NSImage(cgImage:cg,size:NSSize(width:100,height:80)))
        NotificationCenter.default.removeObserver(retinaObserver)
        try require(emittedSource == NSRect(x:-990,y:210,width:25,height:15),"Retina capture pixels must not be used as animation points")
        let canvas = EditorCanvas(image:NSImage(cgImage:cg,size:NSSize(width:100,height:80)),overlay:true); canvas.frame = NSRect(x:0,y:0,width:100,height:80)
        canvas.tool = .rectangle; canvas.width = 4; canvas.begin(at:NSPoint(x:60,y:5)); canvas.drag(to:NSPoint(x:90,y:25)); canvas.end(at:NSPoint(x:90,y:25))
        guard let output = canvas.renderedImage() else { throw NSError(domain:"EditorVerification",code:4) }; let bitmap = NSBitmapImageRep(cgImage:output)
        try require(output.width == 100 && output.height == 80,"Native export size changed")
        try require((bitmap.colorAt(x:5,y:5)?.blueComponent ?? 0)>0.9 && (bitmap.colorAt(x:5,y:75)?.redComponent ?? 0)>0.9,"Export pixel orientation flipped")
        try require((bitmap.colorAt(x:60,y:70)?.redComponent ?? 0)>0.9 && (bitmap.colorAt(x:60,y:70)?.blueComponent ?? 1)<0.1,"Annotation coordinates flipped")
        canvas.outputRect = NSRect(x:10,y:5,width:30,height:20); guard let cropped = canvas.renderedImage() else { throw NSError(domain:"EditorVerification",code:5) }
        try require(cropped.width == 30 && cropped.height == 20 && (NSBitmapImageRep(cgImage:cropped).colorAt(x:1,y:1)?.redComponent ?? 0)>0.9,"Selection crop coordinates changed")
        canvas.outputRect = NSRect(x:0,y:0,width:100,height:80); canvas.begin(at:NSPoint(x:60,y:15)); canvas.drag(to:NSPoint(x:65,y:20)); canvas.end(at:NSPoint(x:65,y:20)); try require(canvas.marks[0].rect.minX == 65 && canvas.marks[0].rect.minY == 10,"Automatic shape movement failed")
        canvas.begin(at:NSPoint(x:95,y:30)); canvas.drag(to:NSPoint(x:98,y:35)); canvas.end(at:NSPoint(x:98,y:35)); try require(canvas.marks[0].rect.maxX == 98 && canvas.marks[0].rect.maxY == 35,"Shape handle resize failed")
        canvas.undoAction(); try require(canvas.marks.isEmpty,"Undo did not remove last annotation")
        let arrow = EditorMark(tool:.arrow,points:[NSPoint(x:10,y:10),NSPoint(x:60,y:60)],color:.red,width:8); try require(arrow.path().contains(NSPoint(x:35,y:35)),"Filled arrow geometry failed")
        let text = EditorMark(tool:.text,points:[NSPoint(x:25,y:65)],color:.red,width:7.5,text:"A\nB"); try require(text.rect.height > 20 && text.rect.midY == 65,"Multiline text or center positioning failed")
        let longText = String(repeating:"long text ",count:25)
        let bounded = EditorMark(tool:.text,points:[NSPoint(x:50,y:40)],color:.red,width:7.5,text:longText,textMeasurementBounds:NSSize(width:100,height:80))
        let unbounded = EditorMark(tool:.text,points:[NSPoint(x:50,y:40)],color:.red,width:7.5,text:longText)
        try require(bounded.rect.width < unbounded.rect.width && bounded.rect.height > unbounded.rect.height,"Text no longer measures inside its superview bounds")
        canvas.tool = .text; canvas.begin(at:NSPoint(x:30,y:30))
        try require(canvas.textView != nil && canvas.textView?.frame.minX == canvas.viewRect(canvas.marks.last!.rect).minX+5,"Text field or five-point inset changed")
        canvas.finishText()
        try require(originalEmojiPresets[1] == "⛽️" && originalEmojiPresets[2] == "👏" && originalEmojiPresets[14] == "😮‍💨" && originalEmojiPresets[15] == "🤫","Original emoji presets changed")
        for y in 0..<80 { for x in 0..<100 { let value:CGFloat = (x+y)%2 == 0 ? 0 : 1; rep.setColor(NSColor(deviceRed:value,green:value,blue:value,alpha:1),atX:x,y:y) } }
        guard let checker = rep.cgImage else { throw NSError(domain:"EditorVerification",code:6) }; let mosaic = EditorCanvas(image:NSImage(cgImage:checker,size:NSSize(width:100,height:80)),overlay:true); mosaic.frame = NSRect(x:0,y:0,width:100,height:80); mosaic.tool = .mosaic; mosaic.width = 12; mosaic.begin(at:NSPoint(x:10,y:10)); mosaic.drag(to:NSPoint(x:80,y:10)); mosaic.end(at:NSPoint(x:80,y:10))
        guard let redacted = mosaic.renderedImage() else { throw NSError(domain:"EditorVerification",code:7) }; let pixels = NSBitmapImageRep(cgImage:redacted)
        guard let a = pixels.colorAt(x:21,y:69),let b = pixels.colorAt(x:22,y:69),let outside = pixels.colorAt(x:21,y:30) else { throw NSError(domain:"EditorVerification",code:8) }
        try require(abs(a.redComponent-b.redComponent)<0.01 && a.alphaComponent > 0.99,"Freehand mosaic retained underlying checker pixels or transparency")
        try require(abs(outside.redComponent-(rep.colorAt(x:21,y:30)?.redComponent ?? -1))<0.01,"Mosaic modified pixels outside brush mask")
        let view = NSImageView(frame:NSRect(x:0,y:0,width:100,height:80)); view.image = NSImage(cgImage:redacted,size:NSSize(width:100,height:80)); view.imageScaling = .scaleAxesIndependently; let pdf = view.dataWithPDF(inside:view.bounds)
        guard let provider = CGDataProvider(data:pdf as CFData),let document = CGPDFDocument(provider),let page = document.page(at:1) else { throw NSError(domain:"EditorVerification",code:9) }
        try require(document.numberOfPages == 1 && page.getBoxRect(.mediaBox).size == NSSize(width:100,height:80),"PDF dimensions changed")
        print("Editor verified: native pixel crop, orientation, auto move/resize/undo, arrow, text, opaque freehand mosaic, PDF")
    }
}
