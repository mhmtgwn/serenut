; C:\Users\notop\AndroidStudioProjects\shaman_new\windows\installer\serenut_installer.iss
; Inno Setup Compiler Script for Serenut OS Client
; Blueprint: Pilot Launch Sprint (Clean Windows Installer Configuration)

[Setup]
AppId={{5E22B005-9B28-4DE3-BB10-388C838F5F2B}
AppName=Serenut OS
AppVersion=1.0.5
AppPublisher=Serenut OS Software Technologies A.Ş.
AppPublisherURL=https://serenut.com/
AppSupportURL=https://serenut.com/faq.html
AppUpdatesURL=https://serenut.com/release-notes.html
DefaultDirName={userappdata}\SerenutOS
DisableDirPage=yes
DefaultGroupName=Serenut OS
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=SerenutOSSetup
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
Source: "..\..\build\windows\x64\runner\Release\serenutos.exe"; DestDir: "{app}"; DestName: "serenutos.exe"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Serenut OS"; Filename: "{app}\serenutos.exe"
Name: "{autodesktop}\Serenut OS"; Filename: "{app}\serenutos.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\serenutos.exe"; Description: "{cm:LaunchProgram,Serenut OS}"; Flags: nowait postinstall skipifsilent
