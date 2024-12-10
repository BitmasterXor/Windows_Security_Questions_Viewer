{ ==================================================================================== }
{ WINDOWS SECURITY QUESTIONS RECOVERY }
{ SECURITY RESEARCH TOOL BY: BITMASTERXOR }
{ ==================================================================================== }
{ }
{ PURPOSE: This tool extracts and decrypts Windows security Q&A from registry }
{ REQUIREMENTS: Administrative privileges }
{ FEATURES: Registry extraction, decryption, clipboard support }
{ NOTES: Uses SYSTEM privileges, handles cleanup automatically }
{ ==================================================================================== }

unit Unit1;

{ ==================================================================================== }
{ INTERFACE }
{ ==================================================================================== }

interface

uses
  Winapi.Windows, // Windows API core
  Winapi.Messages, // Windows messaging
  System.SysUtils, // System utilities
  System.Variants, // Variant types
  System.Classes, // Core classes
  Vcl.Graphics, // Graphics support
  Vcl.Controls, // UI controls
  Vcl.Forms, // Forms
  Vcl.Dialogs, // Dialogs
  uSysAccount, // System account management
  clipbrd, // Clipboard operations
  Vcl.ComCtrls, // Common controls
  System.json, // JSON handling
  System.RegularExpressions, // Regex
  shellapi, // Shell operations
  Vcl.StdCtrls, // Standard controls
  Vcl.Menus; // Menu components

{ ==================================================================================== }
{ TYPE DECLARATIONS }
{ ==================================================================================== }

type
  TForm1 = class(TForm)
    Button1: TButton;
    // Main extraction trigger button... (starts the process of getting things done)
    ListView1: TListView; // Q&A display
    PopupMenu1: TPopupMenu; // Context menu
    c1: TMenuItem; // Copy question
    C2: TMenuItem; // Copy answer
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure c1Click(Sender: TObject);
    procedure C2Click(Sender: TObject);
  private
    { Private declarations }
  public
    DesktopPath: string; // Temp file location for extracted registry Dump...
  end;

var
  Form1: TForm1;

  { ==================================================================================== }
  { IMPLEMENTATION }
  { ==================================================================================== }

implementation

{$R *.dfm}
{ ==================================================================================== }
{ SECURITY HELPER FUNCTIONS }
{ ==================================================================================== }

// Verifies administrative privileges
function IsElevated: Boolean;
var
  TokenHandle: THandle; // Process token
  TokenInformation: TTokenElevation; // Elevation info
  ReturnLength: Cardinal; // Return size
begin
  Result := False;
  if OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, TokenHandle) then
    try
      if GetTokenInformation(TokenHandle, TokenElevation, @TokenInformation,
        SizeOf(TokenInformation), ReturnLength) then
        Result := TokenInformation.TokenIsElevated <> 0;
    finally
      CloseHandle(TokenHandle);
    end;
end;

{ ==================================================================================== }
{ DATA PROCESSING FUNCTIONS }
{ ==================================================================================== }

// Converts hex to readable text
function HexToString(const Hex: string): string;
var
  i: Integer;
  HexChar: string;
  Value: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(Hex) do
  begin
    HexChar := Copy(Hex, i, 2);
    if TRegEx.IsMatch(HexChar, '^[0-9A-Fa-f]{2}$') then
    begin
      Value := StrToInt('$' + HexChar);
      if Value >= 32 then // Printable ASCII only
        Result := Result + Chr(Value);
    end;
    Inc(i, 2);
  end;
end;

// Processes JSON Q&A data
procedure ParseQuestionsAndAnswers(const JSONStr: string);
var
  JSONObject: TJSONObject; // JSON container
  QuestionsArray: TJSONArray; // Q&A array
  QuestionObj: TJSONObject; // Single Q&A pair
  i: Integer;
  Question, Answer: string;
  li: TListItem;
begin
  try
    // Parse main JSON object
    JSONObject := TJSONObject.ParseJSONValue(JSONStr) as TJSONObject;
    if JSONObject = nil then
    begin
      ShowMessage('Invalid JSON format.');
      Exit;
    end;

    // Get questions array
    QuestionsArray := JSONObject.GetValue<TJSONArray>('questions');
    if QuestionsArray = nil then
    begin
      ShowMessage('No "questions" array found in the JSON.');
      Exit;
    end;

    // Process each Q&A pair
    for i := 0 to QuestionsArray.Count - 1 do
    begin
      QuestionObj := QuestionsArray.Items[i] as TJSONObject;
      Question := QuestionObj.GetValue<string>('question');
      Answer := QuestionObj.GetValue<string>('answer');

      // Add to display
      li := Form1.ListView1.Items.Add;
      li.Caption := Question;
      li.SubItems.Add(Answer)
    end;
  except
    on E: Exception do
      ShowMessage('Error parsing JSON: ' + E.Message);
  end;
end;

{ ==================================================================================== }
{ REGISTRY FILE PROCESSING }
{ ==================================================================================== }

// Extracts and processes registry data
procedure ParseRegFile(const FileName: string);
var
  RegFile: TStringList; // File contents
  Line, HexData: string; // Processing variables
  i: Integer;
  StartPos, StopPos: Integer; // Section markers
  InHexSection: Boolean; // Section flag
begin
  if not FileExists(FileName) then
  begin
    ShowMessage('File not found: ' + FileName);
    Exit;
  end;

  RegFile := TStringList.Create;
  try
    // Load and process file
    RegFile.LoadFromFile(FileName);
    HexData := '';
    InHexSection := False;

    for i := 0 to RegFile.Count - 1 do
    begin
      Line := Trim(RegFile[i]);

      // Find data section start
      StartPos := Pos('"ResetData"=hex:', Line);
      if StartPos > 0 then
      begin
        InHexSection := True;
        StartPos := StartPos + Length('"ResetData"=hex:');
        Line := Copy(Line, StartPos, MaxInt);
      end;

      // Find section end
      StopPos := Pos('"UserTile"=hex:', Line);
      if StopPos > 0 then
      begin
        InHexSection := False;
        Line := Copy(Line, 1, StopPos - 1);
      end;

      // Process hex data
      if InHexSection then
      begin
        Line := StringReplace(Line, ',', '', [rfReplaceAll]);
        Line := StringReplace(Line, '\', '', [rfReplaceAll]);
        HexData := HexData + Line;
      end;
    end;

    // Parse accumulated data
    if HexData <> '' then
      ParseQuestionsAndAnswers(HexToString(HexData));
  finally
    RegFile.Free;
  end;
end;

{ ==================================================================================== }
{ EVENT HANDLERS }
{ ==================================================================================== }

// Main extraction process
procedure TForm1.Button1Click(Sender: TObject);
var
  FileName: string;
  ElevatedProcess: string;
begin
  // Clear previous results
  if self.ListView1.Items.Count > 0 then
    self.ListView1.Clear;

  // Setup and execute extraction
  FileName := DesktopPath + '\something.txt';
  ElevatedProcess := 'C:\Windows\system32\cmd.exe';
  CreateProcessAsSystem(Pwidechar(ElevatedProcess));

  // Wait for file creation
  while not FileExists(FileName) do
    sleep(1000);

  // Process and cleanup
  ParseRegFile(FileName);
  if FileExists(FileName) then
    Deletefile(FileName);
end;

// Copy question to clipboard
procedure TForm1.c1Click(Sender: TObject);
begin
  if self.ListView1.Selected = nil then
    Exit;
  Clipboard.AsText := ListView1.Selected.Caption;
end;

// Copy answer to clipboard
procedure TForm1.C2Click(Sender: TObject);
begin
  if self.ListView1.Selected = nil then
    Exit;
  Clipboard.AsText := ListView1.Selected.SubItems[0];
end;

{ ==================================================================================== }
{ FORM INITIALIZATION }
{ ==================================================================================== }

// Initial setup and privilege check
procedure TForm1.FormCreate(Sender: TObject);
var
  UserName: array [0 .. 255] of Char;
  UserNameLen: DWORD;
  SearchRec: TSearchRec;
  AllFilesExist: Boolean;
begin
  // Verify admin rights
  if IsElevated = False then
  begin
    ShowMessage('This Application Must Be Executed With Admin Rights!');
    halt;
  end;

  // Setup paths
  DesktopPath := GetEnvironmentVariable('USERPROFILE') + '\Desktop';
  UserNameLen := SizeOf(UserName) div SizeOf(Char);

  // Check SYSTEM privileges
  if GetUserName(UserName, UserNameLen) then
  begin
    if StrComp(UserName, 'SYSTEM') = 0 then
    begin
      // Export registry for all users
      if FindFirst('C:\Users\*', faDirectory, SearchRec) = 0 then
        try
          repeat
            if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') and
              (SearchRec.Name <> 'Public') and (SearchRec.Name <> 'Default') and
              (SearchRec.Name <> 'All Users') and
              (SearchRec.Name <> 'Default User') and
              (SearchRec.Attr and faDirectory <> 0) then
            begin
              ShellExecute(0, nil, 'cmd.exe',
                PChar('/c reg export "HKLM\SAM\SAM\Domains\Account\Users\000003E9" "C:\Users\'
                + SearchRec.Name + '\Desktop\something.txt" /y'), nil, SW_HIDE);
            end;
          until FindNext(SearchRec) <> 0;
        finally
          FindClose(SearchRec);
        end;

      // Wait for all exports
      repeat
        AllFilesExist := True;
        if FindFirst('C:\Users\*', faDirectory, SearchRec) = 0 then
          try
            repeat
              if (SearchRec.Name <> '.') and (SearchRec.Name <> '..') and
                (SearchRec.Name <> 'Public') and (SearchRec.Name <> 'Default')
                and (SearchRec.Name <> 'All Users') and
                (SearchRec.Name <> 'Default User') and
                (SearchRec.Attr and faDirectory <> 0) then
              begin
                if not FileExists('C:\Users\' + SearchRec.Name +
                  '\Desktop\something.txt') then
                begin
                  AllFilesExist := False;
                  Break;
                end;
              end;
            until FindNext(SearchRec) <> 0;
          finally
            FindClose(SearchRec);
          end;
        if not AllFilesExist then
          sleep(100);
      until AllFilesExist;

      // Cleanup any SYSWOW64 something.txt files found on the SYSTEM Desktop as it will not be needed (Just extra cleanup in case we need it done!)
      if FileExists
        ('C:\Windows\SysWOW64\config\systemprofile\Desktop\something.txt') then
      begin
        Deletefile
          ('C:\Windows\SysWOW64\config\systemprofile\Desktop\something.txt');
      end;

      // now that we have done our business its time to kill ourselves out...
      halt;
    end;
  end;
end;

end.
