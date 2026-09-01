; ============================================================
; Serenut OS — Windows Installer Script
; Inno Setup 7 Compatible
; Build: flutter build windows --release
; ============================================================

#define MyAppName "Serenut OS"
#define MyAppVersion "1.3.31"
#define MyAppPublisher "Serenut Software Technologies"
#define MyAppURL "https://serenut.com"
#define MyAppExeName "serenutos.exe"
#define MyAppId "{{5E22B005-9B28-4DE3-BB10-388C838F5F2B}"

[Setup]
; NOTE: The value of AppId uniquely identifies this application.
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Serenut OS
UsePreviousAppDir=no
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
CloseApplications=yes
; Installer output
OutputDir=..\server\public\website\downloads
OutputBaseFilename=SerenutOS-v1.3.31
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=120
; Require Windows 10+
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Privacy / UAC
PrivilegesRequired=admin
; Sign installer
; SignTool=signtool sign /n "Serenut" /t "http://timestamp.digicert.com" $f

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Files]
; Main executable
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion restartreplace
; Flutter engine DLL
Source: "..\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion restartreplace
; Dart runtime
Source: "..\build\windows\x64\runner\Release\dartjni.dll"; DestDir: "{app}"; Flags: ignoreversion restartreplace
; SQLite
Source: "..\build\windows\x64\runner\Release\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion restartreplace
Source: "..\build\windows\x64\runner\Release\sqlite3_flutter_libs_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion restartreplace
; Crashpad error reporter
Source: "..\build\windows\x64\runner\Release\crashpad_handler.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\crashpad_wer.dll"; DestDir: "{app}"; Flags: ignoreversion
; Sentry monitoring
Source: "..\build\windows\x64\runner\Release\sentry.dll"; DestDir: "{app}"; Flags: ignoreversion
; Plugin DLLs
Source: "..\build\windows\x64\runner\Release\file_selector_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\permission_handler_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\share_plus_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
; Data directory (ICU locale data, Flutter assets)
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{#MyAppName} Kaldır"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[InstallDelete]
; Eski kullanıcı-bazlı AppData kurulumuna giden kısayolları temizle.
Type: files; Name: "{userdesktop}\{#MyAppName}.lnk"
Type: files; Name: "{userprograms}\{#MyAppName}\{#MyAppName}.lnk"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"

[Code]
// Custom installer messages (Turkish)
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    Log('Serenut OS kurulumu başlıyor...');
  if CurStep = ssPostInstall then
    Log('Serenut OS kurulumu tamamlandı!');
end;
