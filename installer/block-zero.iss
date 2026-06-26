; Inno Setup script for the Block Zero wallet (Windows).
; Produces a single double-click "Block-Zero-Setup.exe" that installs the GUI
; wallet per-user (no admin / UAC prompt) and creates Start Menu + Desktop
; shortcuts named "Block Zero".
;
; Build (after a windeployqt'd Release build):
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ^
;     /DSourceDir="...\blockzero-core\build\bin\Release" ^
;     /DAppVersion=1.0.0 installer\block-zero.iss
;
; SourceDir must contain bitcoin-qt.exe plus the Qt runtime (Qt6*.dll, the
; platforms/ tls/ etc. plugin folders) and the VC++ runtime DLLs.

#ifndef SourceDir
  #define SourceDir "..\..\blockzero-core\build\bin\Release"
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "Block Zero"
#define AppExe "Block Zero.exe"
#define AppPublisher "Block Zero"
#define AppURL "https://bloz.org"

[Setup]
AppId={{8F3A1C2E-5B6D-4E7F-9A0B-1C2D3E4F5A6B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
; Per-user install: no administrator rights, no UAC prompt.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=Block-Zero-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The GUI executable, renamed to the friendly Block Zero name.
Source: "{#SourceDir}\bitcoin-qt.exe"; DestDir: "{app}"; DestName: "{#AppExe}"; Flags: ignoreversion
; Everything else (DLLs, Qt plugin folders, helper exes), minus the items we
; handle specially or do not want to ship.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "bitcoin-qt.exe,vc_redist.x64.exe"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
