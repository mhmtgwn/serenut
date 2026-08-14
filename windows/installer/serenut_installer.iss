; C:\Users\notop\AndroidStudioProjects\shaman_new\windows\installer\serenut_installer.iss
; Inno Setup Compiler Script for Serenut OS Client
; Blueprint: Pilot Launch Sprint (Clean Windows Installer Configuration)

[Setup]
AppId={{5E22B005-9B28-4DE3-BB10-388C838F5F2B}
AppName=Serenut OS
AppVersion=1.3.29
AppPublisher=Serenut OS Software Technologies A.Ş.
AppPublisherURL=https://serenut.com/
AppSupportURL=https://serenut.com/faq.html
AppUpdatesURL=https://serenut.com/release-notes.html
DefaultDirName={autopf}\Serenut OS
UsePreviousAppDir=no
DisableDirPage=yes
DefaultGroupName=Serenut OS
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename=SerenutOSSetup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
AppMutex=SerenutOS_App_Mutex
CloseApplications=yes
CloseApplicationsFilter=*serenutos.exe*

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Files]
Source: "..\..\build\windows\x64\runner\Release\serenutos.exe"; DestDir: "{app}"; DestName: "serenutos.exe"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: ".sentry-native\*"; Flags: ignoreversion recursesubdirs createallsubdirs
; Flutter's Windows runner is linked against the Microsoft Visual C++ runtime.
; Bundle the official x64 redistributable so a clean customer machine never
; fails with a missing MSVCP140.dll / VCRUNTIME140.dll error.
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Serenut OS"; Filename: "{app}\serenutos.exe"
Name: "{commondesktop}\Serenut OS"; Filename: "{app}\serenutos.exe"

[InstallDelete]
; v1.2.0+52 and older used a per-user AppData installation. Remove only the
; stale shortcuts so users cannot accidentally launch the obsolete binary.
Type: files; Name: "{userdesktop}\Serenut OS.lnk"
Type: files; Name: "{userprograms}\Serenut OS\Serenut OS.lnk"

[Run]
; The installer already runs elevated because application files live under
; Program Files. Skip the redistributable when it is already installed.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Microsoft Visual C++ çalışma zamanı kuruluyor..."; Flags: waituntilterminated; Check: NeedsVCRuntime
; Product images never live on the VPS. Permit authenticated peer transfer only
; on trusted/private LAN profiles; the application still validates company and hash.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Serenut OS Ürün Görseli TCP"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Serenut OS Ürün Görseli TCP"" dir=in action=allow program=""{app}\serenutos.exe"" protocol=TCP localport=48731 profile=private"; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Serenut OS Ürün Görseli UDP"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Serenut OS Ürün Görseli UDP"" dir=in action=allow program=""{app}\serenutos.exe"" protocol=UDP localport=48732 profile=private"; Flags: runhidden waituntilterminated
Filename: "{app}\serenutos.exe"; Description: "{cm:LaunchProgram,Serenut OS}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Serenut OS Ürün Görseli TCP"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Serenut OS Ürün Görseli UDP"""; Flags: runhidden waituntilterminated

[Code]
function NeedsVCRuntime: Boolean;
var
  Installed: Cardinal;
begin
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
