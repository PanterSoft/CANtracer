; Built by CI: iscc /DAppVersion=1.2.3 windows\installer.iss
[Setup]
AppName=Pantrace
AppVersion={#AppVersion}
AppPublisher=PanterSoft
AppPublisherURL=https://github.com/PanterSoft/Pantrace
DefaultDirName={autopf}\Pantrace
DefaultGroupName=Pantrace
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..
OutputBaseFilename=Pantrace-windows-x64-setup
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: desktopicon; Description: "Create a &desktop icon"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Pantrace"; Filename: "{app}\pantrace.exe"
Name: "{autodesktop}\Pantrace"; Filename: "{app}\pantrace.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pantrace.exe"; Description: "Launch Pantrace"; Flags: nowait postinstall skipifsilent
