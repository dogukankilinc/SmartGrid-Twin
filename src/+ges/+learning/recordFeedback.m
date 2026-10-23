function f = recordFeedback(cfg, id, day, label, opts)
%RECORDFEEDBACK Kullanıcı / saha denetimi geri bildirimini kaydet.
%   f = ges.learning.recordFeedback(cfg, id, day, label) — id: cihaz kimliği,
%   day: datetime, label: string sınıf etiketi.
%   Kaydedilen geri bildirim artifacts/feedback/<id>_feedback.csv dosyasına eklenir.
%   Birden fazla geri bildirim birikince (MinCount) ilgili modelin yeniden kalibrasyonu önerilir.
arguments
    cfg  (1,1) struct
    id   (1,1) string
    day  (1,1) datetime
    label(1,1) string
    opts.Note     (1,1) string  = ""
    opts.Source   (1,1) string  = "user"   % "user" | "field_inspection"
    opts.MinCount (1,1) double  = 3
end

fbDir = fullfile(cfg.paths.root, "artifacts", "feedback");
if ~isfolder(fbDir); mkdir(fbDir); end
fbFile = fullfile(fbDir, id + "_feedback.csv");

newRow = table(day, label, opts.Note, opts.Source, datetime("now"), ...
    VariableNames=["Day" "Label" "Note" "Source" "RecordedAt"]);
if isfile(fbFile)
    existing = readtable(fbFile, TextType="string");
    combined = [existing; newRow];
else
    combined = newRow;
end
writetable(combined, fbFile);

f.Id        = id;
f.Day       = day;
f.Label     = label;
f.Source    = opts.Source;
f.TotalFeedback = height(combined);
f.RetainSuggested = f.TotalFeedback >= opts.MinCount;
if f.RetainSuggested
    fprintf("[Geri Bildirim] %s: %d geri bildirim birikti → kalibrasyon önerilir.\n", id, f.TotalFeedback);
end
end
