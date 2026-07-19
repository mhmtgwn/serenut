; C:\Users\notop\AndroidStudioProjects\shaman_new\windows\installer\serenut_installer.iss
; Inno Setup Compiler Script for Serenut OS Client
; Blueprint: Pilot Launch Sprint (Clean Windows Installer Configuration)

[Setup]
AppId={{5E22B005-9B28-4DE3-BB10-388C838F5F2B}
AppName=Serenut OS
AppVersion=1.1.2
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
; Flutter's Windows runner is linked against the Microsoft Visual C++ runtime.
; Bundle the official x64 redistributable so a clean customer machine never
; fails with a missing MSVCP140.dll / VCRUNTIME140.dll error.
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Serenut OS"; Filename: "{app}\serenutos.exe"
Name: "{autodesktop}\Serenut OS"; Filename: "{app}\serenutos.exe"; Tasks: desktopicon

[Run]
; vc_redist requires elevation even though Serenut OS is a per-user install.
; An already running installation necessarily has its runtime dependencies, so
; never launch the elevated redistributable during an in-app update.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Microsoft Visual C++ çalışma zamanı kuruluyor..."; Flags: waituntilterminated; Check: NeedsVCRuntime
Filename: "{app}\serenutos.exe"; Description: "{cm:LaunchProgram,Serenut OS}"; Flags: nowait postinstall skipifsilent

[Code]
function NeedsVCRuntime: Boolean;
var
  Installed: Cardinal;
begin
  { Updating an existing per-user installation must remain elevation-free. }
  if FileExists(ExpandConstant('{app}\serenutos.exe')) then
  begin
    Result := False;
    exit;
  end;

  { Avoid launching the redistributable when the x64 runtime is already present. }
  Result := not (
    RegQueryDWordValue(
      HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed',
      Installed
    ) and (Installed = 1)
  );
end;
