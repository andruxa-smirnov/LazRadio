unit gen_graph;

{$mode objfpc}{$H+}

// This is a generic directed graph class:

interface

uses
  Classes, SysUtils, Graphics, ExtCtrls, Utils, Math;

type

  IGenDrawable = interface
    procedure Measure(out Extent: TPoint);
    procedure Draw(ACanvas: TCanvas; ARect: TRect);
    procedure MouseClick(const Pt: TPoint; Shifts: TShiftState);
  end;

  TGenGraph = class;
  TGenEntityNode = class;

  TGenEntityPortType = (epIn, epOut);

  TGenEntityPortRef = record
    Entity: TGenEntityNode;
    Index: Integer;
  end;

  { TGenEntity }

  TGenEntity = class
  private
    FInValidated: Boolean;
  protected
    FExtent: TPoint;
    function GetBox: TRect; virtual;
  public
    procedure Invalidate;

    procedure Measure; virtual;
    procedure Draw(ACanvas: TCanvas); virtual;
    function  IsPtOn(const Pt: TPoint): Boolean; virtual;
    procedure MouseClick(const Pt: TPoint; Shifts: TShiftState); virtual;

    procedure Move(const OffsetX, OffsetY: Integer); virtual;

    property Extent: TPoint read FExtent;
    property Box: TRect read GetBox;
    property Invalidated: Boolean read FInValidated;
  end;

  { TGenEntityNode }

  TGenEntityNode = class(TGenEntity)
  private
    FDegIn: Integer;
    FDegOut: Integer;
    FDrawable: IGenDrawable;
    //FDrawRect: TRect;
    FLevel: Integer;
    //FNodeRect: TRect;
    FInPorts: array of string;
    FOutPorts: array of string;

    procedure DrawPorts(ACanvas: TCanvas);
  protected
    function GetBox: TRect; override;
  public
    Pos: TPoint;
  public
    constructor Create;

    procedure Measure; override;
    procedure Draw(ACanvas: TCanvas); override;
    function  IsPtOn(const Pt: TPoint): Boolean; override;
    procedure MouseClick(const Pt: TPoint; Shifts: TShiftState); override;

    procedure SetPortsNum(const T: TGenEntityPortType; const N: Integer);
    procedure SetPortsNumAtLeast(const T: TGenEntityPortType; const N: Integer);

    procedure Move(const OffsetX, OffsetY: Integer); override;

    function  GetPortConnectPos(T: TGenEntityPortType; Index: Integer): TPoint;
    property Drawable: IGenDrawable read FDrawable write FDrawable;

    property Level: Integer read FLevel write FLevel;
    property DegIn: Integer read FDegIn write FDegIn;
    property DegOut: Integer read FDegOut write FDegOut;
  end;

  { TGenEntityConnection }

  TGenEntityConnection = class(TGenEntity)
  private
    FCtrlPts: array of TPoint;
    FFromPort: TGenEntityPortRef;
    FToPort: TGenEntityPortRef;
    function GetCtrlPoints(const Index: Integer): TPoint;
    function GetEndPt: TPoint;
    function GetStartPt: TPoint;
    procedure SetCtrlPoints(const Index: Integer; AValue: TPoint);
  protected
    function GetBox: TRect; override;
  public
    constructor Create;

    procedure SetCtrlPointsNumber(const N: Integer);

    procedure Measure; override;
    procedure Draw(ACanvas: TCanvas); override;

    property CtrlPoints[const Index: Integer]: TPoint read GetCtrlPoints write SetCtrlPoints;
    property FromPt: TPoint read GetStartPt;
    property ToPt: TPoint read GetEndPt;

    procedure Move(const OffsetX, OffsetY: Integer); override;

    property FromPort: TGenEntityPortRef read FFromPort write FFromPort;
    property ToPort: TGenEntityPortRef read FToPort write FToPort;
  end;

  { TGenGraph }

  TGenGraph = class
  private
    FDBuffer: TDoubleBuffer;
    FEntities: TList;
    FConns: TList;
    FUpdateCount: Integer;
    function GetPaintBox: TPaintBox;
    procedure SetPaintBox(AValue: TPaintBox);
    function  FindConnection(AFrom, ATo: TGenEntityNode; const AFromPort,
      AToPort: Integer): TGenEntityConnection;
  protected
    procedure Layout;
    procedure Route;
  public
    procedure FullRender;
    procedure PartialRender;

    procedure RemoveEntity(AEntity: TGenEntityNode);
    procedure AddEntity(AEntity: TGenEntityNode);
    procedure AddConnection(AFrom, ATo: TGenEntityNode; const AFromPort, AToPort: Integer);
    procedure RemoveConnecttion(AFrom, ATo: TGenEntityNode; const AFromPort, AToPort: Integer);
    procedure Clear;

    procedure BeginUpdate;
    procedure EndUpdate;

    constructor Create;
    destructor Destroy; override;

    property PaintBox: TPaintBox read GetPaintBox write SetPaintBox;
  end;

implementation

const
  PORT_MARK_SIZE   = 6;
  PORT_MARK_MARGIN = 2 * PORT_MARK_SIZE;

function MergeRect(const R1, R2: TRect): TRect;
begin
  with Result do
  begin
    Left := Min(R1.Left, R2.Left);
    Right := Max(R1.Right, R2.Right);
    Top   := Min(R1.Top, R2.Top);
    Bottom := Max(R1.Bottom, R2.Bottom);
  end;
end;

{ TGenEntityNode }

procedure TGenEntityNode.DrawPorts(ACanvas: TCanvas);
var
  R: TRect;
  DrawRect: TRect;
  procedure DrawIt(N: Integer);
  var
    I: Integer;
  begin
    for I := 0 to N - 1 do
    begin
      ACanvas.Rectangle(R);
      Inc(R.Top, PORT_MARK_MARGIN + PORT_MARK_SIZE);
      Inc(R.Bottom, PORT_MARK_MARGIN + PORT_MARK_SIZE);
    end;
  end;

begin
  DrawRect := Box;
  with R do
  begin
    Left := DrawRect.Left;
    Right := Left + PORT_MARK_SIZE;
    Top  := DrawRect.Top + PORT_MARK_MARGIN div 2;
    Bottom := Top + PORT_MARK_SIZE;
  end;
  with ACanvas do
  begin
    Pen.Width := 1;
    Pen.Color := clBlack;
    Pen.Style := psSolid;
    Brush.Color := TColor($ffaaaa);
    Brush.Style := bsSolid;
  end;
  DrawIt(High(FInPorts) + 1);
  ACanvas.Brush.Color := TColor($aaaaff);
  with R do
  begin
    Left := DrawRect.Right - PORT_MARK_SIZE;
    Right := DrawRect.Right;
    Top  := DrawRect.Top + PORT_MARK_MARGIN div 2;
    Bottom := Top + PORT_MARK_SIZE;
  end;
  DrawIt(High(FOutPorts) + 1);
end;

function TGenEntityNode.GetBox: TRect;
begin
  with Result do
  begin
    Left := Pos.x;
    Right := Left + Extent.x;
    Top   := Pos.y;
    Bottom := Top + Extent.y;
  end;
end;

constructor TGenEntityNode.Create;
begin
  inherited;
  //FInPorts[0] := 'def';
end;

procedure TGenEntityNode.Measure;
var
  I: Integer;
begin
  I := Max(High(FInPorts), High(FOutPorts)) + 1;
  if I >= 1 then I := I * (PORT_MARK_MARGIN + PORT_MARK_SIZE);

  if Assigned(FDrawable) then FDrawable.Measure(FExtent);
  FExtent.x := FExtent.x + 2 * PORT_MARK_SIZE;
  FExtent.y := Max(FExtent.y, I);
end;

procedure TGenEntityNode.Draw(ACanvas: TCanvas);
var
  DrawRect: TRect;
  NodeRect: TRect;
begin
  inherited;
  DrawRect := Box;

  NodeRect := DrawRect;
  with NodeRect do
  begin
    Left  := Left + PORT_MARK_SIZE;
    Right := Right - PORT_MARK_SIZE;
  end;

  with ACanvas do
  begin
    Brush.Color := clWhite;
    FillRect(DrawRect);
  end;
  if not Assigned(FDrawable) then Exit;
  FDrawable.Draw(ACanvas, NodeRect);
  DrawPorts(ACanvas);
end;

function TGenEntityNode.IsPtOn(const Pt: TPoint): Boolean;
begin
  Result := InRange(Pt.x, Pos.x, Pos.x + FExtent.x)
         and InRange(Pt.y, Pos.y, Pos.y + FExtent.y);
end;

procedure TGenEntityNode.MouseClick(const Pt: TPoint; Shifts: TShiftState);
begin
  if Assigned(FDrawable) then FDrawable.MouseClick(Pt, Shifts);
end;

procedure TGenEntityNode.SetPortsNum(const T: TGenEntityPortType;
  const N: Integer);
begin
  case T of
    epIn: SetLength(FInPorts, N);
    epOut: SetLength(FOutPorts, N);
  end;
end;

procedure TGenEntityNode.SetPortsNumAtLeast(const T: TGenEntityPortType;
  const N: Integer);
begin
  case T of
    epIn : if High(FInPorts) < N -1  then SetLength(FInPorts, N);
    epOut: if High(FOutPorts) < N -1 then SetLength(FOutPorts, N);
  end;
end;

procedure TGenEntityNode.Move(const OffsetX, OffsetY: Integer);
begin
  Pos.x := Pos.x + OffsetX;
  Pos.y := Pos.y + OffsetY;
end;

function TGenEntityNode.GetPortConnectPos(T: TGenEntityPortType; Index: Integer
  ): TPoint;
begin
  case T of
    epIn:
      begin
        if InRange(Index, 0, High(FInPorts)) then
          Result.y := Pos.y + (PORT_MARK_MARGIN div 2) + (PORT_MARK_MARGIN + PORT_MARK_SIZE) * Index
                   + PORT_MARK_SIZE div 2
        else
          Result.y := Pos.y;
        Result.x := Pos.x;
      end;
    epOut:
      begin
        if InRange(Index, 0, High(FOutPorts)) then
          Result.y := Pos.y + (PORT_MARK_MARGIN div 2) + (PORT_MARK_MARGIN + PORT_MARK_SIZE) * Index
                   + PORT_MARK_SIZE div 2
        else
          Result.y := Pos.y;
        Result.x := Pos.x + FExtent.x
      end;
  end;
end;

{ TGenEntityConnection }

function TGenEntityConnection.GetCtrlPoints(const Index: Integer): TPoint;
begin
  Result.x := 0; Result.y := 0;
  if InRange(Index, 0, High(FCtrlPts) - 1) then
    Result := FCtrlPts[Index + 1];
end;

function TGenEntityConnection.GetEndPt: TPoint;
begin
  Result := FToPort.Entity.GetPortConnectPos(epIn, FToPort.Index);
end;

function TGenEntityConnection.GetStartPt: TPoint;
begin
  Result := FFromPort.Entity.GetPortConnectPos(epOut, FFromPort.Index);
end;

procedure TGenEntityConnection.SetCtrlPoints(const Index: Integer; AValue: TPoint);
begin
  if InRange(Index, 0, High(FCtrlPts) - 1) then
    FCtrlPts[Index + 1] := AValue;
end;

function TGenEntityConnection.GetBox: TRect;
begin
  with Result do
  begin
    Left := Min(FromPt.x, ToPt.x);
    Right := Max(FromPt.x, ToPt.x);
    Top   := Min(FromPt.y, ToPt.y);
    Bottom := Max(FromPt.y, ToPt.y);
  end;
end;

constructor TGenEntityConnection.Create;
begin
  inherited;
  SetLength(FCtrlPts, 4);
end;

procedure TGenEntityConnection.SetCtrlPointsNumber(const N: Integer);
var
  T: TPoint;
begin
  T := ToPt;
  SetLength(FCtrlPts, N + 2);
end;

procedure TGenEntityConnection.Measure;
var
  S, E: TPoint;
begin
  S := FromPt;
  E := ToPt;
  FExtent.x := Max(S.x, E.x) - Min(S.x, E.x);
  FExtent.y := Max(S.y, E.y) - Min(S.y, E.y);
end;

procedure TGenEntityConnection.Draw(ACanvas: TCanvas);
begin
  inherited;
  FCtrlPts[0] := FromPt;
  FCtrlPts[High(FCtrlPts)] := ToPt;
  with ACanvas do
  begin
    Pen.Color := clBlack;
    Pen.Style := psSolid;
    Pen.Width := 1;
    //PolyBezier(FCtrlPts);
    Line(FCtrlPts[0], FCtrlPts[High(FCtrlPts)]);
  end;
end;

procedure TGenEntityConnection.Move(const OffsetX, OffsetY: Integer);
var
  I: Integer;
begin
  for I := 1 to High(FCtrlPts) - 1 do
  begin
    FCtrlPts[I].x := FCtrlPts[I].x + OffsetX;
    FCtrlPts[I].y := FCtrlPts[I].y + OffsetY;
  end;
end;

{ TGenEntity }

function TGenEntity.GetBox: TRect;
begin
  with Result do
  begin
    Left := 0;
    Right := 10;
    Top := 0;
    Bottom := 10;
  end;
end;

procedure TGenEntity.Invalidate;
begin
  FInValidated := True;
end;

procedure TGenEntity.Measure;
begin

end;

procedure TGenEntity.Draw(ACanvas: TCanvas);
begin
  FInValidated := False;
end;

function TGenEntity.IsPtOn(const Pt: TPoint): Boolean;
begin
  Result := False;
end;

procedure TGenEntity.MouseClick(const Pt: TPoint; Shifts: TShiftState);
begin

end;

procedure TGenEntity.Move(const OffsetX, OffsetY: Integer);
begin

end;

{ TGenGraph }

function TGenGraph.GetPaintBox: TPaintBox;
begin
  Result := FDBuffer.PaintBox;
end;

procedure TGenGraph.SetPaintBox(AValue: TPaintBox);
begin
  FDBuffer.PaintBox := AValue;
end;

function TGenGraph.FindConnection(AFrom, ATo: TGenEntityNode; const AFromPort,
  AToPort: Integer): TGenEntityConnection;
var
  P: Pointer;
  C: TGenEntityConnection;
begin
  Result := nil;
  for P in FConns do
  begin
    C := TGenEntityConnection(P);
    if (C.FromPort.Entity = AFrom) and (C.FromPort.Index = AFromPort)
      and (C.ToPort.Entity = AFrom) and (C.ToPort.Index = AFromPort) then
    begin
      Result := C;
      Break;
    end;
  end;
end;

function GenEntityCompare(Item1, Item2: TGenEntityNode): Integer;
begin
  Result := Item1.Level - Item2.Level;
  if Result = 0 then
    Result := (Item1.DegIn + Item1.DegOut) - (Item2.DegIn + Item2.DegOut);
end;

procedure TGenGraph.Layout;
const
  V_MARGIN = 50;
  H_MARGIN = 100;
var
  P: Pointer;
  C: Pointer;
  Dirty: Boolean;
  L: TList;
  I: Integer;
  J: Integer;
  K: Integer;
  V: Integer;
  S: array of TRect;
  M: Integer;
begin
  if FEntities.Count < 1 then Exit;

  for P in FEntities do
  begin
    TGenEntityNode(P).Pos.x := -1;
    TGenEntityNode(P).DegIn := 0;
    TGenEntityNode(P).DegOut := 0;
  end;

  for C in FConns do
    with TGenEntityConnection(C) do
    begin
      ToPort.Entity.DegIn := ToPort.Entity.DegIn + 1;
      FromPort.Entity.DegOut := FromPort.Entity.DegOut + 1;
    end;

  for P in FEntities do
  begin
    with TGenEntityNode(P) do
    begin
      Level := IfThen(DegIn = 0, 0, MaxInt);
    end;
  end;

  repeat
    Dirty := False;
    for C in FConns do
    begin
      with TGenEntityConnection(C) do
      begin
        if FromPort.Entity.Level = MaxInt then Continue;
        if ToPort.Entity.Level > FromPort.Entity.Level + 1 then
        begin
          ToPort.Entity.Level := FromPort.Entity.Level + 1;
          Dirty := True;
          Break;
        end;
      end;
    end;
  until not Dirty;

  FEntities.Sort(TListSortCompare(@GenEntityCompare));

  // level should be continous
  I := 0;
  for I := 0 to FEntities.Count - 1 do
  begin
    if TGenEntityNode(FEntities[I]).Level - V > 1 then
    begin
      K := TGenEntityNode(FEntities[I]).Level - V - 1;
      for J := I to FEntities.Count - 1 do
        TGenEntityNode(FEntities[J]).Level := TGenEntityNode(FEntities[J]).Level - K;
    end;
    V := TGenEntityNode(FEntities[I]).Level;
  end;

  // size of each level
  SetLength(S, TGenEntityNode(FEntities[FEntities.Count - 1]).Level + 1);
  for P in FEntities do
  begin
    with TGenEntityNode(P) do
    begin
      S[Level].Right  := Max(S[Level].Right, Extent.x);
      S[Level].Bottom := S[Level].Bottom + V_MARGIN + Extent.y;
    end;
  end;

  // get max v-size
  K := 0;
  for I := 0 to High(S) do
    K := Max(K, S[I].Bottom);

  // Left
  J := H_MARGIN div 2;
  for I := 0 to High(S) do
  begin
    with S[I] do
    begin
      Left := J;
      Top := (K - Bottom) div 2;
      Inc(J, Right + H_MARGIN);
    end;
  end;

  // layout
  for P in FEntities do
  begin
    with TGenEntityNode(P) do
    begin
      Pos.x := S[Level].Left + (S[Level].Right - Extent.x) div 2;
      Pos.y := S[Level].Top;
      S[Level].Top := S[Level].Top + Extent.y + V_MARGIN;
    end;
  end;
end;

procedure TGenGraph.Route;
begin

end;

procedure TGenGraph.FullRender;
const
  Margin_H = 100;
  Margin_V = 80;
var
  P: Pointer;
  R: TRect = (Left: 0; Top: 0; Right: 0; Bottom: 0);
begin
  if FUpdateCount > 0 then Exit;

  for P in FEntities do TGenEntityNode(P).Measure;
  Layout;
  Route;
  for P in FConns do TGenEntityConnection(P).Measure;

  for P in FEntities do
    R := MergeRect(R, TGenEntity(P).Box);
  for P in FConns do
    R := MergeRect(R, TGenEntity(P).Box);
  Inc(R.Right, Margin_H * 2);
  Inc(R.Bottom, Margin_V * 2);
  FDBuffer.PaintBox.Width := R.Right;
  FDBuffer.PaintBox.Height := R.Bottom;
  FDBuffer.SetSize(R.Right, R.Bottom);

  for P in FEntities do
    TGenEntity(P).Move(Margin_H, Margin_V);
  for P in FConns do
    TGenEntity(P).Move(Margin_H, Margin_V);

  // draw background
  with FDBuffer.PaintBuffer.Canvas do
  begin
    Brush.Color := clWhite;
    FillRect(R);
  end;
  for P in FEntities do TGenEntity(P).Draw(FDBuffer.PaintBuffer.Canvas);
  for P in FConns do TGenEntity(P).Draw(FDBuffer.PaintBuffer.Canvas);
end;

procedure TGenGraph.PartialRender;
var
  P: Pointer;
begin
  for P in FEntities do
  begin
    with TGenEntityNode(P) do
    begin
      if Invalidated then Draw(FDBuffer.DrawBuffer.Canvas);
    end;
  end;
  FDBuffer.Paint;
end;

procedure TGenGraph.RemoveEntity(AEntity: TGenEntityNode);
begin
  FEntities.Remove(AEntity);
end;

procedure TGenGraph.AddEntity(AEntity: TGenEntityNode);
begin
  FEntities.Add(AEntity);
end;

procedure TGenGraph.Clear;
var
  P: Pointer;
begin
  for P in FConns    do TGenEntityConnection(P).Free;
  for P in FEntities do TGenEntityNode(P).Free;
  FConns.Clear;
  FEntities.Clear;
end;

procedure TGenGraph.AddConnection(AFrom, ATo: TGenEntityNode; const AFromPort,
  AToPort: Integer);
var
  C: TGenEntityConnection;
begin
  if not Assigned(AFrom) then raise Exception.Create('not Assigned(AFrom)');
  if not Assigned(ATo) then raise Exception.Create('not Assigned(ATo)');
  if AFrom = ATo then raise Exception.Create('AFrom = ATo');

  AFrom.SetPortsNumAtLeast(epOut, AFromPort + 1);
  ATo.SetPortsNumAtLeast(epIn, AToPort + 1);
  C := TGenEntityConnection.Create;
  with C.FromPort do
  begin
    Entity := AFrom;
    Index := AFromPort;
  end;
  with C.ToPort do
  begin
    Entity := ATo;
    Index := AToPort;
  end;
  FConns.Add(C);
end;

procedure TGenGraph.RemoveConnecttion(AFrom, ATo: TGenEntityNode;
  const AFromPort, AToPort: Integer);
var
  C: TGenEntityConnection;
begin
  C := FindConnection(AFrom, ATo, AFromPort, AToPort);
  if Assigned(C) then FConns.Remove(C);
end;

procedure TGenGraph.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TGenGraph.EndUpdate;
begin
  Dec(FUpdateCount);
  if FUpdateCount <= 0 then FullRender;
end;

constructor TGenGraph.Create;
begin
  inherited;
  FDBuffer := TDoubleBuffer.Create;
  FDBuffer.PaintBuffer.Canvas.AntialiasingMode := amOn;
  FDBuffer.DrawBuffer.Canvas.AntialiasingMode := amOn;
  FEntities := TList.Create;
  FConns    := TList.Create;
end;

destructor TGenGraph.Destroy;
begin
  Clear;
  FDBuffer.Free;
  inherited Destroy;
end;

end.

