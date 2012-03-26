program Intersection;

uses
  FMX.Forms,
  IntersectForm in 'IntersectForm.pas' {MainIntersectForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainIntersectForm, MainIntersectForm);
  Application.Run;
end.
