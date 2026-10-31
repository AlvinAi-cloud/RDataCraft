"""Windows association recipes; never change a user's protected UserChoice key."""


def windows_associations(version, uninstall=False):
    progid = 'RDataCraft.Study.' + version
    classes = r'Software\Classes'
    capability = r'Software\RDataCraft\Capabilities' + '\\' + version
    command = r'$\"$INSTDIR\RDataCraft.exe$\" $\"%1$\"'
    icon = r'$\"$INSTDIR\RDataCraftDocument.ico$\",0'
    if uninstall:
        lines = [f'  ReadRegStr $0 HKCU "{classes}\\{progid}\\shell\\open\\command" ""',
                 f"  ${{If}} $0 == '{command}'"]
        for ext in ('.rdcraft', '.rdatacraft'):
            lines += [f'    ReadRegStr $1 HKCU "{classes}\\{ext}" ""',
                      f'    ${{If}} $1 == "{progid}"',
                      f'      DeleteRegValue HKCU "{classes}\\{ext}" ""', '    ${EndIf}',
                      f'    DeleteRegValue HKCU "{classes}\\{ext}\\OpenWithProgids" "{progid}"',
                      f'    DeleteRegKey /ifempty HKCU "{classes}\\{ext}\\OpenWithProgids"',
                      f'    DeleteRegKey /ifempty HKCU "{classes}\\{ext}"']
        lines += [f'    DeleteRegKey HKCU "{classes}\\{progid}"',
                  f'    DeleteRegKey HKCU "{capability}"',
                  f'    DeleteRegValue HKCU "Software\\RegisteredApplications" "RDataCraft {version}"',
                  '  ${EndIf}']
    else:
        lines = [f'  WriteRegStr HKCU "{classes}\\{progid}" "" "RDataCraft Study"',
                 f'  WriteRegStr HKCU "{classes}\\{progid}\\DefaultIcon" "" \'{icon}\'',
                 f'  WriteRegStr HKCU "{classes}\\{progid}\\shell\\open\\command" "" \'{command}\'',
                 f'  WriteRegStr HKCU "{capability}" "ApplicationName" "RDataCraft"',
                 f'  WriteRegStr HKCU "{capability}" "ApplicationDescription" "RDataCraft scientific studies"',
                 f'  WriteRegStr HKCU "Software\\RegisteredApplications" "RDataCraft {version}" "{capability}"']
        for ext in ('.rdcraft', '.rdatacraft'):
            lines += [f'  WriteRegStr HKCU "{classes}\\{ext}\\OpenWithProgids" "{progid}" ""',
                      f'  WriteRegStr HKCU "{capability}\\FileAssociations" "{ext}" "{progid}"',
                      f'  ReadRegStr $0 HKCU "{classes}\\{ext}" ""',
                      f'  StrCpy $1 $0 {len("RDataCraft.Study.")}',
                      '  ${If} $0 == ""', f'    WriteRegStr HKCU "{classes}\\{ext}" "" "{progid}"',
                      '  ${ElseIf} $1 == "RDataCraft.Study."',
                      f'    WriteRegStr HKCU "{classes}\\{ext}" "" "{progid}"', '  ${EndIf}']
    return lines + ["  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'"]
