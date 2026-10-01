[Setup]
AppName=Animind Player
AppVersion=0.2.0
AppPublisher=Animind
AppPublisherURL=https://github.com/FNXDOOM/AniMind_Native
DefaultDirName={autopf}\AnimindPlayer
DefaultGroupName=Animind Player
OutputDir=.\qt_host\build
OutputBaseFilename=AnimindPlayer-v0.2.0-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=qt_host\resources\icons\animind.ico
UninstallDisplayIcon={app}\AnimindQtHost.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copy the main executable and everything in the Release folder (DLLs, qml folder, etc.)
Source: "qt_host\build\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Animind Player"; Filename: "{app}\AnimindQtHost.exe"
Name: "{group}\{cm:UninstallProgram,Animind Player}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Animind Player"; Filename: "{app}\AnimindQtHost.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\AnimindQtHost.exe"; Description: "{cm:LaunchProgram,Animind Player}"; Flags: nowait postinstall skipifsilent
