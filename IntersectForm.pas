(* This Source Code Form is subject to the terms of the Mozilla Public
   License, v. 2.0. If a copy of the MPL was not distributed with this file,
   You can obtain one at http://mozilla.org/MPL/2.0/. *)

unit IntersectForm;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.Objects, FMX.Ani;

type
  TMainIntersectForm = class(TForm)
    pb1: TPaintBox;
    lbDT: TLabel;
    tmrComputeFPS: TTimer;
    tmrDelayMorphing: TTimer;
    procedure pb1Paint(Sender: TObject; Canvas: TCanvas);
    procedure FormCreate(Sender: TObject);
    procedure tmrComputeFPSTimer(Sender: TObject);
    procedure tmrDelayMorphingTimer(Sender: TObject);
  private
    { Déclarations privées }
    FMorpher: TAnimation;
    FAnimator: TAnimation;
    FFrames: Cardinal;
    procedure Process(Sender: TObject);
  public
    { Déclarations publiques }
  end;

var
  MainIntersectForm: TMainIntersectForm;

implementation

{$R *.fmx}

type
  TPointAnimation = class(TAnimation)
  private
    type
      TBorder = (bTop, bRight, bBottom, bLeft);
  private var
    FBorder: TBorder;
    FControl: TControl;
    FEndSegment: TPointF;
    FFirstPass: Boolean;
  protected
    procedure ProcessAnimation; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Control: TControl read FControl write FControl;
    property Point: TPointF read FEndSegment;
  end;

  TPolygonAnimation = class(TAnimation)
  private
    FControl: TControl;
    FStock: array of TPolygon;
    FBase, FTarget: Integer;
    FShape: TPolygon;
    procedure SetControl(const Value: TControl);
    procedure ResamplePolygon(Index: Integer; FinalPoints: Integer);
  protected
    procedure ProcessAnimation; override;
    procedure Start; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Control: TControl read FControl write SetControl;
    property Shape: TPolygon read FShape;
  end;

{ TPointAnimation }

constructor TPointAnimation.Create(AOwner: TComponent);
begin
  inherited;
  Loop := True;
  FFirstPass := True;
  FBorder := bTop;
  FEndSegment := PointF(0,0);
end;

procedure TPointAnimation.ProcessAnimation;
var
  T: Single;
begin
  if (FControl = nil) then
    Exit;

  T := NormalizedTime;

  if (T = 0) then
  begin
    if FFirstPass then
      FFirstPass := False
    else
    begin
      Inc(FBorder);
      if FBorder > High(TBorder) then
        FBorder := Low(TBorder);
    end;
  end;

  { Moves the end point along the four edges of the paintbox }

  case FBorder of
  bTop:
    begin
      FEndSegment.Y := 0;
      FEndSegment.X := FControl.Width * T;
    end;
  bRight:
    begin
      FEndSegment.X := FControl.Width;
      FEndSegment.Y := FControl.Height * T;
    end;
  bBottom:
    begin
      FEndSegment.Y := FControl.Height;
      FEndSegment.X := FControl.Width * (1 - T);
    end;
  bLeft:
    begin
      FEndSegment.X := 0;
      FEndSegment.Y := FControl.Height * (1 - T);
    end;
  end;
end;

{ TPolygonAnimation }

constructor TPolygonAnimation.Create(AOwner: TComponent);
begin
  inherited;
  Loop := True;
  FControl := nil; { The paintbox }
  FStock := nil;   { The polygons we plan to morph between }
  FBase := 0;      { Current "base" polygon }
  FTarget := 0;    { Current "target" polygon }
  FShape := nil;   { Current "interpolation" between "base" and "target" polygons }
end;

procedure TPolygonAnimation.SetControl(const Value: TControl);

  procedure RemoveClosePolygon(var P: TPolygon);
  begin
    if (P[High(P)].X = ClosePolygon.X) and (P[High(P)].Y = ClosePolygon.Y) then
      P[High(P)] := P[0];
  end;

  procedure StorePolygon(D: TPathData; I: Integer; var Biggest: Integer);
  begin
    D.FlattenToPolygon(FStock[I]);
    RemoveClosePolygon(FStock[I]);
    if Length(FStock[I]) > Biggest then
      Biggest := Length(FStock[I]);
  end;

var
  R: TRectF;
  D: TPathData;
  I: Integer;
  Biggest: Integer;
  Generators: array[1..4] of TCornerType;
begin
  FControl := Value;

  { Corner generators }
  Generators[1] := TCornerType.ctInnerLine;
  Generators[2] := TCornerType.ctRound;
  Generators[3] := TCornerType.ctInnerRound;
  Generators[4] := TCornerType.ctBevel;

  { FControl is the PaintBox }
  R := FControl.LocalRect;
  InflateRect(R, -10, -10);

  SetLength(FStock, 5);

  D := TPathData.Create;
  try
    Biggest := 0;

    { The first Polygon is a simple rectangle }
    D.AddRectangle(R, 20, 20, []);
    StorePolygon(D, 0, Biggest);

    { Others are rectangle with rounded corners }
    for I := Low(Generators) to High(Generators) do
    begin
      D.Clear;
      D.AddRectangle(R, 20, 20, AllCorners, Generators[I]);
      StorePolygon(D, I, Biggest);
    end;
  finally
    D.Free;
  end;

  { We want all polygons to have the same number of points }

  for I := 0 to Length(FStock) - 1 do
    ResamplePolygon(I, Biggest);

  { Initialize the shape with the first polygon, so that we can draw something
    even if the animation has not been started }

  FBase := 0;
  SetLength(FShape, Length(FStock[FBase]));
  Move(FStock[FBase][0], FShape[0], Length(FStock[FBase]) * SizeOf(TPointF));
end;

procedure TPolygonAnimation.ResamplePolygon(Index, FinalPoints: Integer);
var
  R, Z: Single;
  P, I, C: Integer;
  P1, P2, PO: TPointF;
begin
  { Interpolate points between existing points of the polygon }

  C := Length(FStock[Index]);
  if FinalPoints <= C then
    Exit;

  SetLength(FStock[Index], FinalPoints);

  I := FinalPoints;
  R := I / (C - 1);

  Z := 0;
  while I > 0 do
  begin
    Assert(C > 1);

    Z := Z + R;

    P1 := FStock[Index][C - 1];
    P2 := FStock[Index][C - 2];

    PO := PointF((P1.X - P2.X) / Round(Z), (P1.Y - P2.Y) / Round(Z));

    for P := 0 to Round(Z) - 1 do
    begin
      FStock[Index][I] := P1 - PointF(PO.X * P, PO.Y * P);
      Dec(I);
    end;

    Z := Z - Round(Z);

    Dec(C);
  end;
end;

procedure TPolygonAnimation.Start;
begin
  FBase := -1;
  inherited;
end;

procedure TPolygonAnimation.ProcessAnimation;
var
  T: Single;
  I: Integer;
  P: TPointF;
begin
  if (FControl = nil) or (FShape = nil) then
    Exit;

  T := NormalizedTime;

  { Loop between shapes }

  if (T = 0) or (FBase = -1) then
  begin
    Inc(FBase);
    if FBase > High(FStock) then
      FBase := 0;
    FTarget := FBase + 1;
    if FTarget > High(FStock) then
      FTarget := 0;
  end;

  Assert(Length(FStock[FBase]) = Length(FStock[FTarget]));

  { Interpolate a shape between "Base" and "Target" }

  for I := 0 to High(FStock[FBase]) do
  begin
    P := FStock[FTarget][I] - FStock[FBase][I];
    FShape[I] := FStock[FBase][I] + PointF(P.X * T, P.Y * T);
  end;
end;

{ TForm1 }

procedure TMainIntersectForm.FormCreate(Sender: TObject);
begin
  { This animator will move the end of the segment around the rectangle }
  FAnimator := TPointAnimation.Create(Self);
  FAnimator.Parent := Self;
  FAnimator.Duration := 2;
  FAnimator.Interpolation := TInterpolationType.itLinear;
  TPointAnimation(FAnimator).Control := pb1;
  FAnimator.OnProcess := Process;
  FAnimator.Start;

  { This animator will morph current shape between polygons }
  FMorpher := TPolygonAnimation.Create(Self);
  FMorpher.Parent := Self;
  FMorpher.Duration := 4;
  FMorpher.Interpolation := TInterpolationType.itLinear;
  TPolygonAnimation(FMorpher).Control := pb1;
end;

procedure TMainIntersectForm.Process(Sender: TObject);
begin
  { Redraw the whole form }
  Invalidate;
  Inc(FFrames);
end;

function Intersect(const A1, A2, B1, B2: TPointF; out P: TPointF): Boolean;

  { Returns the determinant }
  function Det(P1, P2: TPointF): Single; inline;
  begin
    Result := P1.X * P2.Y - P1.Y * P2.X;
  end;

  { Returns True if Min(X1, X2) <= X < Max(X1, X2) }
  function InSignedRange(const X, X1, X2: Single): Boolean; inline;
  begin
    Result := (X < X1) xor (X < X2);
  end;

var
  A, B, AB: TPointF;
  dAB, dBAB, dAAB: Single;
begin
  Result := False;

  A := A2 - A1;
  B := B2 - B1;

  dAB := Det(A, B);

  if dAB = 0 then
    Exit; { vectors A and B hold by (A1,A2) and (B1,B2) are colinear }

  AB := A1 - B1;

  dAAB := Det(A, AB);
  dBAB := Det(B, AB);

  if InSignedRange(dAAB, 0, dAB) and InSignedRange(dBAB, 0, dAB) then
  begin
    Result := True;
    dBAB := dBAB / dAB;
    P.X := A1.X + dBAB * A.X;
    P.Y := A1.Y + dBAB * A.Y;
  end;
end;

procedure TMainIntersectForm.pb1Paint(Sender: TObject; Canvas: TCanvas);
var
  R: TRectF;
  C, I: TPointF;
  J, K: Integer;
  Shape: TPolygon;
  EndPoint: TPointF;
begin
  Shape := TPolygonAnimation(FMorpher).Shape;
  EndPoint := TPointAnimation(FAnimator).Point;

  Canvas.StrokeThickness := 1;
  Canvas.Stroke.Kind := TBrushKind.bkSolid;
  Canvas.Stroke.Color := $A0909090;

  { Paintbox }
  R := pb1.LocalRect;

  { Border }
  InflateRect(R, -0.5, -0.5);
  Canvas.StrokeDash := TStrokeDash.sdDash;
  Canvas.DrawRect(R, 0, 0, AllCorners, pb1.AbsoluteOpacity);

  InflateRect(R, -10, -10);

  { Draw the current polygon }
  Canvas.StrokeThickness := 3;
  Canvas.StrokeDash := TStrokeDash.sdSolid;
  Canvas.Stroke.Kind := TBrushKind.bkSolid;

  Canvas.DrawPolygon(Shape, pb1.AbsoluteOpacity);

  { Compute the center of the diagonals (it is fun and it tests the validity of
    the Intersect algorithmn) }
  if Intersect(R.TopLeft, R.BottomRight, PointF(R.Bottom, R.Left), PointF(R.Top, R.Right), C) then
    Canvas.DrawArc(C, PointF(2, 2), 0, 360, pb1.AbsoluteOpacity * 1.05);

  { A segment that moves around the shape from C (center) to EndPoint that
    is moved by TPointAnimation }
  Canvas.StrokeThickness := 1;
  Canvas.StrokeDash := TStrokeDash.sdDash;
  Canvas.DrawLine(C, EndPoint, pb1.AbsoluteOpacity);

  Canvas.StrokeThickness := 3;
  Canvas.StrokeDash := TStrokeDash.sdSolid;
  Canvas.Stroke.Kind := TBrushKind.bkSolid;

  { Find the first intersection point between the moving segment and the
    current shape }
  for J := Low(Shape) to High(Shape) - 1 do
  begin
    K := J + 1;
    if (Shape[K].X = ClosePolygon.X) and (Shape[K].Y = ClosePolygon.Y) then
      K := 0;
    if Intersect(C, EndPoint, Shape[J], Shape[K], I) then
    begin
      Canvas.DrawArc(I, PointF(2, 2), 0, 360, pb1.AbsoluteOpacity);
      Exit;
    end;
  end;
end;

procedure TMainIntersectForm.tmrComputeFPSTimer(Sender: TObject);
var
  FPS: Single;
begin
  { Try to compute the Frame Per Second value }
  FPS := FFrames / tmrComputeFPS.Interval * 1000;
  lbDT.Text := Format('%.1f fps', [FPS]);
  FFrames := 0;
end;

procedure TMainIntersectForm.tmrDelayMorphingTimer(Sender: TObject);
begin
  { After two seconds, morphing is started }
  FMorpher.Start;
  tmrDelayMorphing.Enabled := False;
end;

end.
