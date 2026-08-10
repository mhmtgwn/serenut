; Serenut OS — Windows Installer Script (Inno Setup 6)
; Dosya Adı: SerenutOS-v1.3.10.exe (+ karakteri olmadan, profesyonel format)

#define AppName "Serenut OS"
#define AppVersion "1.3.10"
#define AppPublisher "Serenut"
#define AppExeName "serenutos.exe"
#define SourceDir "..\build\windows\x64\runner\Release"

[Setup]
; Keep the original product identity and directory so an update replaces the
; installed application instead of creating a parallel SerenutOS installation.
AppId={{5E22B005-9B28-4DE3-BB10-388C838F5F2B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://serenut.com
AppSupportURL=https://serenut.com
AppUpdatesURL=https://serenut.com
DefaultDirName={autopf}\Serenut OS
DefaultGroupName={#AppName}
AllowNoIcons=yes
LicenseFile=
OutputDir=..\build\installer
OutputBaseFilename=SerenutOS-v{#AppVersion}
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "{#SourceDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\native_assets.json"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
