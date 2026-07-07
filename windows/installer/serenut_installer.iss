; C:\Users\notop\AndroidStudioProjects\shaman_new\windows\installer\serenut_installer.iss
; Inno Setup Compiler Script for Serenut OS POS Client (Release Candidate 1)
; Blueprint: Pilot Launch Sprint (Clean Windows Installer Configuration)

[Setup]
AppId={{5E22B005-9B28-4DE3-BB10-388C838F5F2B}
AppName=Serenut POS
AppVersion=1.0.0
AppPublisher=Serenut OS Software Technologies A.Ş.
AppPublisherURL=https://serenut.com/
AppSupportURL=https://serenut.com/faq.html
AppUpdatesURL=https://serenut.com/release-notes.html
DefaultDirName={userappdata}\SerenutPOS
DisableDirPage=yes
DefaultGroupName=Serenut POS
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=SerenutPOSSetup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\shaman_new.exe"; DestDir: "{app}"; DestName: "serenut_pos.exe"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Serenut POS"; Filename: "{app}\serenut_pos.exe"
Name: "{autodesktop}\Serenut POS"; Filename: "{app}\serenut_pos.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\serenut_pos.exe"; Description: "{cm:LaunchProgram,Serenut POS}"; Flags: nowait postinstall skipifsilent
