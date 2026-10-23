function renderAnalysis(app, force)
%RENDERANALYSIS Analiz sayfası: 4 modlu mühendislik grafiği (ufuk penceresi), skalogram şeridi, 3 görüşlü teşhis, olaylar.
E = app.Engine;
if isempty(app.Selected)
    return
end
id = app.Selected;
k = find(E.Ids == id, 1);
if isempty(k), k = 1; id = E.Ids(1); end
snap = E.snapshot();
for h = ["instant" "day" "week"]
    b = app.An.HorizonButtons.(h);
    if h == app.Horizon
        b.BackgroundColor = [0.10 0.45 0.91];
        b.FontColor = [1 1 1];
    else
        b.BackgroundColor = [0.96 0.96 0.96];
        b.FontColor = [0.15 0.18 0.22];
    end
end
heads = ["Anlık" "Bugün" "7 gün"];
hs = ["instant" "day" "week"];
parts = strings(1, 3);
for j = 1:3
    st = app.assess(hs(j)).State(k);
    parts(j) = sprintf('%s: <b><font color="%s">%s</font></b>', heads(j), app.StateColor(st), app.StateTr(st));
end
A = app.assess(app.Horizon);
perf = "";
if app.Horizon ~= "instant" && ~isnan(A.Ratio(k))
    perf = sprintf(" &nbsp;·&nbsp; perf. <b>%%%.1f</b>", 100 * A.Ratio(k));
end
app.An.Status.Text = strjoin(parts, " &nbsp;·&nbsp; ") + perf;

% --- 4 Modlu Mühendislik Grafiği
[t0, t1, day0] = app.horizonWindow();
T = E.series(id, t0, t1);
modeIdx = find(app.ChartModes == app.ChartMode, 1);
modeLbl = "";
if ~isempty(modeIdx)
    modeLbl = " · " + extractAfter(app.ChartModeTitles(modeIdx), ") ");
end
if app.Horizon == "week"
    xl = [day0, max(snap.Time, day0 + hours(1))];
    ttl = id + modeLbl + " — " + string(day0, "dd MMM") + " – " + string(snap.Time, "dd MMM yyyy");
else
    xl = [day0 + hours(5), day0 + hours(21)];
    ttl = id + modeLbl + " — " + string(day0, "dd MMM yyyy");
end
app.An.Chart = updatePowerChart(app.An.Chart, app.An.Axes, T, xl, ttl, app.ChartMode);

% --- Skalogram şeridi + teşhis (saat başı / seçim / ufuk değişince)
key = id + app.Horizon + string(day0, "yyyyMMdd") + string(snap.Time, "yyyyMMddHH");
if ~force && isfield(app.RenderKey, "analysis") && app.RenderKey.analysis == key
    return
end
app.RenderKey.analysis = key;
if app.Horizon == "week"
    dayList = day0 + days(0:6)';
    dayList = dayList(dayList <= snap.Time);
else
    dayList = day0;
end
try
    V = app.periodDays(id, dayList);
catch err
    V = [];
    app.An.ScaloPanel.Title = "Skalogram hesaplanamadı: " + err.message;
end
n = numel(V);
widths = [repmat({"1x"}, 1, n) repmat({0}, 1, 7 - n) {250}];
if n == 1
    widths = [{170} repmat({0}, 1, 6) {"1x"}];
end
app.An.ScaloGrid.ColumnWidth = widths;
wd = ["Paz" "Pzt" "Sal" "Çar" "Per" "Cum" "Cmt"];
for j = 1:7
    if j > n
        app.An.ScaloImg(j).Visible = "off";
        app.An.ScaloLbl(j).Text = "";
        continue
    end
    v = V(j);
    app.An.ScaloImg(j).Visible = "on";
    app.An.ScaloImg(j).ImageSource = imresize(v.Rgb, [128 128], "nearest");
    lab = wd(weekday(v.Day)) + " " + string(v.Day, "dd.MM");
    if snap.Time < v.Day + days(1)
        lab = lab + " (sürüyor)";
    end
    lab = lab + newline + v.LabelTr;
    if v.ThrottleHours > 0
        lab = lab + sprintf(" %.1f sa", v.ThrottleHours);
    end
    if ~isnan(v.PerfPct)
        lab = lab + sprintf(" · %%%.0f", v.PerfPct);
    end
    if ~v.Ok
        lab = lab + " · veri az";
    end
    app.An.ScaloLbl(j).Text = lab;
    app.An.ScaloImg(j).Tooltip = sprintf("%s — %s, performans %%%.1f, kısma %.1f saat, açıklanamayan eksik %%%.1f", ...
        string(v.Day, "dd.MM.yyyy"), v.LabelTr, v.PerfPct, v.ThrottleHours, v.ResDefPct);
end
if n > 1
    app.An.ScaloPanel.Title = sprintf("Skalogram — son %d gün (her gün ayrı; altında o günün sensör teşhisi ve performansı)", n);
else
    app.An.ScaloPanel.Title = "Skalogram — " + string(day0, "dd.MM.yyyy");
end

% Teşhis: değerlendirilen günün çoklu ajan kararı
dDay = snap.Time;
if app.Horizon == "day"
    dDay = day0;
end
try
    r = ges.agents.diagnoseDay(app.Ctx, id, dDay);
    app.LastDiagnosis = r;
    app.DiagTime = snap.Time;
    app.An.Agent.Value = [sprintf("Teşhis: %s günü (%s itibarıyla; saat başı yenilenir)", r.Day, string(snap.Time, "dd.MM.yyyy HH:mm")); app.describe(r)];
catch err
    app.LastDiagnosis = [];
    app.An.Agent.Value = "Teşhis yapılamadı: " + err.message;
end
ev = app.Ctx.Catalog(app.Ctx.Catalog.Id == id & app.Ctx.Catalog.Start <= snap.Time ...
    & app.Ctx.Catalog.End >= snap.Time - days(30), :);
ev = sortrows(ev, "Start", "descend");
lossCol = round(ev.LossKwh, 2);
app.An.Events.Data = table(eventNameTr(ev.Type, ev.Detail), ev.PV, ...
    string(ev.Start, "dd.MM HH:mm"), round(days(min(ev.End, snap.Time) - ev.Start), 1), ...
    lossCol, ev.Chronic);
end
