; Build with scripts/package-windows.ps1. The AppId must remain stable for upgrades.
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef ReleaseTag
  #error ReleaseTag is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildNumber
  #error BuildNumber is required
#endif
#define AppExe "neutrino_proxy_client_desktop.exe"

[Setup]
AppId=cn.neutrino.neutrinoProxyClientDesktop
AppName=Neutrino Proxy
AppVersion={#AppVersion}
AppVerName=Neutrino Proxy {#ReleaseTag}
AppPublisher=Neutrino Proxy
AppPublisherURL=https://github.com/ynx-official/neutrino-proxy-client-desktop
AppSupportURL=https://github.com/ynx-official/neutrino-proxy-client-desktop/issues
AppUpdatesURL=https://github.com/ynx-official/neutrino-proxy-client-desktop/releases
DefaultDirName={localappdata}\Programs\Neutrino Proxy
DefaultGroupName=Neutrino Proxy
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=Neutrino Proxy
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=neutrino-proxy-client-desktop-{#ReleaseTag}-windows-x64-setup
VersionInfoVersion={#AppVersion}.{#BuildNumber}
Compression=lzma2/max
SolidCompression=yes
; The native host owns this mutex even after the Flutter window is closed.
; Ask the user to exit from the tray rather than interrupting live tunnels.
AppMutex=Local\NeutrinoProxyFlutter
CloseApplications=no
RestartApplications=no
UsePreviousAppDir=yes
UsePreviousTasks=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
chinesesimplified.AppRunningError=安装程序检测到 [name] 仍在运行。%n%n请在系统托盘中选择“退出应用”，然后点击“确定”继续。仅关闭主窗口不会退出后台内核。
chinesesimplified.UninstallAppRunningError=卸载程序检测到 [name] 仍在运行。%n%n请在系统托盘中选择“退出应用”，然后点击“确定”继续。连接配置会保留。

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Neutrino Proxy"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\Neutrino Proxy"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Neutrino Proxy}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

; User settings live in Roaming AppData and are deliberately outside [Files].
; Do not add an UninstallDelete rule for user settings or arbitrary app folders.
