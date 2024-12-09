{====================================================================================}
{                           SYSTEM LEVEL PROCESS CREATION                            }
{                     WINDOWS SERVICE UTILITY BY: BITMASTERXOR                       }
{====================================================================================}
{                                                                                    }
{ PURPOSE: Creates and manages Windows services to execute processes with SYSTEM     }
{ privileges. Handles service creation, environment setup, and process launching.    }
{                                                                                    }
{ SECURITY: Requires administrative rights for service operations                    }
{====================================================================================}

unit uSysAccount;

interface

uses
  WinSvc,             // Service control
  SvcMgr,            // Service management
  Winapi.Windows,     // Core Windows API
  System.SysUtils,    // System utilities
  System.Classes;     // Core classes

{====================================================================================}
{                              SERVICE CLASS DEFINITION                              }
{====================================================================================}

type
  // Main service class for SYSTEM level operations
  TsSysAccount = class(TService)
    procedure ServiceExecute(Sender: TService);
  private
    lpApplicationName: PWideChar;    // Target executable
    lpCommandLine: PWideChar;        // Command line arguments
    lpCurrentDirectory: PWideChar;   // Working directory
  public
    function GetServiceController: TServiceController; override;
  end;

// Main entry point for SYSTEM process creation
procedure CreateProcessAsSystem(const lpApplicationName: PWideChar;
  const lpCommandLine: PWideChar = nil;
  const lpCurrentDirectory: PWideChar = nil);

var
  sSysAccount: TsSysAccount;

implementation

{$R *.dfm}

{====================================================================================}
{                              TYPE DECLARATIONS                                     }
{====================================================================================}

type
  // Extended service application for registration
  TServiceApplicationEx = class(TServiceApplication)
  end;

  // Helper for service registration
  TServiceApplicationHelper = class helper for TServiceApplication
  public
    procedure ServicesRegister(Install, Silent: Boolean);
  end;

{====================================================================================}
{                              EXTERNAL FUNCTION IMPORTS                             }
{====================================================================================}

// External Windows API functions
function IsUserAnAdmin: BOOL; stdcall;
  external 'shell32.dll' name 'IsUserAnAdmin';

function CreateEnvironmentBlock(var lpEnvironment: Pointer; hToken: THandle;
  bInherit: BOOL): BOOL; stdcall;
  external 'Userenv.dll';

function DestroyEnvironmentBlock(pEnvironment: Pointer): BOOL; stdcall;
  external 'Userenv.dll';

{====================================================================================}
{                              SECURITY CHECK FUNCTIONS                              }
{====================================================================================}

// Get process integrity level
function _GetIntegrityLevel(): DWORD;
type
  PTokenMandatoryLabel = ^TTokenMandatoryLabel;
  TTokenMandatoryLabel = packed record
    Label_: TSidAndAttributes;
  end;
var
  hToken: THandle;
  cbSize: DWORD;
  pTIL: PTokenMandatoryLabel;
  dwTokenUserLength: DWORD;
begin
  Result := 0;
  dwTokenUserLength := MAXCHAR;

  if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, hToken) then
  begin
    pTIL := Pointer(LocalAlloc(0, dwTokenUserLength));
    if pTIL = nil then Exit;

    cbSize := SizeOf(TTokenMandatoryLabel);
    if GetTokenInformation(hToken, TokenIntegrityLevel, pTIL, dwTokenUserLength, cbSize) then
      if IsValidSid((pTIL.Label_).Sid) then
        Result := GetSidSubAuthority((pTIL.Label_).Sid,
          GetSidSubAuthorityCount((pTIL.Label_).Sid)^ - 1)^;

    if hToken <> INVALID_HANDLE_VALUE then CloseHandle(hToken);
    LocalFree(Cardinal(pTIL));
  end;
end;

// Check if process has SYSTEM privileges
function IsUserAnSystem(): Boolean;
const
  SECURITY_MANDATORY_SYSTEM_RID = $00004000;
begin
  Result := (_GetIntegrityLevel = SECURITY_MANDATORY_SYSTEM_RID);
end;

{====================================================================================}
{                              SERVICE MANAGEMENT                                    }
{====================================================================================}

// Start Windows service
function StartTheService(Service: TService): Boolean;
var
  SCM: SC_HANDLE;
  ServiceHandle: SC_HANDLE;
begin
  Result := False;
  SCM := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);

  if (SCM <> 0) then
  begin
    try
      ServiceHandle := OpenService(SCM, PChar(Service.Name), SERVICE_ALL_ACCESS);
      if (ServiceHandle <> 0) then
      begin
        Result := StartService(ServiceHandle, 0, PChar(nil^));
        CloseServiceHandle(ServiceHandle);
      end;
    finally
      CloseServiceHandle(SCM);
    end;
  end;
end;

// Set unique service name using timestamp
procedure SetServiceName(Service: TService);
begin
  if Assigned(Service) then
  begin
    Service.DisplayName := 'System Service ' + DateTimeToStr(Now);
    Service.Name := 'SysService' + FormatDateTime('ddmmyyyyhhnnss', Now);
  end;
end;

{====================================================================================}
{                              PROCESS CREATION                                      }
{====================================================================================}

// Main procedure to create process with SYSTEM privileges
procedure CreateProcessAsSystem(const lpApplicationName: PWideChar;
  const lpCommandLine: PWideChar = nil;
  const lpCurrentDirectory: PWideChar = nil);
begin
  // Verify admin rights
  if not(IsUserAnAdmin) then
  begin
    SetLastError(ERROR_ACCESS_DENIED);
    Exit();
  end;

  // Check file exists
  if not(FileExists(lpApplicationName)) then
  begin
    SetLastError(ERROR_FILE_NOT_FOUND);
    Exit();
  end;

  // Handle SYSTEM vs non-SYSTEM context
  if (IsUserAnSystem) then
  begin
    // Direct execution if already SYSTEM
    SvcMgr.Application.Initialize;
    SvcMgr.Application.CreateForm(TsSysAccount, sSysAccount);
    sSysAccount.lpApplicationName := lpApplicationName;
    sSysAccount.lpCommandLine := lpCommandLine;
    sSysAccount.lpCurrentDirectory := lpCurrentDirectory;
    SetServiceName(sSysAccount);
    SvcMgr.Application.Run;
  end
  else
  begin
    // Create service to gain SYSTEM privileges
    SvcMgr.Application.Free;
    SvcMgr.Application := TServiceApplicationEx.Create(nil);
    SvcMgr.Application.Initialize;
    SvcMgr.Application.CreateForm(TsSysAccount, sSysAccount);
    SetServiceName(sSysAccount);
    SvcMgr.Application.ServicesRegister(True, True);
    try
      StartTheService(sSysAccount);
    finally
      SvcMgr.Application.ServicesRegister(False, True);
    end;
  end;
end;

{====================================================================================}
{                              HELPER IMPLEMENTATIONS                                }
{====================================================================================}

// Service registration helper
procedure TServiceApplicationHelper.ServicesRegister(Install, Silent: Boolean);
begin
  RegisterServices(Install, Silent);
end;

// Service controller callback
procedure ServiceController(CtrlCode: DWORD); stdcall;
begin
  sSysAccount.Controller(CtrlCode);
end;

function TsSysAccount.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

{====================================================================================}
{                              SERVICE EXECUTION                                     }
{====================================================================================}

// Main service execution - creates process in SYSTEM context
procedure TsSysAccount.ServiceExecute(Sender: TService);
var
  StartupInfo: TStartupInfoW;
  ProcessInfo: TProcessInformation;
  P: Pointer;
begin
  // Create environment block
  if CreateEnvironmentBlock(P, 0, True) then
  begin
    // Initialize process startup info
    ZeroMemory(@StartupInfo, SizeOf(StartupInfo));
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.lpDesktop := 'winsta0\default';
    StartupInfo.wShowWindow := SW_SHOWNORMAL;

    // Create process
    if CreateProcessW(lpApplicationName, lpCommandLine, nil, nil,
      False, CREATE_UNICODE_ENVIRONMENT, P, lpCurrentDirectory, StartupInfo,
      ProcessInfo) then
    begin
      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
    end;
    DestroyEnvironmentBlock(P);
  end;
  ExitProcess(0);
end;

end.
