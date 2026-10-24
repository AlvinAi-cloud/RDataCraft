// Original PZFX source-table reader. No Prism code or assets are included.
import Foundation
final class PrismNode {
    let name:String; let attributes:[String:String]; var text=""; var children:[PrismNode]=[]
    init(_ name:String,_ attributes:[String:String]) {self.name=name;self.attributes=attributes}
    var content:String {text}
    func child(_ name:String)->PrismNode? {children.first{$0.name==name}}
}
final class PrismXMLReader:NSObject,XMLParserDelegate {
    var root:PrismNode?; var stack:[PrismNode]=[];var nodes=0;var characters=0
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        nodes += 1
        if nodes>1_000_000 || stack.count>100 {parser.abortParsing();return}
        let node=PrismNode(name,attributes)
        if let parent=stack.last {parent.children.append(node)} else {root=node}
        stack.append(node)
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) {
        characters += string.utf8.count
        if characters>40_000_000 {parser.abortParsing();return}
        stack.last?.text += string
    }
    func parser(_ parser:XMLParser,foundCDATA data:Data) {
        guard let text=String(data:data,encoding:.utf8) else {parser.abortParsing();return}
        self.parser(parser,foundCharacters:text)
    }
    func parser(_ parser:XMLParser,didEndElement:String,namespaceURI:String?,qualifiedName:String?) {
        if !stack.isEmpty {let child=stack.removeLast();characters += child.text.utf8.count;if characters>80_000_000 {parser.abortParsing();return};stack.last?.text += child.text}
    }
    static func read(_ path:String)throws -> [[String:Any]] {
        let data=try Data(contentsOf:URL(fileURLWithPath:path))
        guard data.count<=30_000_000,let text=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16),!text.uppercased().contains("<!DOCTYPE"),!text.uppercased().contains("<!ENTITY") else {throw NSError(domain:"PrismXML",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose an XML PZFX file under 30 MB without external entities."])}
        let parser=XMLParser(data:data), reader=PrismXMLReader();parser.delegate=reader;parser.shouldResolveExternalEntities=false
        guard parser.parse(),let root=reader.root,root.name=="GraphPadPrismFile" else {throw parser.parserError ?? NSError(domain:"PrismXML",code:2,userInfo:[NSLocalizedDescriptionKey:"Invalid PZFX XML."])}
        func values(_ node:PrismNode)->[String] {node.children.filter{$0.name=="d"}.map { cell in
            if ["1","true","yes"].contains((cell.attributes["Excluded"] ?? "").lowercased()) {return ""}
            return cell.content.trimmingCharacters(in:.whitespacesAndNewlines)
        }}
        let tables=root.children.filter{$0.name=="Table"}
        guard tables.count<=100 else {throw NSError(domain:"PrismXML",code:4,userInfo:[NSLocalizedDescriptionKey:"Import supports up to 100 source tables; no tables were imported."])}
        return tables.map { table in
            let ys=table.children.filter{$0.name=="YColumn"}.map { column -> [String:Any] in
                ["name":column.child("Title")?.content ?? "", "subcolumns":column.children.filter{$0.name=="Subcolumn"}.map(values)]
            }
            let x=table.child("XColumn")
            return ["name":table.child("Title")?.content ?? "Imported table","type":table.attributes["TableType"] ?? "",
                "format":table.attributes["YFormat"] ?? "replicates","xFormat":table.attributes["XFormat"] ?? "none",
                "xTitle":x?.child("Title")?.content ?? "X","x":x?.children.first(where:{$0.name=="Subcolumn"}).map(values) ?? [],
                "rows":table.child("RowTitlesColumn")?.children.first(where:{$0.name=="Subcolumn"}).map(values) ?? [],"ys":ys]
        }
    }
}
