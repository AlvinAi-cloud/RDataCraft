import Cocoa
import CoreServices
import UniformTypeIdentifiers

// Explicit local setup utility, never run automatically by opening a study.
guard CommandLine.arguments.count == 4 else {fatalError("Usage: RegisterStudyTypes app.app review-files-directory report.json")}
let appURL=URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
let examples=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
let output=URL(fileURLWithPath:CommandLine.arguments[3])
guard let bundle=Bundle(url:appURL),let identifier=bundle.bundleIdentifier,
      bundle.object(forInfoDictionaryKey:"CFBundleName") as? String == "RDataCraft" else {fatalError("Expected the RDataCraft application")}
let status=LSRegisterURL(appURL as CFURL,true)
guard status == noErr else {fatalError("Application registration failed: \(status)")}
let types=[("rdcraft","org.rdatacraft.study","Curve results review.rdcraft"),
           ("rdatacraft","org.rdatacraft.project","Legacy format review.rdatacraft")]
var records:[[String:Any]]=[]
for (ext,typeID,name) in types {
    guard let type=UTType(typeID) else {fatalError("Study type was not registered: \(typeID)")}
    let prior=LSCopyDefaultRoleHandlerForContentType(typeID as CFString,.all)?.takeRetainedValue() as String?
    var finished=false
    var failure:Error?
    NSWorkspace.shared.setDefaultApplication(at:appURL,toOpen:type) {error in failure=error;finished=true}
    let deadline=Date().addingTimeInterval(30)
    while !finished && Date()<deadline {_ = RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.05))}
    guard finished,failure==nil else {fatalError("Could not set the default for \(ext): \(String(describing:failure))")}
    let file=examples.appendingPathComponent(name)
    let resolved=NSWorkspace.shared.urlForApplication(toOpen:file)?.standardizedFileURL
    guard resolved==appURL else {fatalError("File association verification failed for \(ext): \(String(describing:resolved))")}
    let image=NSWorkspace.shared.icon(forFile:file.path)
    if let data=image.tiffRepresentation,let rep=NSBitmapImageRep(data:data),let png=rep.representation(using:.png,properties:[:]) {
        try png.write(to:output.deletingLastPathComponent().appendingPathComponent("finder-\(ext)-icon.png"))
    }
    records.append(["extension":ext,"type":typeID,"default_application":appURL.path,"previous_bundle_id":prior ?? "","verified":true])
}
let data=try JSONSerialization.data(withJSONObject:["bundle_id":identifier,"associations":records],options:[.prettyPrinted,.sortedKeys])
try data.write(to:output)
print(String(data:data,encoding:.utf8)!)
