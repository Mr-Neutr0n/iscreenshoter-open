#!/usr/bin/env swift
// Independently authored geometric artwork. No artwork from other apps is used.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
let fm = FileManager.default
let icons = root.appendingPathComponent("Icons")
try fm.createDirectory(at: icons, withIntermediateDirectories: true)
let catalog = root.appendingPathComponent("Assets.xcassets")
try fm.createDirectory(at: catalog, withIntermediateDirectories: true)
func json(_ object: Any, _ url: URL) throws { try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url) }
try json(["info": ["author": "xcode", "version": 1]], catalog.appendingPathComponent("Contents.json"))
let colors = ["323232":"323232", "color-btn-bg1":"484848", "color_purchase_bg":"E7FE66", "color-view-bg":"323232", "color-title-color":"BBBBBB", "color-line-bg":"505050", "color-btn-bg":"484848", "color-toggle-bg":"262626"]
for (name, hex) in colors {
    let folder = catalog.appendingPathComponent(name + ".colorset")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let value = UInt32(hex, radix:16)!
    try json(["info": ["author":"xcode", "version":1], "colors": [["idiom":"universal", "color":["color-space":"srgb", "components":["red":Double((value >> 16) & 255)/255, "green":Double((value >> 8) & 255)/255, "blue":Double(value & 255)/255, "alpha":1.0]]]]], folder.appendingPathComponent("Contents.json"))
}
func path(_ points: [(CGFloat, CGFloat)], close: Bool = false, fill: Bool = false) {
    let p = NSBezierPath(); p.lineWidth = 1.6; p.lineCapStyle = .round; p.lineJoinStyle = .round
    for (i, point) in points.enumerated() { if i == 0 { p.move(to: NSPoint(x:point.0,y:point.1)) } else { p.line(to:NSPoint(x:point.0,y:point.1)) } }
    if close { p.close() }; if fill { p.fill() } else { p.stroke() }
}
func rect(_ x:CGFloat, _ y:CGFloat, _ w:CGFloat, _ h:CGFloat, radius:CGFloat = 0, fill:Bool = false) {
    let p = NSBezierPath(roundedRect:NSRect(x:x,y:y,width:w,height:h),xRadius:radius,yRadius:radius); p.lineWidth = 1.6
    if fill { p.fill() } else { p.stroke() }
}
func circle(_ x:CGFloat, _ y:CGFloat, _ d:CGFloat, fill:Bool = false) {
    let p = NSBezierPath(ovalIn:NSRect(x:x,y:y,width:d,height:d)); p.lineWidth = 1.6
    if fill { p.fill() } else { p.stroke() }
}
func glyph(_ name:String) {
    NSColor.white.set()
    switch name {
    case "icon_topbar", "icon_shot", "icon_tools_record":
        for pts:[(CGFloat,CGFloat)] in [[(3,9),(3,3),(9,3)],[(15,3),(21,3),(21,9)],[(21,15),(21,21),(15,21)],[(9,21),(3,21),(3,15)]] { path(pts) }
        if name == "icon_tools_record" { circle(8,8,8,fill:true) } else { circle(8,8,8) }
    case "icon_shot_A", "icon_tools_ocr":
        path([(3,8),(3,3),(8,3)]); path([(16,3),(21,3),(21,8)]); path([(21,16),(21,21),(16,21)]); path([(8,21),(3,21),(3,16)])
        path([(8,7),(12,17),(16,7)]); path([(10,10),(14,10)])
    case "icon_rectangle": rect(4,5,16,14,radius:1)
    case "icon_ellipse": let p = NSBezierPath(ovalIn:NSRect(x:3,y:5,width:18,height:14)); p.lineWidth = 1.6; p.stroke()
    case "icon_line": path([(4,4),(20,20)])
    case "icon_arrow": path([(4,4),(20,20)]); path([(11,20),(20,20),(20,11)])
    case "icon_pen": path([(4,4),(8,5),(20,17),(17,20),(5,8),(4,4)],close:true); path([(14,17),(17,14)])
    case "mosaic": for x in stride(from:4,through:16,by:6) { for y in stride(from:4,through:16,by:6) { rect(CGFloat(x),CGFloat(y),4,4,fill:(x+y)%12 == 8) } }
    case "icon_text", "icon_text 1": path([(5,19),(19,19)]); path([(12,19),(12,5)]); path([(8,5),(16,5)])
    case "add_Image": rect(3,4,18,16,radius:2); circle(6,13,3); path([(4,6),(10,12),(14,8),(18,13),(20,10)])
    case "icon_redo": path([(8,18),(4,14),(8,10)]); path([(4,14),(14,14),(19,10),(19,5)])
    case "Icon_tool_pin": path([(8,20),(16,20),(15,13),(19,9),(5,9),(9,13),(8,20)],close:true); path([(12,9),(12,3)])
    case "pin_arrow", "save_arrow": path([(6,15),(12,9),(18,15)])
    case "icon_share": rect(5,3,14,11,radius:2); path([(12,9),(12,21)]); path([(7,16),(12,21),(17,16)])
    case "save_image", "save_quick_image", "icon_save", "Icon_pin_save": path([(12,21),(12,8)]); path([(7,13),(12,8),(17,13)]); path([(4,8),(4,3),(20,3),(20,8)])
    case "icon_copy", "Icon_pin_copy": rect(4,7,12,14,radius:2); path([(9,7),(9,3),(21,3),(21,17),(16,17)])
    case "icon_openfolder": path([(3,4),(3,18),(10,18),(12,15),(21,15),(21,4),(3,4)],close:true)
    case "icon_delete", "icon_del": rect(6,4,12,14,radius:1); path([(4,19),(20,19)]); path([(9,19),(9,22),(15,22),(15,19)]); path([(10,7),(10,15)]); path([(14,7),(14,15)])
    case "icon_close_normal", "icon_close_black":
        if name == "icon_close_black" { NSColor.black.set() }; path([(6,6),(18,18)]); path([(6,18),(18,6)])
    case "btn_record_normal": circle(3,3,18); circle(8,8,8,fill:true)
    case "icon_settings": circle(7,7,10); for a in 0..<8 { let t = Double(a)*Double.pi/4; path([(12+CGFloat(cos(t))*7,12+CGFloat(sin(t))*7),(12+CGFloat(cos(t))*10,12+CGFloat(sin(t))*10)]) }; circle(10,10,4)
    case "icon_copy_ok": path([(4,12),(10,6),(20,18)])
    case "bar_drag": for x in [8,16] { for y in [5,12,19] { circle(CGFloat(x-1),CGFloat(y-1),2,fill:true) } }
    case "knob": rect(9,2,6,20,radius:3,fill:true)
    default: rect(5,5,14,14,radius:3)
    }
}
func png(size:CGFloat, draw:()->Void) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size*2),pixelsHigh:Int(size*2),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    bitmap.size = NSSize(width:size,height:size)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    let transform = NSAffineTransform(); transform.scale(by:size/24); transform.concat(); draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using:.png,properties:[:])!
}
let names = ["icon_topbar","icon_shot","icon_shot_A","btn_record_normal","icon_rectangle","icon_ellipse","icon_line","icon_arrow","icon_pen","mosaic","icon_text","icon_text 1","add_Image","icon_redo","icon_tools_ocr","icon_tools_record","Icon_tool_pin","icon_share","save_image","save_quick_image","save_arrow","icon_copy","Icon_pin_copy","Icon_pin_save","icon_save","icon_openfolder","icon_delete","icon_del","icon_close_normal","icon_close_black","icon_settings","icon_copy_ok","bar_drag","pin_arrow","knob"]
for name in names {
    let size:CGFloat = name == "icon_topbar" ? 18 : ["icon_shot","icon_shot_A","btn_record_normal"].contains(name) ? 42 : name == "save_arrow" ? 9 : 24
    try png(size:size) { glyph(name) }.write(to:icons.appendingPathComponent(name + ".png"))
}
for i in 1...5 {
    try png(size:96) {
        NSColor(srgbRed:0.25+Double(i)*0.10,green:0.8-Double(i)*0.07,blue:0.45,alpha:1).set()
        switch i {
        case 1: circle(2,2,20,fill:true)
        case 2: path([(12,22),(22,3),(2,3)],close:true,fill:true)
        case 3: rect(2,2,20,20,radius:5,fill:true)
        case 4: path([(12,23),(23,12),(12,1),(1,12)],close:true,fill:true)
        default: path([(12,23),(15,16),(23,15),(17,10),(19,2),(12,6),(5,2),(7,10),(1,15),(9,16)],close:true,fill:true)
        }
    }.write(to:icons.appendingPathComponent("q_\(i).png"))
}
let iconset = root.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let data = png(size:CGFloat(size*scale)/2) {
            NSColor(srgbRed:0.12,green:0.15,blue:0.20,alpha:1).set(); rect(0,0,24,24,radius:5,fill:true)
            NSColor(srgbRed:0.70,green:0.95,blue:0.36,alpha:1).set()
            for pts:[(CGFloat,CGFloat)] in [[(4,9),(4,4),(9,4)],[(15,4),(20,4),(20,9)],[(20,15),(20,20),(15,20)],[(9,20),(4,20),(4,15)]] { path(pts) }; circle(8,8,8)
        }
        try data.write(to:iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let iconutil = Process(); iconutil.executableURL = URL(fileURLWithPath:"/usr/bin/iconutil"); iconutil.arguments = ["-c","icns",iconset.path,"-o",root.appendingPathComponent("AppIcon.icns").path]; try iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated independent artwork and color definitions in Resources")
