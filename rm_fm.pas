unit rm_fm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UComplex, RadioModule, RadioSystem, Math, SignalBasic,
  radiomessage;

type

  { TRadioFreqDiscriminator }

  TRadioFreqDiscriminator = class(TRadioModule)
  private
    FRegulator: TStreamRegulator;
    FLastValue: Complex;
    FBandIndex: Integer;
    FCarrierFreq: Cardinal;
    FSampleRate: Cardinal;
    procedure ReceiveRegulatedData(const P: PComplex; const Len: Integer);
  protected
    function RMSetFrequency(const Msg: TRadioMessage; const Freq: Cardinal): Integer; override;
    function RMSetSampleRate(const Msg: TRadioMessage; const Rate: Cardinal): Integer; override;
  public
    constructor Create(RunQueue: TRadioRunQueue); override;
    destructor Destroy; override;

    procedure ReceiveData(const P: PComplex; const Len: Integer); override;
  end;

implementation

{ TRadioFreqDiscriminator }

// Reference: http://www.digitalsignallabs.com/Digradio.pdf
// y[n] = A/2 exp(-j (2 pi f0 n Ts + f_delta integrate[x(tao), 0, n Ts]))
// y[n] * conj[y[n - 1]] = A^2 / 4 exp(-j (2 pi f0 Ts + f_delta Ts x(nTs)))
// arctan2 is in (-pi, pi)
procedure TRadioFreqDiscriminator.ReceiveRegulatedData(const P: PComplex;
  const Len: Integer);
var
  I: Integer;
  J: Integer;
  O: PComplex;
  T: Complex;
  X: Complex;
  F: Double;
begin
  if FSampleRate = 0 then Exit;
  F := Pi;  // in [0, Pi]
  O := Alloc(DefOutput, I);
  if not Assigned(O) then
  begin
    TRadioLogger.Report(llWarn, 'TRadioFreqDiscriminator.ReceiveRegulatedData: data lost');
    Exit;
  end;
  T := FLastValue;
  for J := 0 to Len - 1 do
  begin
    X := P[J] * cong(T);
    T := P[J];
    O[J].im := 0;
    if X.re <> 0 then
      O[J].re := arctan2(X.im, X.re) + F
    else
      O[J].re := IfThen(X.im > 0, Pi / 2, -Pi / 2) + F;
  end;
  CancelDC(O, Len);
  FLastValue := T;
  DefOutput.Broadcast(I, FDataListeners);
end;

function TRadioFreqDiscriminator.RMSetFrequency(const Msg: TRadioMessage;
  const Freq: Cardinal): Integer;
begin
  Result := 0;
end;

function TRadioFreqDiscriminator.RMSetSampleRate(const Msg: TRadioMessage;
  const Rate: Cardinal): Integer;
begin
 // if FSampleRate = Rate then Exit;
  FSampleRate := Rate;
  Result := inherited;
  Broadcast(RM_SET_FEATURE, RM_FEATURE_FREQ, 0);
end;

constructor TRadioFreqDiscriminator.Create(RunQueue: TRadioRunQueue);
begin
  inherited Create(RunQueue);
  FHasConfig := False;
  DefOutput.BufferSize := 50 * 1024;
  FRegulator := TStreamRegulator.Create;
  FRegulator.Size := DefOutput.BufferSize;
  FRegulator.OnRegulatedData := @ReceiveRegulatedData;
end;

destructor TRadioFreqDiscriminator.Destroy;
begin
  FRegulator.Free;
  inherited Destroy;
end;

procedure TRadioFreqDiscriminator.ReceiveData(const P: PComplex; const Len: Integer);
begin
  FRegulator.ReceiveData(P, Len);
end;

initialization

  RegisterModule(TRadioModuleClass(TRadioFreqDiscriminator.ClassType));

end.

