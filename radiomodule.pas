unit RadioModule;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, GraphType, UComplex, radiomessage, gen_graph;

type

  TModuleId = Cardinal;

  PDataStreamRec = ^TDataStreamRec;
  TDataStreamRec = record
    Next: PDataStreamRec;
    Counter: Integer;
    Index: Integer;
    Data: array of Complex;
  end;

  TRadioModule = class;

  TRadioLogLevel = (llVerbose, llInfo, llWarn, llError, llSystem);

  PRadioStringNode = ^TRadioStringNode;
  TRadioStringNode = record
    Next: PRadioStringNode;
    S: string;
  end;

  { TRadioStringStorage }

  TRadioStringStorage = class
  private
    FHead: TRadioStringNode;
    FLast: PRadioStringNode;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Store(const S: string): PtrUInt;
  end;

  { TRadioDataStream }

  TRadioDataStream = class
  const
    BLOCK_NUM = 3;
  private
    FName: string;
    FBlockSize: Integer;
    FFreeFlag: Boolean;
    FAllocted: PDataStreamRec;
    FBuffers: array of PDataStreamRec;
    FFree: PDataStreamRec;
    FModule: TRadioModule;
    FPortId: Integer;
    function GetBuffer(const Index: Integer): PComplex;
    function GetBufferCount: Integer;
    function GetDefBufferSize: Cardinal;
    procedure SetDefBufferSize(AValue: Cardinal);
    procedure FreeBlock(X: PDataStreamRec); // Lock is required
    procedure DumpList;
  public
    constructor Create(Module: TRadioModule; const AName: string; const BlockSize: Integer);
    destructor Destroy; override;
    procedure SafeFree;

    procedure EnsureBlockNumber(const AtLeast: Integer);

    procedure Lock;
    procedure Unlock;

    function TryAlloc(out Index: Integer): PComplex;
    procedure Broadcast(const Index: Integer; Listeners: TList);
    procedure Release(const Index: Integer); // Listeners call this to release buffer  // Alert: multi-thread

    function GetBufferSize(const Index: Integer): Integer;

    property Name: string read FName;
    property Buffer[const Index: Integer]: PComplex read GetBuffer;
    property BufferSize: Cardinal read GetDefBufferSize write SetDefBufferSize;
    property BufferCount: Integer read GetBufferCount;
    property PortId: Integer read FPortId write FPortId;
  end;

  TReceiveData = procedure (const P: PComplex; const Len: Integer) of object;

  { TStreamRegulator }

  TStreamRegulator = class
  private
    FData: array of Complex;
    FOnReceiveData: TReceiveData;
    FSize: Integer;
    FCursor: Integer;
    FOverlap: Integer;
    procedure SetOnReceiveData(AValue: TReceiveData);
    procedure SetOverlap(AValue: Integer);
    procedure SetSize(AValue: Integer);
    procedure CallOnRegulatedData;
  public
    constructor Create;
    procedure ReceiveData(P: PComplex; Len: Integer);

    property Size: Integer read FSize write SetSize;
    property Overlap: Integer read FOverlap write SetOverlap;
    property OnRegulatedData: TReceiveData read FOnReceiveData write SetOnReceiveData ;
  end;

  TRadioMessageId      = 0..31;
  TRadioMessageIdSet   = Cardinal;

  PRadioMessageNode = ^TRadioMessageNode;
  TRadioMessageNode = record
    Next: PRadioMessageNode;
    Msg: TRadioMessage;
  end;

  TRadioMessageQueue = class;
  TRadioRunQueue = class;
  PRadioThreadNode = ^TRadioThreadNode;

  { TRadioThread }

  TRadioThread = class(TThread)
  private
    FJob: TRadioMessageQueue;
    FNode: PRadioThreadNode;
    FRunQueue: TRadioRunQueue;
    FJobScheduled: PRTLEvent;
    FRunTimeAcc: TTime;  // maintained by TRadioRunQueue
    FStartTime: TTime;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;

    // Job want to yield, worker will pick a new job
    function Yield(Job: TRadioMessageQueue): Cardinal;

    property Job: TRadioMessageQueue read FJob write FJob;
    property Node: PRadioThreadNode read FNode write FNode;
    property Terminated;
  end;

  TRadioThreadNode = record
    Next: PRadioThreadNode;
    Thread: TRadioThread;
  end;

  PMessageQueueNode = ^TMessageQueueNode;
  TMessageQueueNode = record
    Next: PMessageQueueNode;
    Queue: TRadioMessageQueue;
  end;

  { TRadioRunQueue }

  TRadioRunQueue = class
  private
    FFirstJob: TMessageQueueNode;
    FIdleNode: TRadioThreadNode;
    FWorkers: array of TRadioThread;
    FDestroying: Boolean;
    FStatStart: TDateTime;
  private
    function GetSMP: Integer;
    procedure Schedule;
    procedure Lock;
    procedure UnLock;
    procedure WorkerIdle(Worker: TRadioThread);
  public
    constructor Create(const SMP: Integer = 4);
    destructor Destroy; override;
    function  PickJob: TRadioMessageQueue;
    procedure Request(Job: TRadioMessageQueue);

  public
    function GetWorkerLoadInfo(var Load: array of Double): Boolean;
    function GetRunningModules(var Modules: array of string): Boolean;
    property SMP: Integer read GetSMP;
  end;

  { TRadioMessageQueue }

  TRadioMessageQueue = class
  private
    FName: string;
    FInQueue: Boolean;
    FFirstExecMsg: TRadioMessageNode;
    FLastExecMsg: PRadioMessageNode;
    FMessageFilter: TRadioMessageIdSet;
    FRunQueue: TRadioRunQueue;
    FCPUTime: TTime;
    FYieldTime: TTime;
    FRunThread: TRadioThread;
    FDestroying: Boolean;
    function GetNeedExec: Boolean;
    procedure SetInQueue(AValue: Boolean);
    procedure RequestSchudule;
  protected
    procedure MessageExceute;      // execute one message in a single call
    procedure ProccessMessage(const Msg: TRadioMessage; var Ret: PtrInt); virtual; abstract;
  public
    constructor Create(RunQueue: TRadioRunQueue); virtual;
    procedure Lock;
    procedure UnLock;

    procedure StoreMessage(const Msg: TRadioMessage);
    procedure MessageQueueReset;

    property NeedExecution: Boolean read GetNeedExec;
    property InQueue: Boolean read FInQueue write SetInQueue;

    property Name: string read FName write FName;
    property CPUTime: TTime read FCPUTime;
    property RunThread: TRadioThread read FRunThread write FRunThread;
  end;

  TDataListener = record
    M: TModuleId;
    SourcePort: Integer;
    TargetPort: Integer;
  end;
  PDataListener = ^TDataListener;

  { TRadioModule }

  TRadioModule = class(TRadioMessageQueue, IGenDrawable)
  const
    ICON_SIZE = 50;
    HEADER_SIZE = 20;
    HEADER_FONT_HEIGHT = 15;
    BTN_CONFIG = '::';
    BTN_GUI    = 'gui';
    BODER_WIDTH = 2;
  private
    FGraphNode: TGenEntityNode;
    FId: TModuleId;
    FRefCount: Integer;
    FDefOutput: TRadioDataStream;
    FDescStr: TStringList;
    FGUIBtnRect: TRect;
    FConfigBtnRect: TRect;
    procedure SetId(AValue: TModuleId);
  protected
    FIcon: string;
    FHasGUI: Boolean;
    FHasConfig: Boolean;
    FInvalidated: Boolean;
{$IFDEF FPC}
    function QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} iid: tguid; out obj): longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
{$ELSE}
    function QueryInterface(const IID: TGUID; out Obj): HResult; virtual; stdcall;
{$ENDIF}
    function _AddRef: Integer; virtual; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    function _Release: Integer; virtual; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    procedure Measure(ACanvas: TCanvas; out Extent: TSize);
    procedure Draw(ACanvas: TCanvas; ARect: TRect);
    procedure MouseClick(const Pt: TPoint);
    function  Invalidated: Boolean;
  protected
    FDataListeners: TList;
    FFeatureListeners: TList;
    function  FindDataListener(Listener: TModuleId): Integer;
    procedure AddDataListener(Listener: TModuleId; const SourcePort, TargetPort: Integer);
    procedure AddFeatureListener(Listener: TModuleId);
    procedure RemoveDataListener(Listener: TModuleId);
    procedure RemoveFeatureListener(Listener: TModuleId);
    procedure ClearDataListeners;
    procedure ClearFeatureListeners;

    function Alloc(Stream: TRadioDataStream; out Index: Integer): PComplex;

    procedure ProccessMessage(const Msg: TRadioMessage; var Ret: Integer); override;
    procedure ProccessCustomMessage(const Msg: TRadioMessage; var Ret: Integer); virtual;

    procedure RMControl(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMData(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMSetFeature(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMReport(const Msg: TRadioMessage; var Ret: Integer); virtual;
    procedure RMTimer(const Msg: TRadioMessage; var Ret: Integer); virtual;

    function RMSetFrequency(const Msg: TRadioMessage; const Freq: Cardinal): Integer; virtual;
    function RMSetBandwidth(const Msg: TRadioMessage; const Bandwidth: Cardinal): Integer; virtual;
    function RMSetSampleRate(const Msg: TRadioMessage; const Rate: Cardinal): Integer; virtual;
    function RMPhaseAdjust(const Msg: TRadioMessage; const Rate: Cardinal): Integer; virtual;

    procedure DoConfigure; virtual;
    procedure DoShowGUI; virtual;

    procedure DoReset; virtual;
    procedure DoBeforeDestroy; virtual;
    procedure DoSyncDestroy; virtual;

    procedure Describe(Strs: TStrings); virtual;
  public
    procedure ShowConnections(Graph: TGenGraph);
    property GraphNode: TGenEntityNode read FGraphNode write FGraphNode;
  public
    constructor Create(RunQueue: TRadioRunQueue); override;
    destructor Destroy; override;

    class function LoadDefIconRes(ResName: string = ''): string;
    procedure GraphInvalidate;

    procedure PostMessage(const Id: Integer; const ParamH, ParamL: PtrUInt);
    procedure PostMessage(const Msg: TRadioMessage); virtual;
    procedure Broadcast(const Msg: TRadioMessage); overload;
    procedure Broadcast(const AId: Integer; const AParamH, AParamL: PtrUInt); overload;

    procedure ReceiveData(const P: PComplex; const Len: Integer); virtual; overload;
    procedure ReceiveData(const Port: Integer; const P: PComplex; const Len: Integer); virtual;

    property DefOutput: TRadioDataStream read FDefOutput;
    property Id: TModuleId read FId write SetId;
  end;

  TRadioModuleClass = class of TRadioModule;

  TBackgroundRadioModule = class;

  { TGenericRadioThread }

  TGenericRadioThread = class(TThread)
  private
    FModule: TBackgroundRadioModule;
    FParam: Pointer;
  protected
    procedure Execute; override;
  public
    constructor Create(Module: TBackgroundRadioModule);
    property Module: TBackgroundRadioModule read FModule write FModule;
    property Param: Pointer read FParam write FParam;
    property Terminated;
  end;

  { TBackgroundRadioModule }

  TBackgroundRadioModule = class(TRadioModule)
  protected
    FThread: TGenericRadioThread;
    procedure ThreadFun(Thread: TGenericRadioThread); virtual;
    procedure DoStopThreadFun; virtual; abstract;
    procedure DoBeforeDestroy; override;
  public
    constructor Create(RunQueue: TRadioRunQueue); override;
    destructor Destroy; override;
  end;

  { TRadioLogger }

  TRadioLogger = class
  private
    FLevel: TRadioLogLevel;  static;
  protected
    FInstance: TRadioLogger; static;
    procedure DoReport(const ALevel: TRadioLogLevel; const S: string); virtual;
  public
    class procedure Report(const ALevel: TRadioLogLevel; const AFormat: string; Params: array of const); overload;
    class procedure Report(const ALevel: TRadioLogLevel; const AFormat: string);
    class property Level: TRadioLogLevel read FLevel write FLevel;

    class function MsgToStr(const M: TRadioMessage): string;
    class function GetInstance: TRadioLogger;
  end;

// I don't like to creae too many CriticalSections
procedure RadioGlobalLock;
procedure RadioGlobalUnlock;

function MakeMessage(const Id: Integer; const ParamH, ParamL: PtrUInt;
  const Sender: TRadioModule = nil): TRadioMessage;

function ClassNameToModuleName(const S: string): string;

implementation

uses
  Math, SignalBasic, utils, util_math, util_config, RadioSystem;

var
  RadioGlobalCS: TRTLCriticalSection;

procedure RadioGlobalLock;
begin
  EnterCriticalsection(RadioGlobalCS);
end;

procedure RadioGlobalUnlock;
begin
  LeaveCriticalsection(RadioGlobalCS);
end;

function MakeMessage(const Id: Integer; const ParamH, ParamL: PtrUInt;
  const Sender: TRadioModule): TRadioMessage;
begin
  Result.Id := Id;
  Result.ParamH := ParamH;
  Result.ParamL := ParamL;
  if Assigned(Sender) then Result.Sender := Sender.Name;
end;

function ClassNameToModuleName(const S: string): string;
begin
  Result := S;
  if Length(Result) < 1 then Exit;
  if Pos('TRadio', S) = 1 then Delete(Result, 1, 6)
  else
    if Result[1] in ['t', 'T'] then Delete(Result, 1, 1);
  if Copy(Result, Length(Result) - 5, 6) = 'Module' then Delete(Result, Length(Result) - 5, 6);
end;

{ TRadioStringStorage }

constructor TRadioStringStorage.Create;
begin
  FLast := @FHead;
end;

destructor TRadioStringStorage.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TRadioStringStorage.Clear;
var
  X: PRadioStringNode;
begin
  X := FHead.Next;
  while Assigned(X) do
  begin
    FHead.Next := X^.Next;
    Dispose(X);
    X := FHead.Next;
  end;
  FLast := @FHead;
end;

function TRadioStringStorage.Store(const S: string): PtrUInt;
var
  X: PRadioStringNode;
begin
  New(X);
  X^.S := Copy(S, 1, Length(S));
  X^.Next := nil;
  FLast^.Next := X;
  Result := PtrUInt(@X^.S);
end;

{ TRadioLogger }

procedure TRadioLogger.DoReport(const ALevel: TRadioLogLevel; const S: string);
begin

end;

class procedure TRadioLogger.Report(const ALevel: TRadioLogLevel;
  const AFormat: string; Params: array of const);
var
  S: string;
begin
  if not Assigned(FInstance) then Exit;
  if FLevel > ALevel then Exit;
  S := Format(AFormat, Params);
  FInstance.DoReport(ALevel, S);
end;

class procedure TRadioLogger.Report(const ALevel: TRadioLogLevel;
  const AFormat: string);
begin
  if not Assigned(FInstance) then Exit;
  if FLevel > ALevel then Exit;
  FInstance.DoReport(ALevel, AFormat);
end;

class function TRadioLogger.MsgToStr(const M: TRadioMessage): string;
begin
  if M.Sender <> '' then
    Result := 'from ' + M.Sender
  else
    Result := 'from unknown';
  Result := Result + Format(' {%d, %d, %d}', [M.Id, M.ParamH, M.ParamL]);
end;

class function TRadioLogger.GetInstance: TRadioLogger;
begin
  Result := FInstance;
end;

{ TRadioMessageQueue }

function TRadioMessageQueue.GetNeedExec: Boolean;
begin
  Result := (not FDestroying) and Assigned(FFirstExecMsg.Next);
end;

procedure TRadioMessageQueue.SetInQueue(AValue: Boolean);
var
  Req: Boolean = False;
begin
  Lock;
  if FInQueue <> AValue then
  begin
    FInQueue := AValue;
    Req := not AValue;
  end;
  Unlock;

  if FDestroying and (not FInQueue) then
  begin
    Free;
    Exit;
  end;

  if Req and NeedExecution then
    RequestSchudule;
end;

procedure TRadioMessageQueue.RequestSchudule;
begin
  if (not FDestroying) and (not FInQueue) then FRunQueue.Request(Self);
end;

procedure TRadioMessageQueue.MessageExceute;
var
  Msg: TRadioMessage;
  Ret: Integer = 0;
  P: PRadioMessageNode;
begin
  if FDestroying then Exit;
  if not Assigned(FFirstExecMsg.Next) then Exit;
  Lock;
  P := FFirstExecMsg.Next;
  Msg := P^.Msg;
  FFirstExecMsg.Next := P^.Next;
  if not Assigned(FFirstExecMsg.Next) then
    FLastExecMsg := @FFirstExecMsg;
  UnLock;
  Dispose(P);

  try
    TRadioLogger.Report(llVerbose, Format('in thread #%d, %s  start exec msg %s', [GetThreadID, Name, TRadioLogger.MsgToStr(Msg)]));
    ProccessMessage(Msg, Ret);
    TRadioLogger.Report(llVerbose, Name + ' msg exec done');
  except
    on E: Exception do
      TRadioLogger.Report(llError, Format('MessageExceute Exception: %s when handling %s', [E.Message, TRadioLogger.MsgToStr(Msg)]));
  end;
end;

constructor TRadioMessageQueue.Create(RunQueue: TRadioRunQueue);
begin
  FMessageFilter := $FFFFFFFF;
  FLastExecMsg := @FFirstExecMsg;
  FRunQueue := RunQueue;
end;

procedure TRadioMessageQueue.Lock;
begin
  RadioGlobalLock;
end;

procedure TRadioMessageQueue.UnLock;
begin
  RadioGlobalUnlock;
end;

procedure TRadioMessageQueue.StoreMessage(const Msg: TRadioMessage);
var
  P: PRadioMessageNode;
begin
  if FDestroying then Exit;

  New(P);
  P^.Msg := Msg;
  P^.Next := nil;

  Lock;
  FLastExecMsg^.Next := P;
  FLastExecMsg := P;
  UnLock;
  RequestSchudule;
end;

procedure TRadioMessageQueue.MessageQueueReset;
  procedure FreeList(P: PRadioMessageNode);
  var
    T: PRadioMessageNode;
  begin
    while Assigned(P) do
    begin
      T := P^.Next;
      Dispose(P);
      P := T;
    end;
  end;

begin
  Lock;
  FreeList(FFirstExecMsg.Next);
  FFirstExecMsg.Next := nil;
  FLastExecMsg := @FFirstExecMsg;
  UnLock;
end;

{ TBackgroundRadioModule }

procedure TBackgroundRadioModule.ThreadFun(Thread: TGenericRadioThread);
begin
  Sleep(10);
end;

procedure TBackgroundRadioModule.DoBeforeDestroy;
begin
  FThread.Terminate;
  DoStopThreadFun;
  FThread.WaitFor;
  inherited DoBeforeDestroy;
end;

constructor TBackgroundRadioModule.Create(RunQueue: TRadioRunQueue);
begin
  inherited;
  FThread := TGenericRadioThread.Create(Self);
end;

destructor TBackgroundRadioModule.Destroy;
begin
  FThread.Free;
  inherited;
end;

{ TGenericRadioThread }

procedure TGenericRadioThread.Execute;
begin
  while not Terminated do
    if Assigned(FModule) then FModule.ThreadFun(Self);
end;

constructor TGenericRadioThread.Create(Module: TBackgroundRadioModule);
begin
  inherited Create(True);
  FModule := Module;
  Start;
end;

{ TRadioRunQueue }

function TRadioRunQueue.GetSMP: Integer;
begin
  Result := Length(FWorkers);
end;

procedure TRadioRunQueue.Schedule;
label
  again;
var
  T: PRadioThreadNode;
  P: PMessageQueueNode;
begin
again:
  if FDestroying then Exit;

  Lock;
  if Assigned(FFirstJob.Next) and Assigned(FIdleNode.Next) then
  begin
    T := FIdleNode.Next;
    FIdleNode.Next := T^.Next;
    P := FFirstJob.Next;
    FFirstJob.Next := P^.Next;
    UnLock;

    T^.Thread.FStartTime := Now;
    T^.Thread.Job := P^.Queue;
    Dispose(P);
    RTLEventSetEvent(T^.Thread.FJobScheduled);
    goto again;
  end
  else
    Unlock;
end;

procedure TRadioRunQueue.Lock;
begin
  RadioGlobalLock;
end;

procedure TRadioRunQueue.UnLock;
begin
  RadioGlobalUnlock;
end;

procedure TRadioRunQueue.WorkerIdle(Worker: TRadioThread);
var
  J: TRadioMessageQueue;
begin
  if FDestroying then Exit;
  Worker.FRunTimeAcc := Worker.FRunTimeAcc + (Now - Worker.FStartTime);
  Worker.FStartTime := 0;
  Lock;
  Worker.Node^.Next := FIdleNode.Next;
  FIdleNode.Next := Worker.Node;
  Unlock;
  if Assigned(Worker.FJob) then
  begin
    J := Worker.FJob;
    Worker.FJob := nil;
    J.InQueue := False;  // here, worker might be re-scheduled!
  end;
  Schedule;
end;

constructor TRadioRunQueue.Create(const SMP: Integer);
var
  I: Integer;
  P: PRadioThreadNode;
begin
  SetLength(FWorkers, SMP);
  for I := 1 to SMP do
  begin
    New(P);
    P^.Thread := TRadioThread.Create;
    P^.Thread.Node := P;
    P^.Thread.FRunQueue := Self;
    P^.Next := FIdleNode.Next;
    FIdleNode.Next := P;
    FWorkers[I - 1] := P^.Thread;

    TRadioLogger.Report(llVerbose, 'TRadioRunQueue: thread #%d added', [P^.Thread.ThreadID]);
  end;
  FStatStart := Now;
end;

destructor TRadioRunQueue.Destroy;
var
  T: TRadioThread;
begin
  FDestroying := True;
  Lock;
  FIdleNode.Next := nil;
  Unlock;
  for T in FWorkers do T.Free;
  inherited;
end;

function TRadioRunQueue.PickJob: TRadioMessageQueue;
var
  P: PMessageQueueNode;
begin
  Result := nil;
  if FDestroying then Exit;

  if not Assigned(FFirstJob.Next) then Exit;

  Lock;
  if not Assigned(FFirstJob.Next) then
  begin
    UnLock;
    Exit;
  end;
  P := FFirstJob.Next;
  FFirstJob.Next := P^.Next;
  UnLock;

  Result := P^.Queue;
  Dispose(P);
end;

procedure TRadioRunQueue.Request(Job: TRadioMessageQueue);
var
  T: PRadioThreadNode;
  P: PMessageQueueNode;
  F: Boolean = False;
begin
  Lock;
  if not Job.InQueue then
  begin
    F := True;
    Job.InQueue := True;
  end;
  Unlock;

  if not F then Exit;

  Lock;
  if Assigned(FIdleNode.Next) then
  begin
    T := FIdleNode.Next;
    FIdleNode.Next := T^.Next;
    UnLock;

    T^.Thread.FStartTime := Now;
    T^.Thread.Job := Job;
    RTLEventSetEvent(T^.Thread.FJobScheduled);

    Exit;
  end
  else
    UnLock;

  New(P);
  P^.Queue := Job;

  Lock;
  P^.Next := FFirstJob.Next;
  FFirstJob.Next := P;
  Unlock;

  Schedule;
end;

function TRadioRunQueue.GetWorkerLoadInfo(var Load: array of Double): Boolean;
var
  I: Integer;
  T: TDateTime;
  S: TDateTime;
begin
  Result := Length(Load) = Length(FWorkers);
  if not Result then Exit;
  T := Now;
  S := Max(1 / MSecsPerDay, T - FStatStart);
  FStatStart := Now;
  for I := 0 to High(FWorkers) do
  begin
    if FWorkers[I].FStartTime > 0 then
    begin
      Load[I] := (FWorkers[I].FRunTimeAcc + (T - FWorkers[I].FStartTime)) / S;
      FWorkers[I].FStartTime := T;
    end
    else begin
      Load[I] := FWorkers[I].FRunTimeAcc / S;
    end;
    FWorkers[I].FRunTimeAcc := 0.0;
  end;
end;

function TRadioRunQueue.GetRunningModules(var Modules: array of string
  ): Boolean;
var
  I: Integer;
  M: TRadioMessageQueue;
begin
  Result := Length(Modules) = Length(FWorkers);
  if not Result then Exit;
  for I := 0 to High(FWorkers) do
  begin
    Modules[I] := '<nil>';
    M := FWorkers[I].Job;
    if not Assigned(M) then Continue;

    try
      Modules[I] := M.Name;
    except
    end;
  end;
end;

{ TRadioThread }

procedure TRadioThread.Execute;
var
  T: TTime;
begin
  while not Terminated do
  begin
    RTLEventWaitFor(FJobScheduled);
    if Terminated then Break;

    RTLEventResetEvent(FJobScheduled);

    if Assigned(FJob) then
    begin
      T := Now;

      with FJob do
      begin
        RunThread := Self;
        while (not Terminated) and NeedExecution do
          MessageExceute;
        RunThread := nil;
        FCPUTime := FCPUTime + Now - T - FYieldTime;
        FYieldTime := 0;
      end;

      FRunQueue.WorkerIdle(Self);
    end
    else;
  end;
end;

constructor TRadioThread.Create;
begin
  FJobScheduled := RTLEventCreate;
  inherited Create(False);
end;

destructor TRadioThread.Destroy;
begin
  Terminate;
  RTLeventSetEvent(FJobScheduled);
  WaitFor;
  RTLEventDestroy(FJobScheduled);
  inherited Destroy;
end;

function TRadioThread.Yield(Job: TRadioMessageQueue): Cardinal;
var
  J: TRadioMessageQueue;
  T: TTime;
begin
  Result := 0;

  J := FRunQueue.PickJob;
  if not Assigned(J) then Exit;

  // we only exec one message here, and this job will be at the tail of the queue
  // if it has more messaages.
  if J.NeedExecution then
  begin
    T := Now;
    J.RunThread := Self;
    J.MessageExceute;
    T := Now - T;
    J.FCPUTime := J.FCPUTime + T;
    J.RunThread := nil;

    Job.FYieldTime := Job.FYieldTime + T;
  end;

  J.InQueue := False;

  Result := Max(1, Round(T * MSecsPerDay));
end;

{ TStreamRegulator }

procedure TStreamRegulator.SetOnReceiveData(AValue: TReceiveData);
begin
  if FOnReceiveData = AValue then Exit;
  FOnReceiveData := AValue;
end;

procedure TStreamRegulator.SetOverlap(AValue: Integer);
begin
  if AValue < 0 then
    FOverlap := 0
  else if AValue > FSize - 1 then
    FOverlap := FSize - 1
  else
    FOverlap := AValue;
end;

procedure TStreamRegulator.SetSize(AValue: Integer);
begin
  if AValue < 1 then Exit;
  if FSize = AValue then Exit;

  FSize := AValue;
  CallOnRegulatedData;

  SetLength(FData, FSize);
  Overlap := FOverlap;
end;

procedure TStreamRegulator.CallOnRegulatedData;
var
  I: Integer = 0;
begin
  while FCursor >= FSize do
  begin
    if Assigned(FOnReceiveData) then FOnReceiveData(@FData[I], FSize);
    Inc(I, FSize - FOverlap);
    Dec(FCursor, FSize - FOverlap);
  end;
  if FCursor > 0 then
    Move(FData[I], FData[0], FCursor * SizeOf(FData[0]));
end;

constructor TStreamRegulator.Create;
begin
  FSize := 1024;
  SetLength(FData, FSize);
end;

procedure TStreamRegulator.ReceiveData(P: PComplex; Len: Integer);
var
  F: Integer;
  S: Integer;
begin
  while Len > 0 do
  begin
    F := FSize - FCursor;
    if F <= 0 then
    begin
      CallOnRegulatedData;
      F := FSize - FCursor;
    end;
    S := Min(F, Len);
    Move(P^, FData[FCursor], S * SizeOf(P^));
    Inc(P, S);
    Inc(FCursor, S);
    Dec(Len, S);
  end;
  CallOnRegulatedData;
end;

{ TRadioDataStream }

function TRadioDataStream.GetBuffer(const Index: Integer): PComplex;
begin
  Result := @(FBuffers[Index]^.Data[0]);
end;

function TRadioDataStream.GetBufferCount: Integer;
begin
  Result := Length(FBuffers);
end;

function TRadioDataStream.GetDefBufferSize: Cardinal;
begin
  Result := FBlockSize;
end;

procedure TRadioDataStream.SetDefBufferSize(AValue: Cardinal);
begin
  Lock;
  FBlockSize := AValue;
  Unlock;
end;

procedure TRadioDataStream.FreeBlock(X: PDataStreamRec);
var
  P: PDataStreamRec;
begin
  if FAllocted <> X then
  begin
    P := FAllocted;
    while Assigned(P) and (P^.Next <> X) do P := P^.Next;
    if Assigned(P) then
    begin
      P^.Next := X^.Next;
      X^.Next := FFree;
      FFree := X;
    end
    else begin
      TRadioLogger.Report(llError, 'TRadioDataStream.FreeBlock: %d not in Allocated list', [PtrUInt(X)]);
      DumpList;
      raise Exception.Create('TRadioDataStream.FreeBlock: not in Allocated list');
    end;
  end
  else begin
    FAllocted := X^.Next;
    X^.Next := FFree;
    FFree := X;
  end;

  if FFreeFlag and (not Assigned(FAllocted)) then
  begin
    Unlock;
    Free;
  end;
end;

procedure TRadioDataStream.DumpList;
var
  I: Integer;
begin
  for I := 0 to High(FBuffers) do
    TRadioLogger.Report(llVerbose, 'buff[%d] = %d, next = %d, count = %d',
                        [I, PtrUInt(FBuffers[I]), PtrUInt(FBuffers[I]^.Next), FBuffers[I]^.Counter]);
  TRadioLogger.Report(llVerbose, 'Allocated head = %d', [PtrUInt(FAllocted)]);
  TRadioLogger.Report(llVerbose, 'Free      head = %d', [PtrUInt(FFree)]);
end;

constructor TRadioDataStream.Create(Module: TRadioModule; const AName: string;
  const BlockSize: Integer);
begin
  inherited Create;
  FName := AName;
  FBlockSize := BlockSize;
  FModule := Module;
  EnsureBlockNumber(BLOCK_NUM);
end;

destructor TRadioDataStream.Destroy;
var
  P: PDataStreamRec;
begin
  for P in FBuffers do
  begin
    SetLength(P^.Data, 0);
    Dispose(P);
  end;
  inherited;
end;

procedure TRadioDataStream.SafeFree;
begin
  Lock;
  FFreeFlag := Assigned(FAllocted);
  if not FFreeFlag then Free;
  Unlock;
end;

procedure TRadioDataStream.EnsureBlockNumber(const AtLeast: Integer);
var
  I: Integer;
  P: PDataStreamRec;
begin
  I := High(FBuffers) + 1;
  if I < AtLeast then
  begin
    TRadioLogger.Report(llWarn, '%d EnsureBlockNumber %d', [PtrUInt(Self), AtLeast]);

    Lock;
    SetLength(FBuffers, AtLeast);
    while I < AtLeast do
    begin
      New(P);
      FillByte(P^, SizeOf(P^), 0);
      //SetLength(P^.Data, FBlockSize);
      P^.Index := I;
      P^.Next := FFree;
      FFree := P;
      FBuffers[I] := P;
      Inc(I);
    end;
    Unlock;
  end;
end;

procedure TRadioDataStream.Lock;
begin
  RadioGlobalLock;
end;

procedure TRadioDataStream.Unlock;
begin
  RadioGlobalUnlock;
end;

function TRadioDataStream.TryAlloc(out Index: Integer): PComplex;
var
  X: PDataStreamRec = nil;
begin
  Result := nil;
  if FFreeFlag then Exit;

  Lock;
  if Assigned(FFree) then
  begin
    X := FFree;
    FFree := X^.Next;
    X^.Next := FAllocted;
    FAllocted := X;
  end;
  Unlock;

  if not Assigned(X) then Exit;

  if Length(X^.Data) <> FBlockSize then
    SetLength(X^.Data, FBlockSize);
  Result := @X^.Data[0];
  Index := X^.Index;
end;

procedure TRadioDataStream.Broadcast(const Index: Integer; Listeners: TList);
var
  M: TRadioMessage;
  P: Pointer;
  L: PDataListener;
  X: PDataStreamRec;
begin
  // assumption: buffer must be allocated!
  X := FBuffers[Index];
  X^.Counter := 0;
  for P in Listeners do
  begin
    L := PDataListener(P);
    if L^.SourcePort = PortId then Inc(X^.Counter);
  end;

  if X^.Counter < 1 then
  begin
    Lock;
    FreeBlock(X); // free it
    Unlock;
    Exit;
  end;

  with M do
  begin
    Id := RM_DATA;
    Sender := FModule.Name;
    ParamH := PtrInt(Self);
  end;

  for P in Listeners do
  begin
    L := PDataListener(P);
    if L^.SourcePort <> PortId then Continue;

    M.ParamL := (L^.TargetPort shl 16) or Index;
    if not RadioPostMessage(M, L^.M) then
      Release(Index);
  end;
end;

procedure TRadioDataStream.Release(const Index: Integer);
begin
  Lock;
  Dec(FBuffers[Index]^.Counter);
  if FBuffers[Index]^.Counter < 1 then
    FreeBlock(FBuffers[Index]);
  Unlock;
end;

function TRadioDataStream.GetBufferSize(const Index: Integer): Integer;
begin
  Result := Length(FBuffers[Index]^.Data);
end;

{ TRadioModule }

procedure TRadioModule.PostMessage(const Msg: TRadioMessage);
begin
  StoreMessage(Msg);
end;

procedure TRadioModule.Broadcast(const Msg: TRadioMessage);
var
  P: Pointer;
begin
  for P in FFeatureListeners do
    RadioPostMessage(Msg, TModuleId(P));
end;

procedure TRadioModule.Broadcast(const AId: Integer; const AParamH,
  AParamL: PtrUInt);
var
  M: TRadioMessage;
begin
  with M do
  begin
    Sender := Name;
    Id := AId;
    ParamH := AParamH;
    ParamL := AParamL;
  end;
  Broadcast(M);
end;

function TRadioModule.FindDataListener(Listener: TModuleId): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FDataListeners.Count - 1 do
  begin
    if PDataListener(FDataListeners[I])^.M = Listener then Exit(I);
  end;
end;

class function TRadioModule.LoadDefIconRes(ResName: string): string;
var
  N: string;
  L: TStrings;
begin
  if ResName = '' then ResName := ClassNameToModuleName(ClassName);
  ResName := ResName + '.icon.txt';
  N := GetResFullName(ResName);
  if FileExists(N) then
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(N);
      L.StrictDelimiter := True;
      L.Delimiter := ';';
      Result := L.DelimitedText;
    finally
      L.Free
    end;
  end
  else
    Result := 'text (0,0),' + ClassNameToModuleName(ClassName);
end;

procedure TRadioModule.SetId(AValue: TModuleId);
begin
  if FId <> 0 then Exception.Create('TRadioModule.SetId');
  FId := AValue;
end;

function TRadioModule.QueryInterface(constref iid: tguid; out obj): longint;
  stdcall;
begin
   if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TRadioModule._AddRef: Integer; stdcall;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TRadioModule._Release: Integer; stdcall;
begin
  Result := InterlockedDecrement(FRefCount);
  //if Result = 0 then
  //  Destroy;
end;

procedure TRadioModule.Measure(ACanvas: TCanvas; out Extent: TSize);
var
  E, F: TSize;
begin
  with ACanvas do
  begin
    Font.Height := HEADER_FONT_HEIGHT;
    Font.Style := [];
    E := TextExtent(Name);
    if FHasConfig then Inc(E.cx, TextExtent(BTN_CONFIG).cx + 20) else Inc(E.cx, 5);
    if FHasGUI then Inc(E.cx, TextExtent(BTN_GUI).cx + 20) else Inc(E.cx, 5);
  end;
  FDescStr.Clear;
  Describe(FDescStr);
  F := StyledTextExtent(ACanvas, FDescStr);
  Extent.cy := Max(ICON_SIZE, F.cy);
  Extent.cx := Max(ICON_SIZE, F.cx);
  Extent.cx := Max(Extent.cx, E.cx);
  Inc(Extent.cy, HEADER_SIZE + BODER_WIDTH * 2 + 6);
  Inc(Extent.cx, BODER_WIDTH * 2 + 4);
end;

procedure TRadioModule.Draw(ACanvas: TCanvas; ARect: TRect);
var
  IconRect: TRect;
  C: TPoint;
  E: TSize;
begin
  FInvalidated := False;
  with ACanvas do
  begin
    Pen.Style := psSolid;
    Pen.Width := BODER_WIDTH;
    Pen.Color := TColor($00AAFF);
    Brush.Color := clCream; // $fafafa;
    Brush.Style := bsSolid;
    RoundRect(ARect, 8, 8);
    FloodFill(ARect.Left + 10, ARect.Top + 10, clWhite, fsSurface);

    // shrink, border excluded
    Inc(ARect.Left, BODER_WIDTH + 1);
    Inc(ARect.Top, BODER_WIDTH + 1);
    Dec(ARect.Right, BODER_WIDTH - 1);
    Dec(ARect.Bottom, BODER_WIDTH - 1);

    Font.Style := [];
    Font.Height := HEADER_FONT_HEIGHT;
    Font.Color := clBlack;
    Font.Bold  := True;
    TextRect(ARect, ARect.Left + 3, ARect.Top, Name);

    // buttons
    Font.Color := TColor($FF5050);
    if FHasConfig then
    begin
      E := TextExtent(BTN_CONFIG);
      with FConfigBtnRect do
      begin
        Left := ARect.Right - E.cx - 8;
        Top  := ARect.Top;
        Right := Left + E.cx;
        Bottom := Top + E.cy;
        TextRect(ARect, Left, Top, BTN_CONFIG);
      end;
    end
    else
      FConfigBtnRect.Left := ARect.Right;
    if FHasGUI then
    begin
      E := TextExtent(BTN_GUI);
      with FGUIBtnRect do
      begin
        Left := FConfigBtnRect.Left - E.cx - 15;
        Top  := ARect.Top;
        Right := Left + E.cx;
        Bottom := Top + E.cy;
        TextRect(ARect, Left, Top, BTN_GUI);
      end;
    end;


    Pen.Width := 1;
    Inc(ARect.Top, HEADER_SIZE - BODER_WIDTH);
    Line(ARect.Left, ARect.Top, ARect.Right, ARect.Top);

    // icon
    C.x := (ARect.Left + ARect.Right) div 2;
    C.y := (ARect.Top + ARect.Bottom) div 2;
    IconRect.Left   := C.x - ICON_SIZE div 2;
    IconRect.Right  := C.x + ICON_SIZE div 2;
    IconRect.Top    := C.y - ICON_SIZE div 2;
    IconRect.Bottom := C.y + ICON_SIZE div 2;
    StrIconDraw(ACanvas, IconRect, FIcon);

    // description strings
    Font.Height := HEADER_FONT_HEIGHT;
    FDescStr.Clear;
    Describe(FDescStr);
    StyledTextOut(ACanvas, ARect, FDescStr);
  end;
end;

procedure TRadioModule.MouseClick(const Pt: TPoint);
begin
  if IsPtInRect(Pt, FGUIBtnRect) then
    PostMessage(RM_SHOW_MAIN_GUI, 0, 0)
  else if IsPtInRect(Pt, FConfigBtnRect) then
    PostMessage(RM_CONFIGURE, 0, 0);
end;

function TRadioModule.Invalidated: Boolean;
begin
  Result := FInvalidated;
end;

function TRadioModule.Alloc(Stream: TRadioDataStream; out Index: Integer
  ): PComplex;
var
  T: Cardinal = 0;
  I: Cardinal;
begin
  Result := Stream.TryAlloc(Index);
  while (not Assigned(Result)) and (not RunThread.Terminated) and (T < 150) do
  begin
    I := RunThread.Yield(Self);
    if I = 0 then
    begin
      Sleep(2);
      I := 2;
    end;
    Inc(T, I);
    Result := Stream.TryAlloc(Index);
  end;
end;

{
function TRadioModule.Alloc(Stream: TRadioDataStream; out Index: Integer
  ): PComplex;
var
  C: Integer = 0;
begin
  Result := Stream.TryAlloc(Index);
  while (not RunThread.Terminated) and (Result = nil) do
  begin
    Inc(C);
    if C > 200 then
    begin
      TRadioLogger.Report(llError, 'TRadioModule.Alloc(%s): possible dead-lock in , exit', [Name]);
      Exit;  // avoid possible dead-lock
    end;
    Sleep(10);
    Result := Stream.TryAlloc(Index);
  end;
end;
}

procedure TRadioModule.ProccessMessage(const Msg: TRadioMessage;
  var Ret: Integer);
begin
  case Msg.Id of
    RM_Control: RMControl(Msg, Ret);
    RM_DATA     : RMData(Msg, Ret);
    RM_REPORT   : RMReport(Msg, Ret);
    RM_SET_FEATURE: RMSetFeature(Msg, Ret);
    RM_TIMER      : RMTimer(Msg, Ret);
    RM_CONFIGURE:   TThread.Synchronize(nil, @DoConfigure);
    RM_SHOW_MAIN_GUI:   TThread.Synchronize(nil, @DoShowGUI);
    RM_DESTROY:
      begin
        // Free is called when InQueue := False
        FDestroying := True;
        DoBeforeDestroy;
      end;
    RM_ADD_FEATURE_LISTENER:
      AddFeatureListener(Msg.ParamL);
    RM_REMOVE_FEATURE_LISTENER:
      if Msg.ParamL <> INVALID_MODULE_ID then
        RemoveFeatureListener(Msg.ParamL)
      else
        ClearFeatureListeners;
    RM_ADD_DATA_LISTENER: AddDataListener(Msg.ParamL, Msg.ParamH shr 16, Msg.ParamH and $FFFF);
    RM_REMOVE_DATA_LISTENER:
      if Msg.ParamL <> INVALID_MODULE_ID then
        RemoveDataListener(Msg.ParamL)
      else
        ClearDataListeners
  else
    ProccessCustomMessage(Msg, Ret);
  end;
end;

procedure TRadioModule.ProccessCustomMessage(const Msg: TRadioMessage;
  var Ret: Integer);
begin

end;

procedure TRadioModule.RMControl(const Msg: TRadioMessage; var Ret: Integer);
begin
  case Msg.ParamH of
    RM_CONTROL_RESET: DoReset;
  end;
end;

procedure TRadioModule.RMData(const Msg: TRadioMessage; var Ret: Integer);
var
  B: TRadioDataStream;
  Port: Integer;
  S: Integer;
  procedure AllocBuff;
  begin
    DefOutput.EnsureBlockNumber(Round(S * 1.2 / DefOutput.BufferSize));
  end;
begin
  B := TRadioDataStream(Msg.ParamH);
  Port := Msg.ParamL shr 16;
  S := B.GetBufferSize(Msg.ParamL and $FFFF);
  AllocBuff;
  if Port = 0 then
    ReceiveData(B.Buffer[Msg.ParamL], S)
  else
    ReceiveData(Port, B.Buffer[Msg.ParamL and $FFFF], S);
  B.Release(Msg.ParamL and $FFFF);
end;

procedure TRadioModule.RMSetFeature(const Msg: TRadioMessage; var Ret: Integer);
begin
  case Msg.ParamH of
    RM_FEATURE_BANDWIDTH: RMSetBandwidth(Msg, Msg.ParamL);
    RM_FEATURE_FREQ:      RMSetFrequency(Msg, Msg.ParamL);
    RM_FEATURE_PHASE_ADJ: RMPhaseAdjust(Msg, Msg.ParamL);
    RM_FEATURE_SAMPLE_RATE: RMSetSampleRate(Msg, Msg.ParamL);
  end;
end;

procedure TRadioModule.RMReport(const Msg: TRadioMessage; var Ret: Integer);
begin
end;

procedure TRadioModule.RMTimer(const Msg: TRadioMessage; var Ret: Integer);
begin
end;

function TRadioModule.RMSetFrequency(const Msg: TRadioMessage;
  const Freq: Cardinal): Integer;
begin
  Broadcast(Msg);
  Result := 0;
end;

function TRadioModule.RMSetBandwidth(const Msg: TRadioMessage;
  const Bandwidth: Cardinal): Integer;
begin
  Result := 0;
end;

function TRadioModule.RMSetSampleRate(const Msg: TRadioMessage;
  const Rate: Cardinal): Integer;
begin
  Broadcast(Msg);
  Result := 0;
end;

function TRadioModule.RMPhaseAdjust(const Msg: TRadioMessage;
  const Rate: Cardinal): Integer;
begin
  Result := 0;
end;

procedure TRadioModule.DoReset;
begin
  MessageQueueReset;
end;

procedure TRadioModule.DoBeforeDestroy;
begin

end;

procedure TRadioModule.DoSyncDestroy;
begin

end;

procedure TRadioModule.Describe(Strs: TStrings);
begin
end;

procedure TRadioModule.ShowConnections(Graph: TGenGraph);
const
  PORT_FEATURE = 0;
  PORT_DATA    = 1;
var
  P: Pointer;
  M: TRadioModule;
begin
  for P in FDataListeners do
  begin
    M := TRadioSystem.Instance.ModuleFromId[PDataListener(P)^.M];
    if not Assigned(M) then Continue;
    Graph.AddConnection(GraphNode, M.GraphNode,
                        PDataListener(P)^.SourcePort + PORT_DATA, PDataListener(P)^.TargetPort + PORT_DATA);
  end;

  for P in FFeatureListeners do
  begin
    M := TRadioSystem.Instance.ModuleFromId[TModuleId(P)];
    if not Assigned(M) then Continue;
    Graph.AddConnection(GraphNode, M.GraphNode,
                        PORT_FEATURE, PORT_FEATURE).PenStyle := psDash;
  end;
end;

constructor TRadioModule.Create(RunQueue: TRadioRunQueue);
begin
  inherited;
  FHasConfig := True;
  FDataListeners := TList.Create;
  FFeatureListeners := TList.Create;
  FDefOutput := TRadioDataStream.Create(Self, 'output', 1024 * 5);
  FDescStr := TStringList.Create;
  FIcon := LoadDefIconRes;
end;

destructor TRadioModule.Destroy;
begin
  if not FDestroying then raise Exception.Create('Destroy must be done by message: RM_DESTROY');
  TThread.Synchronize(nil, @DoSyncDestroy);
  TRadioLogger.Report(llWarn, 'free %s, cpu time %.f', [FName, FCPUTime * MSecsPerDay]);
  FDescStr.Free;
  ClearDataListeners;
  FDefOutput.SafeFree;
  FDataListeners.Free;
  FFeatureListeners.Free;
  inherited Destroy;
end;

procedure TRadioModule.GraphInvalidate;
begin
  FInvalidated := True;
end;

procedure TRadioModule.PostMessage(const Id: Integer; const ParamH,
  ParamL: PtrUInt);
var
  M: TRadioMessage;
begin
  M.Id := Id;
  M.ParamH := ParamH;
  M.ParamL := ParamL;
  PostMessage(M);
end;

procedure TRadioModule.DoConfigure;
begin

end;

procedure TRadioModule.DoShowGUI;
begin

end;

procedure TRadioModule.AddDataListener(Listener: TModuleId; const SourcePort,
  TargetPort: Integer);
var
  P: PDataListener;
begin
  if FindDataListener(Listener) < 0 then
  begin
    New(P);
    P^.M := Listener;
    P^.SourcePort := SourcePort;
    P^.TargetPort := TargetPort;
    FDataListeners.Add(P);
  end;
end;

procedure TRadioModule.AddFeatureListener(Listener: TModuleId);
begin
  with FFeatureListeners do
    if IndexOf(Pointer(Listener)) < 0 then Add(Pointer(Listener));
end;

procedure TRadioModule.RemoveDataListener(Listener: TModuleId);
var
  I: Integer;
  P: PDataListener;
begin
  I := FindDataListener(Listener);
  if I >= 0 then
  begin
    P := PDataListener(FDataListeners[I]);
    FDataListeners.Delete(I);
    Dispose(P);
  end;
end;

procedure TRadioModule.RemoveFeatureListener(Listener: TModuleId);
begin
  FFeatureListeners.Remove(Pointer(Listener));
end;

procedure TRadioModule.ClearDataListeners;
var
  P: Pointer;
begin
  for P in FDataListeners do Dispose(PDataListener(P));
  FDataListeners.Clear;
end;

procedure TRadioModule.ClearFeatureListeners;
begin
  FFeatureListeners.Clear;
end;

procedure TRadioModule.ReceiveData(const P: PComplex; const Len: Integer);
begin

end;

procedure TRadioModule.ReceiveData(const Port: Integer; const P: PComplex;
  const Len: Integer);
begin

end;

initialization

  InitCriticalSection(RadioGlobalCS);

finalization

  DoneCriticalsection(RadioGlobalCS);

end.

