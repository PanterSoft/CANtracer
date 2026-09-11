; Built by CI: iscc /DAppVersion=1.2.3 windows\installer.iss
[Setup]
AppName=CANtracer
AppVersion={#AppVersion}
AppPublisher=PanterSoft
AppPublisherURL=https://github.com/PanterSoft/CANtracer
DefaultDirName={autopf}\CANtracer
DefaultGroupName=CANtracer
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..
OutputBaseFilename=CANtracer-windows-x64-setup
Compression=lzma2
SolidCompression=yes

[Tasks]
Name: desktopicon; Description: "Create a &desktop icon"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\CANtracer"; Filename: "{app}\cantracer.exe"
Name: "{autodesktop}\CANtracer"; Filename: "{app}\cantracer.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\cantracer.exe"; Description: "Launch CANtracer"; Flags: nowait postinstall skipifsilent
