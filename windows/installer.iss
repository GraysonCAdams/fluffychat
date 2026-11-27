; Inno Setup script for the Seam Windows installer.
; Build with: scripts/package-windows.ps1

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef BuildDir
  #define BuildDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change the AppId! Inno Setup uses it to detect an existing
; installation, so that a new installer updates it in place. It is Seam's
; own: an installed FluffyChat has another and is left alone.
AppId={{B6D2F0A4-3C7E-4F5B-8A19-D4E1C7A09B52}
AppName=Seam
AppVersion={#AppVersion}
AppVerName=Seam {#AppVersion}
AppPublisher=Christian Kußowski
AppPublisherURL=https://fluffychat.im
AppSupportURL=https://github.com/krille-chan/fluffychat/issues
AppUpdatesURL=https://github.com/krille-chan/fluffychat/releases
VersionInfoVersion={#AppVersion}
; Per-user installation into %LOCALAPPDATA%\Programs, so that neither the
; installation nor updates require admin rights.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Seam
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=yes
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\fluffychat.exe
LicenseFile=..\LICENSE
OutputDir=..\build\windows\installer
OutputBaseFilename=fluffychat-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "dutch"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Remove assets of the previous version, which might not exist anymore.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Seam"; Filename: "{app}\fluffychat.exe"
Name: "{autodesktop}\Seam"; Filename: "{app}\fluffychat.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\fluffychat.exe"; Description: "{cm:LaunchProgram,Seam}"; Flags: nowait postinstall skipifsilent
