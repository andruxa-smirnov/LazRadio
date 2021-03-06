unit SignalBasic;

{$mode objfpc}{$H+}

{$define _DEBUG}

interface

uses
  Classes, SysUtils, UComplex;

type

  TWindowFunction = (wfRect, wfGaussian, wfHamming, wfHann, wfTriangular, wfBartlett,
                     wfBlackman, wfKaiser, wfBartlettHann);

  TFilterType = (ftLPF, ftBPF, ftBSF, ftHPF);

  TIIRFilter = record
    Zx, Zy: array of Complex;
    A: array of Double;   // feedback
    B: array of Double;   // feedforward
  end;

procedure SetIIROrders(var AFilter: TIIRFilter; XDelay, YDelay: Integer);
procedure IIRFilter(var AFilter: TIIRFilter; X, Y: PComplex; const N: Integer); overload;
procedure IIRFilter(var AFilter: TIIRFilter; IO: PComplex; const N: Integer);
procedure IIRFilter(var AFilter: TIIRFilter; IO: PDouble; const N: Integer);

procedure IIRFilterReal(var AFilter: TIIRFilter; IO: PComplex; const N: Integer); overload;
procedure IIRFilterReal(var AFilter: TIIRFilter; X: PComplex; Y: PDouble; const N: Integer);
procedure IIRFilterReal(var AFilter: TIIRFilter; X: PComplex; Y: PComplex; const N: Integer);

procedure IIRFilterReInIm(var AFilter: TIIRFilter; X: PComplex; Y: PComplex; const N: Integer);

// Output.re = amplitude
// Output.im = arg
procedure ModArg(Input: PComplex; Output: PComplex; const N: Integer); overload;
procedure ModArg(IO: PComplex; const N: Integer);

// Output.re = power
// Output.im = arg
procedure PowArg(Input: PComplex; Output: PComplex; const N: Integer); overload;
procedure PowArg(IO: PComplex; const N: Integer);

// Output.re = power
procedure Pow(Input: PComplex; Output: PComplex; const N: Integer); overload;
procedure Pow(IO: PComplex; const N: Integer);

procedure SpectrumPower(Spectrum: PComplex; P: PDouble; const N: Integer);
procedure SpectrumPowArg(Spectrum: PComplex; P: PComplex; const N: Integer);

procedure CreateWindowFunction(P: PDouble; const N: Integer; const Func: TWindowFunction;
  Param: Double = -1);

function BesselI0(const Z: Double): Double;

procedure Xpolate(Source: PDouble; Target: PDouble; const SourceLen, TargetLen: Integer); overload;
procedure Xpolate(Source: PComplex; Target: PComplex; const SourceLen, TargetLen: Integer);

procedure CancelDC(Signal: PComplex; const N: Integer);

function FormatFreq(F: Integer): string;

procedure Reverse(X: PComplex; const Len: Integer);
procedure Conjugate(X: PComplex; const Len: Integer);

procedure FIRDesign(Coef: PDouble; const N: Integer;
  const AType: TFilterType;
  const OmegaC: Double; const Bandwidth: Double;
  const Wf: TWindowFunction; const WfParam: Double);

{
 T = symbol rate
 Beta: roll-off factor

 H(f) = T, if |f| <= (1 - beta) / (2T)
      = (T/2) [1 + Cos(pi T / beta * (|f| - (1-beta)/(2T)))], (1-beta)/(2T) < |f| <= (1+beta)/(2T)
      = 0, else

if beta -> 0,
 H(f) -> rect(f T)

if beta = 1,
 H(f) = T/2 (1 + Cos(pi f T)), if |f| <= 1/T
      = 0, else
}
procedure RaisedCosinFilterDesign(Coef: PDouble; const N: Integer;
  const SampleRate: Integer; const Beta: Double; const T: Double);

type
  TShelvingFilterType = (sfBassShelf, sfTrebleShelf);

{
% Ported from: http://www.dsprelated.com/showcode/170.php
%
% Derive coefficients for a shelving filter with a given amplitude and
% cutoff frequency.  All coefficients are calculated as described in
% Zolzer's DAFX book (p. 50 -55).
%
% Usage:     [B,A] = shelving(G, Fc, Fs, Q, type);
%
%            G is the logrithmic gain (in dB)
%            Fc is the center frequency
%            Fs is the sampling rate
%            Q adjusts the slope be replacing the sqrt(2) term
%            type is a character string defining filter type
%                 Choices are: 'Base_Shelf' or 'Treble_Shelf'
}
procedure ShelvingFilterDesign(G: Double; Fc: Integer; Fs: Cardinal; Q: Double;
                         T: TShelvingFilterType;
                         out A, B: array of Double);
{
Ref: http://www.musicdsp.org/files/Audio-EQ-Cookbook.txt
 Fs (the sampling frequency)
 f0 ("wherever it's happenin', man."  Center Frequency or
        Corner Frequency, or shelf midpoint frequency, depending
        on which filter type.  The "significant frequency".)
 Q (the EE kind of definition, except for peakingEQ in which A*Q is
      the classic EE Q.  That adjustment in definition was made so that
      a boost of N dB followed by a cut of N dB for identical Q and
      f0/Fs results in a precisely flat unity gain filter or "wire".)
   Q = f0 / (f2 - f1) = f0 / Bw.
}
procedure AudioEQFilterDesign(F0: Double; Fs: Cardinal; Q: Double;
                         T: TFilterType;
                         out A, B: array of Double);

{
reference: multirate_alg from http://www.dspguru.com
Description:

    decim - "decimates" a signal by changing reducing its sampling rate by an
             integral factor via FIR filtering.

Inputs:

    FactorM:
        the decimation factor (must be >= 1)

    H:
        array of coefficients for the resampling filter.
        sampling rate = input rate.

    InLen:
        the number of input samples

    Input:
        pointer to the input samples

Input/Outputs:

    Z:
        the delay line array (which must have  H_size elements)

Outputs:

    Output:
        pointer to the output sample array.

    OutLen:
        pointer to the number of output samples
}
procedure Decimate(const FactorM: Integer; H: array of Double;
                   var Z: array of Complex;
                   Input: PComplex; InLen: Integer;
                   Output: PComplex; out OutLen: Integer);

{
Description:

    interp - "interpolates" a signal by increasing its sampling rate by an
             integral factor via FIR filtering.

Inputs:

    FactorL:
        the interpolation factor (must be >= 1)

    H:
        the array of coefficients for the resampling filter.  (The
        number of total taps in H is FactorL * num_taps_per_phase, so be sure
        to design your filter using a number of taps which is divisible by
        FactorL.), sampling rate = FactorL * input rate.

    InLen:
        the number of input samples

    Input:
        pointer to the input samples

Input/Outputs:

    Z:
        the delay line array (which must have num_taps_per_phase
        elements)

Outputs:

    Output:
        pointer to the output sample array.

    OutLen:
        pointer to the number of output samples

}
procedure Interpolate(const FactorL: Integer; H: array of Double;
                   var Z: array of Complex;
                   Input: PComplex; InLen: Integer;
                   Output: PComplex; out OutLen: Integer);

{
Description:

    interp - "interpolates" a signal by increasing its sampling rate by an
             integral factor via FIR filtering.

Inputs:

    IntepL:
        the interpolation factor (must be >= 1)

    DecimM:
        the decimation factor (must be >= 1)

    H:
        the array of coefficients for the resampling filter.  (The
        number of total taps in H is FactorL * num_taps_per_phase, so be sure
        to design your filter using a number of taps which is divisible by
        FactorL.), sampling rate = FactorL * input rate.

    InLen:
        the number of input samples

    Input:
        pointer to the input samples

Input/Outputs:

    Z:
        the delay line array (which must have num_taps_per_phase
        elements)

Outputs:

    Output:
        pointer to the output sample array.

    OutLen:
        pointer to the number of output samples

}
procedure Resample(const IntepL, DecimM: Integer; H: array of Double;
                   var Z: array of Complex; var CurPhase: Integer;
                   Input: PComplex; InLen: Integer;
                   Output: PComplex; out OutLen: Integer);

function ToString(Input: PComplex; const N: Integer): string;

procedure DumpData(const P: PComplex; const Len: Integer; const Fn: string); overload;
procedure DumpData(const P: PDouble; const Len: Integer; const Fn: string); overload;

var
  gWindowFunctionNames: array [TWindowFunction] of string =
    ('Rect', 'Gaussian', 'Hamming', 'Hann', 'Triangular', 'Bartlett', 'Blackman', 'Kaiser', 'BartlettHann');

implementation

uses
  Math;

function Sinc(const X: Double): Double;
begin
  if Abs(X) > 1e-10 then
    Result := Sin(X) / X
  else
    Result := 1.0;
end;

// naive, not applicable for real-time
function BesselI0(const Z: Double): Double;
var
  A, B, T: Double;
  I: Integer = 1;
begin
  A := 1;
  B := 1;
  T := 1;
  Result := 1;
  repeat
    A := A * Z * Z / 4;
    B := B * I;
    T := A / (B * B);
    Result := Result + T;
    Inc(I);
  until T < 1e-8;
end;

procedure Xpolate(Source: PDouble; Target: PDouble; const SourceLen,
  TargetLen: Integer);
  procedure Smooth(Source: PDouble; Target: PDouble; const SourceLen,
    TargetLen: Integer);
  var
    Ratio: Double;
    P: Double = 0;
    I: Integer;
    K: Integer;
    L: Integer = 0;
    J: Integer;
    T: Double;
  begin
    Ratio := SourceLen / TargetLen;
    for I := 0 to TargetLen - 1 do
    begin
      K := Trunc(P);
      T := Source[L];
      for J := L + 1 to K do
        T := T + Source[J];
      Target[I] := T / (K - L + 1);
      L := K + 1;
      P := P + Ratio;
    end;
  end;

  procedure Interpolate(Source: PDouble; Target: PDouble; const SourceLen,
    TargetLen: Integer);
  var
    Ratio: Double;
    P: Double = 0;
    I: Integer;
    K: Integer;
  begin
    Ratio := SourceLen / TargetLen;
    for I := 0 to TargetLen - 1 do
    begin
      K := Trunc(P);
      Target[I] := Source[K] + (P - K) * (Source[K + 1] - Source[K]);
      P := P + Ratio;
    end;
  end;
begin
  if (SourceLen < 1) or (TargetLen < 1) then Exit;
  if SourceLen = TargetLen then
  begin
    Move(Source^, Target^, SourceLen * SizeOf(Source^));
    Exit;
  end;
  if SourceLen > TargetLen then
    Smooth(Source, Target, SourceLen, TargetLen)
  else
    Interpolate(Source, Target, SourceLen, TargetLen);
end;

procedure Xpolate(Source: PComplex; Target: PComplex; const SourceLen,
  TargetLen: Integer);
  procedure Smooth(Source: PComplex; Target: PComplex; const SourceLen,
    TargetLen: Integer);
  var
    Ratio: Double;
    P: Double = 0;
    I: Integer;
    K: Integer;
    L: Integer = 0;
    J: Integer;
    T: Complex;
  begin
    Ratio := SourceLen / TargetLen;
    for I := 0 to TargetLen - 1 do
    begin
      K := Trunc(P);
      T := Source[L];
      for J := L + 1 to K do
        T := T + Source[J];
      Target[I] := T / (K - L + 1);
      L := K + 1;
      P := P + Ratio;
    end;
  end;

  procedure Interpolate(Source: PComplex; Target: PComplex; const SourceLen,
    TargetLen: Integer);
  var
    Ratio: Double;
    P: Double = 0;
    I: Integer;
    K: Integer;
  begin
    Ratio := SourceLen / TargetLen;
    for I := 0 to TargetLen - 1 do
    begin
      K := Trunc(P);
      Target[I] := Source[K] + (P - K) * (Source[K + 1] - Source[K]);
      P := P + Ratio;
    end;
  end;
begin
  if (SourceLen < 1) or (TargetLen < 1) then Exit;
  if SourceLen = TargetLen then
  begin
    Move(Source^, Target^, SourceLen * SizeOf(Source^));
    Exit;
  end;
  if SourceLen > TargetLen then
    Smooth(Source, Target, SourceLen, TargetLen)
  else
    Interpolate(Source, Target, SourceLen, TargetLen);
end;

procedure CancelDC(Signal: PComplex; const N: Integer);
var
  T: Complex = (re: 0; im: 0);
  I: Integer;
begin
  for I := 0 to N - 1 do
    T := T + Signal[I];
  T := T / N;
  for I := 0 to N - 1 do
    Signal[I] := Signal[I] - T;
end;

function FormatFreq(F: Integer): string;
const
  U: array [1..3] of string = ('K', 'M', 'G');
var
  I: Integer;
  C: Integer = 0;
begin
  Result := IntToStr(F);
  I := Length(Result);
  while (I > 0) and (Result[I] = '0') do
  begin
    Inc(C);
    Dec(I);
  end;
  I := Round(C / 3);
  if I > 0 then
  begin
    I := Min(I, High(U));
    Result := FloatToStr(F / power(1000, I)) + U[I];
  end;
end;

procedure Reverse(X: PComplex; const Len: Integer);
var
  I: Integer;
  T: Complex;
begin
  for I := 0 to Len div 2 - 1 do
  begin
    T := X[I];
    X[I] := X[Len - 1 - I];
    X[Len - 1 - I] := T;
  end;
end;

procedure Conjugate(X: PComplex; const Len: Integer);
var
  I: Integer;
begin
  for I := 0 to Len - 1 do X[I] := cong(X[I]);
end;

procedure FIRDesign(Coef: PDouble; const N: Integer; const AType: TFilterType;
  const OmegaC: Double; const Bandwidth: Double; const Wf: TWindowFunction;
  const WfParam: Double);
var
  J: Integer;
  W: array of Double;
  BL, BH: Double;
  G: Double;
  function lpf(const I: Integer): Double;
  var
    Arg: Double;
  begin
    Arg := I - (N - 1) / 2;
    Result := OmegaC * Sinc(OmegaC * Arg * Pi);
  end;
  function hpf(const I: Integer): Double;
  var
    Arg: Double;
  begin
    Arg := I - (N - 1) / 2;
    Result := Sinc(Arg * Pi) - OmegaC * Sinc(OmegaC * Arg * Pi);
  end;
  function bpf(const I: Integer; const OmegaLow, OmegaHigh: Double): Double;
  var
    Arg: Double;
  begin
    Arg := I - (N - 1) / 2;
    if Arg = 0.0 then Exit(0.0);
    Result := (Cos(OmegaLow * Arg * Pi) - Cos(OmegaHigh * Arg * Pi)) / Pi / Arg;
  end;
  function bsf(const I: Integer; const OmegaLow, OmegaHigh: Double): Double;
  var
    Arg: Double;
  begin
    Arg := I - (N - 1) / 2;
    if Arg = 0.0 then Exit(0.0);
    Result := Sinc(Arg * Pi) - OmegaHigh * Sinc(OmegaHigh * Arg * Pi)
              - OmegaLow * Sinc(OmegaLow * Arg * Pi);
  end;
begin
  BL := Max(0, OmegaC - Bandwidth / 2);
  BH := Min(1, OmegaC + Bandwidth / 2);
  case AType of
    ftLPF: for J := 0 to N - 1 do Coef[J] := lpf(J);
    ftHPF: for J := 0 to N - 1 do Coef[J] := hpf(J);
    ftBPF: for J := 0 to N - 1 do Coef[J] := bpf(J, BL, BH);
    ftBSF: for J := 0 to N - 1 do Coef[J] := bsf(J, BL, BH);
  end;

  SetLength(W, N);
  CreateWindowFunction(@W[0], N, Wf, WfParam);
  G := 0.0;
  for J := 0 to N - 1 do
  begin
    Coef[J] := Coef[J] * W[J];
    G := G + Coef[J];
  end;

  if G < 1e-6 then Exit;

  // unify filter gain
  for J := 0 to N - 1 do
    Coef[J] := Coef[J] / G;
end;

procedure RaisedCosinFilterDesign(Coef: PDouble; const N: Integer;
  const SampleRate: Integer; const Beta: Double; const T: Double);
begin
  if not odd(N) then
    raise Exception.Create('RaisedCosinFilterDesign: N must be odd');

end;

procedure ShelvingFilterDesign(G: Double; Fc: Integer; Fs: Cardinal; Q: Double;
  T: TShelvingFilterType; out A, B: array of Double);
var
  K, V0, Root2: Double;
begin
  K := Tan(Pi * Fc / Fs);
  V0 := Power(10, G / 20);
  Root2 := 1 / Q;

  A[0] := 1.0;

  // invert gain if a cut
  if V0 < 1 then V0 := 1 / V0;

  if G > 0 then
  begin
    case T of
      sfBassShelf:
        begin
          B[0] := (1 + sqrt(V0)*root2*K + V0*K**2) / (1 + root2*K + K**2);
          B[1] :=             (2 * (V0*K**2 - 1) ) / (1 + root2*K + K**2);
          B[2] := (1 - sqrt(V0)*root2*K + V0*K**2) / (1 + root2*K + K**2);
          A[1] :=                (2 * (K**2 - 1) ) / (1 + root2*K + K**2);
          A[2] :=             (1 - root2*K + K**2) / (1 + root2*K + K**2);
        end;
      sfTrebleShelf:
        begin
          B[0] := (V0 + root2*sqrt(V0)*K + K**2) / (1 + root2*K + K**2);
          B[1] :=             (2 * (K**2 - V0) ) / (1 + root2*K + K**2);
          B[2] := (V0 - root2*sqrt(V0)*K + K**2) / (1 + root2*K + K**2);
          A[1] :=              (2 * (K**2 - 1) ) / (1 + root2*K + K**2);
          A[2] :=           (1 - root2*K + K**2) / (1 + root2*K + K**2);
        end;
    end;
  end
  else if G < 0 then
  begin
    case T of
      sfBassShelf:
        begin
          B[0] :=             (1 + root2*K + K**2) / (1 + root2*sqrt(V0)*K + V0*K**2);
          B[1] :=                (2 * (K**2 - 1) ) / (1 + root2*sqrt(V0)*K + V0*K**2);
          B[2] :=             (1 - root2*K + K**2) / (1 + root2*sqrt(V0)*K + V0*K**2);
          A[1] :=             (2 * (V0*K**2 - 1) ) / (1 + root2*sqrt(V0)*K + V0*K**2);
          A[2] := (1 - root2*sqrt(V0)*K + V0*K**2) / (1 + root2*sqrt(V0)*K + V0*K**2);
        end;
      sfTrebleShelf:
        begin
          B[0] :=               (1 + root2*K + K**2) / (V0 + root2*sqrt(V0)*K + K**2);
          B[1] :=                  (2 * (K**2 - 1) ) / (V0 + root2*sqrt(V0)*K + K**2);
          B[2] :=               (1 - root2*K + K**2) / (V0 + root2*sqrt(V0)*K + K**2);
          A[1] :=             (2 * ((K**2)/V0 - 1) ) / (1 + root2/sqrt(V0)*K + (K**2)/V0);
          A[2] := (1 - root2/sqrt(V0)*K + (K**2)/V0) / (1 + root2/sqrt(V0)*K + (K**2)/V0);
        end;
    end;
  end
  else begin
    // full pass
    B[0] := V0;
    B[1] := 0;
    B[2] := 0;
    A[1] := 0;
    A[2] := 0;
  end;
end;

procedure AudioEQFilterDesign(F0: Double; Fs: Cardinal; Q: Double;
  T: TFilterType; out A, B: array of Double);
var
  w0: Double;
  alpha: Double;
begin
  if (High(A) <> 2) or (High(B) <> 2) then Exit;
  w0 := 2 * Pi * f0 / Fs;
  alpha := sin(w0)/(2*Q);
  case T of
    ftLPF:
      begin
        b[0] := ((1.0 - Cos(w0)) / 2.0);
        b[1] := ( 1.0 - Cos(w0));
        b[2] := ((1.0 - Cos(w0)) / 2.0);
        a[0] := ( 1.0 + alpha);
        a[1] := (-2.0 * Cos(w0));
        a[2] := ( 1.0 - alpha);
      end;
    ftHPF:
      begin
        b[0] := ((1.0 + Cos(w0)) / 2.0);
        b[1] := (-1.0 - Cos(w0));
        b[2] := ((1.0 + Cos(w0)) / 2.0);
        a[0] := ( 1.0 + alpha);
        a[1] := (-2.0 * Cos(w0));
        a[2] := ( 1.0 - alpha);
      end;
    ftBPF:
      begin
        b[0] := alpha;
        b[1] := 0;
        b[2] := -alpha;
        a[0] := ( 1.0 + alpha);
        a[1] := (-2.0 * Cos(w0));
        a[2] := ( 1.0 - alpha);
      end;
    ftBSF:
      begin
        b[0] := 1.0;
        b[1] := (-2.0 * Cos(w0));
        b[2] := 1.0;
        a[0] := ( 1.0 + alpha);
        a[1] := (-2.0 * Cos(w0));
        a[2] := ( 1.0 - alpha);
      end;
  end;
end;

function ToString(Input: PComplex; const N: Integer): string;
var
  I: Integer;
begin
  if N > 0 then
  begin
    Result := '[' + cstr(Input[0]);
    for I := 1 to N - 1 do
      Result := Result + ',' + cstr(Input[I]);
    Result := Result + ']';
  end
  else begin
    Result := '[]';
  end;
end;

function CreateFileStream(const Fn: string): TFileStream;
begin
  if FileExists(Fn) then
  begin
    Result := TFileStream.Create(Fn, fmOpenReadWrite);
    Result.Seek(0, soFromEnd);
  end
  else
    Result := TFileStream.Create(Fn, fmCreate);
end;

procedure DumpData(const P: PComplex; const Len: Integer; const Fn: string);
var
  F: TFileStream;
  S: string;
  I: Integer;
begin
  F := CreateFileStream(Fn);
  for I := 0 to Len - 1 do
  begin
    S := Format('%2.8f + %2.8f I' + #13#10, [P[I].re, P[I].im]);
    F.Write(S[1], Length(S));
  end;
  F.Free;
end;

procedure DumpData(const P: PDouble; const Len: Integer; const Fn: string);
var
  F: TFileStream;
  S: string;
  I: Integer;
begin
  F := CreateFileStream(Fn);
  for I := 0 to Len - 1 do
  begin
    S := Format('%.8f' + #13#10, [P[I]]);
    F.Write(S[1], Length(S));
  end;
  F.Free;
end;

procedure Decimate(const FactorM: Integer; H: array of Double;
  var Z: array of Complex; Input: PComplex; InLen: Integer;
  Output: PComplex; out OutLen: Integer);
var
  LenH1: Integer;
  Tap: Integer;
  Sum: Complex;
begin
  OutLen := InLen div FactorM;
{$ifdef _DEBUG}
  if InLen mod FactorM <> 0 then
    raise Exception.Create('InLen mod FactorM <> 0');
{$endif}

  LenH1 := High(H);
  while InLen >= FactorM do
  begin
    // shift FactorM inputs into Z
    for Tap := LenH1 downto FactorM do
      Z[Tap] := Z[Tap - FactorM];
    for Tap := FactorM - 1 downto 0 do
    begin
      Z[Tap] := Input^;
      Inc(Input);
    end;
    Dec(InLen, FactorM);

    Sum.re := 0; Sum.im := 0;
    for Tap := 0 to FactorM - 1 do
      Sum := Sum + H[Tap] * Z[Tap];
    Output^ := Sum;
    Inc(Output);
  end;
end;

procedure Interpolate(const FactorL: Integer; H: array of Double;
  var Z: array of Complex; Input: PComplex; InLen: Integer; Output: PComplex;
  out OutLen: Integer);
var
  Tap, PhaseNum: Integer;
  PCoeff: PDouble;
  Sum: Complex;
  TapsPerPhaseHigh: Integer;
begin
  TapsPerPhaseHigh := High(Z);
  OutLen := FactorL * InLen;

{$ifdef _DEBUG}
  if FactorL * (TapsPerPhaseHigh + 1) <> High(H) + 1 then
    raise Exception.Create('FactorL * (TapsPerPhaseHigh + 1) <> High(H) + 1');
{$endif}

  while InLen > 0 do
  begin
    Dec(InLen);

    // shift data into Z delay line
    for Tap := TapsPerPhaseHigh downto 1 do
      Z[Tap] := Z[Tap - 1];
    Z[0] := Input^;
    Inc(Input);

    for PhaseNum := 0 to FactorL - 1 do
    begin
      PCoeff := @H[PhaseNum];

      Sum := 0;
      for Tap := 0 to TapsPerPhaseHigh do
      begin
        Sum := Sum + PCoeff^ * Z[Tap];
        Inc(PCoeff, FactorL);
      end;
      Output^ := Sum;
      Inc(Output);
    end;
  end;
end;

procedure Resample(const IntepL, DecimM: Integer; H: array of Double;
  var Z: array of Complex; var CurPhase: Integer; Input: PComplex;
  InLen: Integer; Output: PComplex; out OutLen: Integer);
var
  Tap, NumOut, NumNewSamples: Integer;
  PCoeff: PDouble;
  Sum: Complex;
  TapsPerPhase: Integer;
begin
  TapsPerPhase := Length(Z);
{$ifdef _DEBUG}
  if IntepL * TapsPerPhase <> Length(H) then
    raise Exception.Create('FactorL * TapsPerPhase <> Length(H)');
{$endif}

  NumOut := 0;
  while InLen > 0 do
  begin
    // figure out how many new samples to shift into Z delay line
    NumNewSamples := 0;
    while CurPhase >= IntepL do
    begin
      Dec(CurPhase, IntepL);
      Inc(NumNewSamples);
      Dec(InLen);
      if InLen = 0 then Break;
    end;

    if NumNewSamples > TapsPerPhase then
    begin
      // the new samples are bigger than the size of Z:
      // fill the entire Z with the tail of new inputs
      Inc(Input, NumNewSamples - TapsPerPhase);
      NumNewSamples := TapsPerPhase;
    end;

    // copy new samples into Z
    for Tap := TapsPerPhase - 1 downto NumNewSamples do
      Z[Tap] := Z[Tap - NumNewSamples];
    for Tap := NumNewSamples -1 downto 0 do
    begin
      Z[Tap] := Input^;
      Inc(Input);
    end;

    // caculate output
    while CurPhase < IntepL do
    begin
      PCoeff := @H[CurPhase];

      Sum := 0;
      for Tap := 0 to TapsPerPhase - 1 do
      begin
        Sum := Sum + PCoeff^ * Z[Tap];
        Inc(PCoeff, IntepL);
      end;
      Output^ := Sum;
      Inc(Output);
      Inc(NumOut);

      // increase phase number by decimation factor M
      Inc(CurPhase, DecimM);
    end;
  end;
  OutLen := NumOut;
end;

procedure SetIIROrders(var AFilter: TIIRFilter; XDelay, YDelay: Integer);
begin
  SetLength(AFilter.Zx, XDelay);
  SetLength(AFilter.Zy, YDelay);
  FillByte(AFilter.Zx[0], Length(AFilter.Zx) * SizeOf(Complex), 0);
  FillByte(AFilter.Zy[0], Length(AFilter.Zx) * SizeOf(Complex), 0);
  SetLength(AFilter.A, YDelay + 1);
  SetLength(AFilter.B, XDelay + 1);
  FillByte(AFilter.A[0], Length(AFilter.A) * SizeOf(AFilter.A[0]), 0);
  FillByte(AFilter.B[0], Length(AFilter.B) * SizeOf(AFilter.B[0]), 0);
  AFilter.A[0] := 1.0;
end;

procedure IIRFilter(var AFilter: TIIRFilter; X, Y: PComplex; const N: Integer);
var
  I: Integer;
  J: Integer;
  T: Complex;
begin
  for I := 0 to N - 1 do
  begin
    T := X^ * AFilter.B[0];
    for J := 0 to High(AFilter.Zx) do
      T := T + AFilter.Zx[J] * AFilter.B[J + 1];
    for J := 0 to High(AFilter.Zy) do
      T := T - AFilter.Zy[J] * AFilter.A[J + 1];
    T := T / AFilter.A[0];
    Y^ := T;
    for J := High(AFilter.Zx) downto 1 do
      AFilter.Zx[J] := AFilter.Zx[J - 1];
    AFilter.Zx[0] := X^;
    for J := High(AFilter.Zy) downto 1 do
      AFilter.Zy[J] := AFilter.Zy[J - 1];
    AFilter.Zy[0] := T;
    Inc(X);
    Inc(Y);
  end;
end;

procedure IIRFilter(var AFilter: TIIRFilter; IO: PComplex; const N: Integer);
var
  I: Integer;
  J: Integer;
  T: Complex;
begin
  for I := 0 to N - 1 do
  begin
    T := IO^ * AFilter.B[0];
    for J := 0 to High(AFilter.Zx) do
      T := T + AFilter.Zx[J] * AFilter.B[J + 1];
    for J := 0 to High(AFilter.Zy) do
      T := T - AFilter.Zy[J] * AFilter.A[J + 1];
    T := T / AFilter.A[0];

    for J := High(AFilter.Zx) downto 1 do
      AFilter.Zx[J] := AFilter.Zx[J - 1];
    AFilter.Zx[0] := IO^;
    for J := High(AFilter.Zy) downto 1 do
      AFilter.Zy[J] := AFilter.Zy[J - 1];
    AFilter.Zy[0] := T;
    IO^ := T;
    Inc(IO);
  end;
end;

procedure IIRFilter(var AFilter: TIIRFilter; IO: PDouble; const N: Integer);
var
  I: Integer;
  J: Integer;
  T: Double;
begin
  for I := 0 to N - 1 do
  begin
    T := IO^ * AFilter.B[0];
    for J := 0 to High(AFilter.Zx) do
      T := T + AFilter.Zx[J].re * AFilter.B[J + 1];
    for J := 0 to High(AFilter.Zy) do
      T := T - AFilter.Zy[J].re * AFilter.A[J + 1];
    T := T / AFilter.A[0];

    for J := High(AFilter.Zx) downto 1 do
      AFilter.Zx[J].re := AFilter.Zx[J - 1].re;
    AFilter.Zx[0].re := IO^;
    for J := High(AFilter.Zy) downto 1 do
      AFilter.Zy[J].re := AFilter.Zy[J - 1].re;
    AFilter.Zy[0].re := T;
    IO^ := T;
    Inc(IO);
  end;
end;

procedure IIRFilterReal(var AFilter: TIIRFilter; IO: PComplex; const N: Integer
  );
var
  I: Integer;
  J: Integer;
  T: Double;
begin
  for I := 0 to N - 1 do
  begin
    T := IO^.re * AFilter.B[0];
    for J := 0 to High(AFilter.Zx) do
      T := T + AFilter.Zx[J].re * AFilter.B[J + 1];
    for J := 0 to High(AFilter.Zy) do
      T := T - AFilter.Zy[J].re * AFilter.A[J + 1];
    T := T / AFilter.A[0];

    for J := High(AFilter.Zx) downto 1 do
      AFilter.Zx[J].re := AFilter.Zx[J - 1].re;
    AFilter.Zx[0].re := IO^.re;
    for J := High(AFilter.Zy) downto 1 do
      AFilter.Zy[J].re := AFilter.Zy[J - 1].re;
    AFilter.Zy[0].re := T;
    IO^.re := T;
    Inc(IO);
  end;
end;

procedure IIRFilterReal(var AFilter: TIIRFilter; X: PComplex; Y: PDouble;
  const N: Integer);
var
  I: Integer;
  J: Integer;
  T: Double;
begin
  for I := 0 to N - 1 do
  begin
    T := X^.re * AFilter.B[0];
    for J := 0 to High(AFilter.Zx) do
      T := T + AFilter.Zx[J].re * AFilter.B[J + 1];
    for J := 0 to High(AFilter.Zy) do
      T := T - AFilter.Zy[J].re * AFilter.A[J + 1];
    T := T / AFilter.A[0];

    for J := High(AFilter.Zx) downto 1 do
      AFilter.Zx[J].re := AFilter.Zx[J - 1].re;
    AFilter.Zx[0].re := X^.re;
    for J := High(AFilter.Zy) downto 1 do
      AFilter.Zy[J].re := AFilter.Zy[J - 1].re;
    AFilter.Zy[0].re := T;
    Y^ := T;
    Inc(X);
    Inc(Y);
  end;
end;

procedure IIRFilterReal(var AFilter: TIIRFilter; X: PComplex; Y: PComplex;
  const N: Integer);
var
  I: Integer;
  J: Integer;
  T: Double;
begin
  for I := 0 to N - 1 do
  begin
    T := X^.re * AFilter.B[0];
    for J := 0 to High(AFilter.Zx) do
      T := T + AFilter.Zx[J].re * AFilter.B[J + 1];
    for J := 0 to High(AFilter.Zy) do
      T := T - AFilter.Zy[J].re * AFilter.A[J + 1];
    T := T / AFilter.A[0];

    for J := High(AFilter.Zx) downto 1 do
      AFilter.Zx[J].re := AFilter.Zx[J - 1].re;
    AFilter.Zx[0].re := X^.re;
    for J := High(AFilter.Zy) downto 1 do
      AFilter.Zy[J].re := AFilter.Zy[J - 1].re;
    AFilter.Zy[0].re := T;
    Y^.re := T;
    Inc(X);
    Inc(Y);
  end;
end;

procedure IIRFilterReInIm(var AFilter: TIIRFilter; X: PComplex; Y: PComplex;
  const N: Integer);
var
  I: Integer;
  J: Integer;
  T: Double;
begin
  for I := 0 to N - 1 do
  begin
    T := X^.im * AFilter.B[0];
    for J := 0 to High(AFilter.Zx) do
      T := T + AFilter.Zx[J].im * AFilter.B[J + 1];
    for J := 0 to High(AFilter.Zy) do
      T := T - AFilter.Zy[J].im * AFilter.A[J + 1];
    T := T / AFilter.A[0];

    for J := High(AFilter.Zx) downto 1 do
      AFilter.Zx[J].im := AFilter.Zx[J - 1].im;
    AFilter.Zx[0].im := X^.im;
    for J := High(AFilter.Zy) downto 1 do
      AFilter.Zy[J].im := AFilter.Zy[J - 1].im;
    AFilter.Zy[0].im := T;
    Y^.im := T;
    Inc(X);
    Inc(Y);
  end;
end;

procedure ModArg(Input: PComplex; Output: PComplex; const N: Integer);
var
  I: Integer;
begin
  for I := 0 to N - 1 do
  begin
    Output[I].re := cmod(Input[I]);
    Output[I].im := carg(Input[I]);
  end;
end;

procedure ModArg(IO: PComplex; const N: Integer);
var
  I: Integer;
  T: Complex;
begin
  for I := 0 to N - 1 do
  begin
    T := IO[I];
    IO[I].re := cmod(T);
    IO[I].im := carg(T);
  end;
end;

procedure PowArg(Input: PComplex; Output: PComplex; const N: Integer);
var
  I: Integer;
begin
  for I := 0 to N - 1 do
  begin
    Output[I].re := Input[I].re * Input[I].re + Input[I].im * Input[I].im;
    Output[I].im := carg(Input[I]);
  end;
end;

procedure PowArg(IO: PComplex; const N: Integer);
var
  I: Integer;
  T: Complex;
begin
  for I := 0 to N - 1 do
  begin
    T := IO[I];
    IO[I].re := T.re * T.re + T.im * T.im;
    IO[I].im := carg(T);
  end;
end;

procedure Pow(Input: PComplex; Output: PComplex; const N: Integer);
var
  I: Integer;
begin
  for I := 0 to N - 1 do
  begin
    Output[I].re := Input[I].re * Input[I].re + Input[I].im * Input[I].im;
  end;
end;

procedure Pow(IO: PComplex; const N: Integer);
var
  I: Integer;
begin
  for I := 0 to N - 1 do
  begin
    IO[I].re := IO[I].re * IO[I].re + IO[I].im * IO[I].im;
  end;
end;

procedure SpectrumPower(Spectrum: PComplex; P: PDouble; const N: Integer);
var
  I, J, L: Integer;
  function X(const C: Complex): Double; inline;
  begin
    Result := C.re * C.re + C.im * C.im;
  end;
begin
  J := N div 2;
  L := N - J;
  for I := 0 to J - 1 do
    P[I + L] := X(Spectrum[I]);
  for I := 0 to L - 1 do
    P[I] := X(Spectrum[I + J]);
end;

procedure SpectrumPowArg(Spectrum: PComplex; P: PComplex; const N: Integer);
var
  I, J, L: Integer;
  function X(const C: Complex): Double; inline;
  begin
    Result := C.re * C.re + C.im * C.im;
  end;
begin
  J := N div 2;
  L := N - J;
  for I := 0 to J - 1 do
  begin
    P[I + L].re := X(Spectrum[I]);
    P[I + L].im := carg(Spectrum[I]);
  end;
  for I := 0 to L - 1 do
  begin
    P[I].re := X(Spectrum[I + J]);
    P[I].im := carg(Spectrum[I + J]);
  end;
end;

procedure CreateWindowFunction(P: PDouble; const N: Integer;
  const Func: TWindowFunction; Param: Double);
var
  I: Integer;
begin
  case Func of
    wfRect:
      for I := 0 to N - 1 do P[I] := 1.0;
    wfHamming:
      for I := 0 to N - 1 do P[I] := 0.53836 - 0.46164 * Cos(2 * Pi * I / (N - 1));
    wfHann:
      for I := 0 to N - 1 do P[I] := 0.5 * (1 - Cos(2 * Pi * I / (N - 1)));
    wfTriangular:
      for I := 0 to N - 1 do P[I] := 1 - (2 / N) * Abs(I - (N - 1) / 2);
    wfBartlett:
      for I := 0 to N - 1 do P[I] := 1 - (2 / (N - 1 )) * Abs(I - (N - 1) / 2);
    wfBlackman:
      for I := 0 to N - 1 do P[I] := 0.42659 - 0.49656 * Cos(2 * Pi * I / (N - 1)) + 0.076849 * Cos(4 * Pi * I / (N - 1));
    wfBartlettHann:
      for I := 0 to N - 1 do P[I] := 0.62 - 0.48 * Abs(I / (N - 1) - 0.5) - 0.38 * Cos(2 * Pi * I / (N - 1));
    wfGaussian:
      begin
        if Param < 0 then Param := 0.4;
        if Param > 0.5 then raise Exception.Create('Gaussian window alpha > 0.5');
        for I := 0 to N - 1 do P[I] := Exp(-0.5 * Sqr((2 * I / (N - 1) - 1) / Param));
      end;
    wfKaiser:
      begin
        if Param < 0 then Param := 3;
        for I := 0 to N - 1 do P[I] := BesselI0(Pi * Param * Sqrt(1 - Sqr(2 * I / (N - 1) - 1))) / BesselI0(Pi * Param);
      end;
    else
      raise Exception.Create(Format('unknow window: %d', [Func]))
  end;
end;

end.

