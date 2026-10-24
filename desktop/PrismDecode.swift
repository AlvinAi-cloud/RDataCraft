import Foundation
@main struct PrismDecode {
    static func main() {
        do {
            guard CommandLine.arguments.count==2 else {throw NSError(domain:"PrismXML",code:3,userInfo:[NSLocalizedDescriptionKey:"Choose one PZFX file."])}
            let result=try PrismXMLReader.read(CommandLine.arguments[1])
            let data=try JSONSerialization.data(withJSONObject:result)
            FileHandle.standardOutput.write(data)
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8));exit(1)
        }
    }
}
