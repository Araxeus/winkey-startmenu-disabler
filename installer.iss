; Compile with build.ps1, which passes /DAppVersion.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppGuid "833F386A-62D2-4DF9-955B-F8DF8A9F2013"
#define AppName "Disable WinKey Start Menu"
#define AppExe  "disable-winkey-startmenu.exe"

[Setup]
AppId={{{#AppGuid}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Araxeus
AppPublisherURL=https://github.com/Araxeus/disable-winkey-startmenu
AppSupportURL=https://github.com/Araxeus/disable-winkey-startmenu/issues
VersionInfoVersion={#AppVersion}

; Setup elevates through UAC and installs for all users. Declining UAC closes setup.
; /CURRENTUSER installs for the current user without admin.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=commandline

; The elevated task must launch an exe that only admins can modify, so the folder stays fixed.
DefaultDirName={autopf}\disable-winkey-startmenu
DisableDirPage=yes
DisableProgramGroupPage=yes

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; [Code] stops the app, so Restart Manager is not needed.
CloseApplications=no

SetupIconFile=icons\disable_start_menu.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir=dist
OutputBaseFilename=disable-winkey-startmenu-setup

[Files]
Source: "dist\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "Stops a lone Win key press from opening the Start menu"

; HKA is HKLM for all-users installs and HKCU for just-me installs.
; Task Manager lists this entry under Startup apps.
[Registry]
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue

; Running as the original user lets the exe hand off to the elevated task.
[Run]
Filename: "{app}\{#AppExe}"; Description: "Start {#AppName}"; Flags: nowait postinstall runasoriginaluser

[Code]
const
  TaskName = 'disable-winkey-startmenu';
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{{#AppGuid}}_is1';
  ApprovedKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  TASK_CREATE_OR_UPDATE = 6;
  TASK_LOGON_INTERACTIVE_TOKEN = 3;

var
  // Install, Update, Repair, or Downgrade. Set from the version already installed in this mode.
  InstallAction: String;
  InstalledVersion: String;

function GetInstallAction: String;
var
  Installed, Current: Int64;
  Order: Integer;
begin
  Result := 'Install';
  if not RegQueryStringValue(HKA, UninstallKey, 'DisplayVersion', InstalledVersion) then
    Exit;

  Result := 'Update';
  if not (StrToVersion(InstalledVersion, Installed) and StrToVersion('{#AppVersion}', Current)) then
    Exit;

  Order := ComparePackedVersion(Current, Installed);
  if Order = 0 then
    Result := 'Repair'
  else if Order < 0 then
    Result := 'Downgrade';
end;

function ActionGerund: String;
begin
  if InstallAction = 'Repair' then
    Result := 'Repairing'
  else if InstallAction = 'Update' then
    Result := 'Updating'
  else
    Result := 'Downgrading';
end;

procedure InitializeWizard;
begin
  InstallAction := GetInstallAction;
  Log('Install action: ' + InstallAction + ' (installed: ' + InstalledVersion + ', setup: {#AppVersion})');
end;

// Relabels the wizard when this mode already has a copy installed.
procedure CurPageChanged(CurPageID: Integer);
begin
  if InstallAction = 'Install' then
    Exit;

  if CurPageID = wpReady then begin
    WizardForm.PageNameLabel.Caption := 'Ready to ' + InstallAction;
    WizardForm.PageDescriptionLabel.Caption := 'Setup is ready to ' + Lowercase(InstallAction) + ' {#AppName}.';

    if InstallAction = 'Repair' then
      WizardForm.ReadyLabel.Caption := 'Version ' + InstalledVersion + ' is already installed. ' +
        'Setup will reinstall it, restoring its files, startup entry and elevated task.'
    else if InstallAction = 'Update' then
      WizardForm.ReadyLabel.Caption := 'Setup will update {#AppName} from version ' +
        InstalledVersion + ' to {#AppVersion}.'
    else
      WizardForm.ReadyLabel.Caption := 'A newer version (' + InstalledVersion + ') is installed. ' +
        'Setup will replace it with version {#AppVersion}.';

    WizardForm.NextButton.Caption := '&' + InstallAction;
  end
  else if CurPageID = wpInstalling then begin
    WizardForm.PageNameLabel.Caption := ActionGerund;
    WizardForm.PageDescriptionLabel.Caption := 'Please wait while Setup ' + Lowercase(InstallAction) + 's {#AppName}.';
  end
  else if CurPageID = wpFinished then
    WizardForm.FinishedLabel.Caption := 'Setup has finished ' + Lowercase(ActionGerund) + ' {#AppName}.';
end;

procedure StopApp;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
end;

function XmlEscape(S: String): String;
begin
  Result := S;
  StringChangeEx(Result, '&', '&amp;', True);
  StringChangeEx(Result, '<', '&lt;', True);
  StringChangeEx(Result, '>', '&gt;', True);
end;

// Registers an on-demand task that runs the exe elevated for the installing user.
// The exe hands off to it when launched unelevated. The settings override defaults that would
// kill the app after 72 hours, stop it on battery, and run it at below-normal priority.
procedure RegisterElevatedTask;
var
  Service, Folder: Variant;
  Dir, Xml: String;
begin
  Dir := XmlEscape(ExpandConstant('{app}'));
  Xml :=
    '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' +
    '<RegistrationInfo><Description>Runs {#AppName} elevated</Description></RegistrationInfo>' +
    '<Principals><Principal id="Author">' +
      '<LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel>' +
    '</Principal></Principals>' +
    '<Settings>' +
      '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>' +
      '<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' +
      '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' +
      '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' +
      '<Priority>4</Priority>' +
    '</Settings>' +
    '<Actions Context="Author"><Exec>' +
      '<Command>"' + Dir + '\{#AppExe}"</Command>' +
      '<Arguments>/task</Arguments>' +
      '<WorkingDirectory>' + Dir + '</WorkingDirectory>' +
    '</Exec></Actions>' +
    '</Task>';

  try
    Service := CreateOleObject('Schedule.Service');
    Service.Connect();
    Folder := Service.GetFolder('\');
    Folder.RegisterTask(TaskName, Xml, TASK_CREATE_OR_UPDATE, '', '', TASK_LOGON_INTERACTIVE_TOKEN);
  except
    SuppressibleMsgBox(
      'Could not register the elevated task, so the app will run without elevation.' + #13#10#13#10 +
      GetExceptionMessage, mbError, MB_OK, IDOK);
  end;
end;

// Keeps one install per user. An all-users install replaces a just-me install,
// and a just-me install refuses to run over an all-users install.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Uninstaller: String;
  ResultCode: Integer;
begin
  Result := '';

  if not IsAdminInstallMode and RegKeyExists(HKLM, UninstallKey) then begin
    Result := '{#AppName} is already installed for all users. ' +
      'Run this setup for all users to update it, or uninstall it first.';
    Exit;
  end;

  StopApp;

  if IsAdminInstallMode and RegQueryStringValue(HKCU, UninstallKey, 'UninstallString', Uninstaller) then
    Exec(RemoveQuotes(Uninstaller), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and IsAdminInstallMode then
    RegisterElevatedTask;
end;

// Both cleanup steps run in either mode. A step that has nothing to remove, or lacks access, does nothing.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    Exec(ExpandConstant('{sys}\schtasks.exe'), '/delete /tn ' + TaskName + ' /f', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    StopApp;
  end;

  if CurUninstallStep = usPostUninstall then begin
    RegDeleteValue(HKCU, ApprovedKey, '{#AppName}');
    RegDeleteValue(HKLM, ApprovedKey, '{#AppName}');
  end;
end;
