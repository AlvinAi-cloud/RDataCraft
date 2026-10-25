import Cocoa
// Verify each actual representation, not only the master artwork or plist.
var results:[[String:Any]]=[]
for input in CommandLine.arguments.dropFirst() {
    let folder=URL(fileURLWithPath:input)
    for file in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter({$0.pathExtension=="png"}).sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) {
        guard let bitmap=NSBitmapImageRep(data:try Data(contentsOf:file)) else {fatalError("Invalid PNG")}
        let w=bitmap.pixelsWide,h=bitmap.pixelsHigh
        var minX=w,minY=h,maxX=0,maxY=0
        for y in 0..<h {for x in 0..<w {if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.1 {minX=min(x,minX);maxX=max(x,maxX);minY=min(y,minY);maxY=max(y,maxY)}}}
        let scale=Double(maxX-minX+1)/Double(w)
        if folder.lastPathComponent=="revised.iconset" && scale<0.97 {fatalError("Icon representation has excessive padding: \(file.lastPathComponent)")}
        results.append(["set":folder.lastPathComponent,"representation":file.lastPathComponent,"width":w,"height":h,"visible_width":maxX-minX+1,"visible_fraction":scale])
    }
}
let data=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]);print(String(decoding:data,as:UTF8.self))
