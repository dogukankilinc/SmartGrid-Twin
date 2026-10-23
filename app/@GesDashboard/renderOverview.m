function renderOverview(app, force)
%RENDEROVERVIEW Genel Bakış'ı oynatma anına göre günceller (%100 SmartGridLab 21 sütun kapsaması).
E = app.Engine;
snap = E.snapshot();
tNow = snap.Time;
i = E.Index;
isSingle = numel(E.Ids) <= 1;

% Yardımcı: Engine özelliğinden güvenli okuma
engVal = @(prop, def) getEngVal(E, prop, i, def);
pac  = engVal("Pac", snap.PlantKw);
vdc  = engVal("Vdc", NaN);
idc  = engVal("Idc", NaN);
eff  = engVal("Eff", NaN);
if isnan(eff) && snap.PlantKw > 0.02 && ~isnan(pac)
    eff = 100 * pac / snap.PlantKw;
elseif ~isnan(eff) && eff <= 1.2
    eff = 100 * eff;
end
riso = engVal("Riso", NaN);
vgrid = engVal("Vgrid", NaN);
vgridc = engVal("VgridCond", vgrid);
fgrid = engVal("Fgrid", NaN);
if isnan(vgridc) && ~isnan(vgrid) && ~isnan(fgrid) && fgrid > 2
    vgridc = vgrid / min(max(fgrid / 50.0, 0.05), 1);
end
wind = engVal("Wind", NaN);
tcell = engVal("Tcell", E.Tmod(i));
ghoriz = engVal("Ghoriz", E.Gref(i));
if isnan(tcell) && ~isnan(E.Tamb(i)) && ~isnan(E.Gref(i))
    w0 = ifelse(isnan(wind), 0.5, max(wind, 0));
    tcell = E.Tamb(i) + max(E.Gref(i), 0) / (25.0 + 6.84 * w0);
end

% --- 6 KPI Kartı
ratio = "";
if snap.PlantExpectedKw > 0.05
    ratio = sprintf(" (%%%.0f)", 100 * snap.PlantKw / snap.PlantExpectedKw);
end
if isSingle
    pDisp = ifelse(isnan(pac), snap.PlantKw, pac);
    app.Ov.Power.Text = sprintf("%.2f kW", pDisp);
    effTxt = ifelse(isnan(eff), "", sprintf(" · η %%%.1f", eff));
    app.Ov.PowerSub.Text = sprintf("bekl. %.2f kW%s%s", snap.PlantExpectedKw, ratio, effTxt);
else
    app.Ov.Power.Text = sprintf("%.0f kW", snap.PlantKw);
    app.Ov.PowerSub.Text = sprintf("beklenen %.0f kW%s", snap.PlantExpectedKw, ratio);
end

D = app.assess("day");
app.Ov.Today.Text = energyText(D.Plant.Eact);
specTxt = "";
if isSingle && D.Plant.Eact > 0
    specTxt = sprintf(" · %.2f kWh/kWp", D.Plant.Eact / 1.20);
end
app.Ov.TodaySub.Text = perfLine(D.Plant.Eact, D.Plant.Eexp) + specTxt;

m0 = dateshift(tNow, "start", "month");
M = E.energySeries(m0, m0 + calmonths(1), "month");
eMonth = sum(M.Eact, "omitnan");
eMonthExp = sum(M.Eexp, "omitnan");
if isSingle && ~isnan(vdc)
    app.Ov.Month.Text = sprintf("%.0f V · %.2f A", vdc, ifelse(isnan(idc), 0, idc));
    risoTxt = ifelse(isnan(riso), "", sprintf("R_iso %.0f kΩ · ", riso));
    app.Ov.MonthSub.Text = risoTxt + "Ay: " + energyText(eMonth);
else
    app.Ov.Month.Text = energyText(eMonth);
    app.Ov.MonthSub.Text = perfLine(eMonth, eMonthExp) + ifelse(isnan(riso), "", sprintf(" · R_iso %.0f kΩ", riso));
end

[t0, ~] = E.range();
T = E.energySeries(dateshift(t0, "start", "month"), m0 + calmonths(1), "month");
eTot = sum(T.Eact, "omitnan");
eTotExp = sum(T.Eexp, "omitnan");
if isSingle && ~isnan(vgridc) && vgridc > 0
    k18 = round(min(max(fgrid / 50.0, 0), 1) * 18);
    app.Ov.Total.Text = sprintf("%.1f V · %.2f Hz", vgridc, fgrid);
    app.Ov.TotalSub.Text = sprintf("Röle %d/18 · Toplam %s", k18, energyText(eTot));
else
    app.Ov.Total.Text = energyText(eTot);
    app.Ov.TotalSub.Text = perfLine(eTot, eTotExp) + " · " + string(t0, "dd.MM.yyyy") + "'den beri";
end

app.Ov.States.Text = sprintf("%d / %d / %d", snap.NumAlarm, snap.NumWarning, snap.NumChronic);
if isSingle && ~isnan(tcell)
    app.Ov.StatesSub.Text = sprintf("T_cell %.1f°C · v_w %.1f m/s", tcell, ifelse(isnan(wind), 0, wind));
else
    app.Ov.StatesSub.Text = sprintf("ısıl kısmada %d cihaz", nnz(snap.State == "thermal"));
end

if isnan(snap.Kc)
    app.Ov.Sky.Text = "🌙 Gece";
    app.Ov.SkySub.Text = sprintf("G_poa %.0f W/m²", max(E.Gref(i), 0));
else
    s = skyText(snap.Kc, false);
    app.Ov.Sky.Text = extractBefore(s + "  (", "  (");
    app.Ov.SkySub.Text = sprintf("açıklık %%%.0f · %.0f W/m²", 100 * snap.Kc, max(E.Gref(i), 0));
end

% --- Hava, Termal İkiz & Elektriksel Özet Kartı
w = sprintf("POA Işınım (32°): %.0f W/m² (Yatay GHI: %.0f W/m²)", max(E.Gref(i), 0), max(ghoriz, 0));
if ~isnan(E.Tamb(i))
    w = w + sprintf("  ·  Ortam: %.1f °C", E.Tamb(i));
end
if ~isnan(E.Tmod(i))
    w = w + sprintf("  ·  Ross T_mod: %.1f °C", E.Tmod(i));
end
if ~isnan(tcell)
    w = w + sprintf("  ·  Faiman T_cell: %.1f °C", tcell);
end
if ~isnan(wind)
    w = w + sprintf("  ·  Rüzgar: %.2f m/s", wind);
end
if ~isnan(riso) || ~isnan(vgridc)
    w = w + newline + sprintf("DC Bara: V_dc %.1f V, I_dc %.2f A, R_iso %.0f kΩ  |  L1 Şebeke: U_L1,cond %.1f V (Ham %.1f V), f_grid %.2f Hz (L2=0V, L3=0V)", ...
        vdc, idc, riso, vgridc, vgrid, fgrid);
else
    w = w + newline + "Ross T_mod rüzgarsız formüldür; Faiman T_cell rüzgar soğutmasını hesaba katar.";
end
app.Ov.Weather.Text = w;

% --- Durum sayıları (üç ufuk)
I = app.assess("instant");
W = app.assess("week");
st = ["ok" "watch" "thermal" "warning" "alarm" "chronic" "grid" "offline" "night"];
cnt = @(A) arrayfun(@(s) nnz(A.State == s), st)';
names = app.StateTr(st)';
keep = cnt(I) + cnt(D) + cnt(W) > 0;
c3 = [cnt(I) cnt(D) cnt(W)];
app.Ov.StatusTable.Data = table(names(keep), string(c3(keep, 1)), string(c3(keep, 2)), string(c3(keep, 3)), ...
    VariableNames=["Durum" "Anlık" "Bugün" "Son 7 gün"]);

% --- Performans tablosu (Tek eviricide son 7 günün günlük özeti; çoklu eviricide en düşük performanslılar)
if isSingle
    app.Ov.LowPanel.Title = "Son 7 günün günlük performans ve sağlık özeti (tıklayın → Analiz)";
    today0 = dateshift(tNow, "start", "day");
    dayList = (max(dateshift(t0, "start", "day"), today0 - days(6)):days(1):today0)';
    dayList = flip(dayList);
    try
        V = app.periodDays(E.Ids(1), dayList);
        dNames = string({V.Day})';
        for kk = 1:numel(V)
            dNames(kk) = string(V(kk).Day, "dd.MM.yyyy");
        end
        dState = string({V.LabelTr})';
        dPerf = compose("%.1f", [V.PerfPct]');
        dPerf(isnan([V.PerfPct]')) = "—";
        dLoss = compose("%.1f sa kısma", [V.ThrottleHours]');
        dCause = compose("eksik %%%.1f", max([V.ResDefPct]', 0));
        dCause(isnan([V.ResDefPct]')) = "veri yok";
        app.Ov.LowTable.Data = table(dNames, dState, dPerf, dLoss, dCause, ...
            VariableNames=["Birim / Gün" "Durum" "Perf. %" "Kayıp" "Ana neden / R_iso"]);
        app.Ov.LowTable.UserData = [V.Day]';
    catch
        app.Ov.LowTable.Data = table(E.Ids(1), app.StateTr(D.State(1)), compose("%.1f", 100 * D.Ratio(1)), ...
            energyText(max(D.Eexp(1) - D.Eact(1), 0)), "WR13TL22-8231", ...
            VariableNames=["Birim / Gün" "Durum" "Perf. %" "Kayıp" "Ana neden / R_iso"]);
        app.Ov.LowTable.UserData = E.Ids(1);
    end
else
    ok = D.Eexp > 0.1 & ~isnan(D.Ratio);
    idx = find(ok);
    if isempty(idx), idx = 1:min(8, numel(E.Ids)); end
    [~, o] = sort(D.Ratio(idx), "ascend");
    idx = idx(o(1:min(8, end)));
    causes = ["ısıl kısma" "DC dizi/string" "şebeke/L1" "diğer/açıklanamayan"];
    L = [D.LossThermal D.LossDead D.LossGrid D.LossOther];
    [~, c] = max(L(idx, :), [], 2);
    lossK = D.Eexp(idx) - D.Eact(idx);
    cause = causes(c)';
    cause(lossK < 0.05) = "—";
    app.Ov.LowTable.Data = table(E.Ids(idx), app.StateTr(D.State(idx)), compose("%.1f", 100 * D.Ratio(idx)), ...
        arrayfun(@energyText, lossK), cause, VariableNames=["Birim / Gün" "Durum" "Perf. %" "Kayıp" "Ana neden / R_iso"]);
    app.Ov.LowTable.UserData = E.Ids(idx);
end

% --- Enerji grafiği (gün/mod değişince yeniden çizilir)
key = app.EnergyMode + string(tNow, "yyyyMMddHH");
if ~force && isfield(app.RenderKey, "overview") && app.RenderKey.overview == key
    return
end
app.RenderKey.overview = key;
for m = ["week" "month" "year"]
    b = app.Ov.ModeButtons.(m);
    if m == app.EnergyMode
        b.BackgroundColor = [0.10 0.45 0.91];
        b.FontColor = [1 1 1];
    else
        b.BackgroundColor = [0.96 0.96 0.96];
        b.FontColor = [0.15 0.18 0.22];
    end
end
today = dateshift(tNow, "start", "day");
switch app.EnergyMode
    case "week"
        S = E.energySeries(today - days(6), today + days(1), "day");
        lab = string(S.Time, "dd.MM");
        ttl = "Son 7 gün (günlük)";
    case "month"
        S = E.energySeries(m0, m0 + calmonths(1), "day");
        lab = string(S.Time, "dd");
        ttl = string(m0, "MMMM yyyy", "tr_TR") + " (günlük)";
    otherwise
        S = E.energySeries(m0 - calmonths(11), m0 + calmonths(1), "month");
        lab = string(S.Time, "MMM yy", "tr_TR");
        ttl = "Son 12 ay (aylık)";
end
ax = app.Ov.Axes;
cla(ax, "reset");
disableDefaultInteractivity(ax);
scale = 1;
unit = "kWh";
if max(S.Eexp, [], "omitnan") > 20000
    scale = 1000;
    unit = "MWh";
end
Y = [S.Eact S.Eexp] / scale;
Y(isnan(Y)) = 0;
x = categorical(lab, lab);
b = bar(ax, x, Y, "grouped", BarWidth=0.85);
b(1).FaceColor = [0.18 0.62 0.35];
b(2).FaceColor = [0.80 0.84 0.88];
b(2).EdgeColor = [0.55 0.6 0.66];
ylabel(ax, "Enerji (" + unit + ")");
legend(ax, ["Gerçek" "Beklenen (M1)"], Location="northoutside", Orientation="horizontal", Box="off");
grid(ax, "on");
ax.YGrid = "on";
ax.XGrid = "off";
title(ax, ttl);
tot = sum(S.Eact, "omitnan");
totE = sum(S.Eexp, "omitnan");
app.Ov.EnergyInfo.Text = sprintf("Toplam %s / beklenen %s%s", energyText(tot), energyText(totE), perfText(tot, totE));
end

function v = getEngVal(E, prop, idx, def)
v = def;
try
    if isprop(E, prop) && ~isempty(E.(prop))
        arr = E.(prop);
        if size(arr, 1) >= idx
            v = double(arr(idx, 1));
        end
    end
catch
end
end

function s = perfLine(a, e)
if e > 0.05
    s = sprintf("perf. %%%.1f (bekl. %s)", 100 * a / e, energyText(e));
else
    s = "";
end
s = string(s);
end

function s = perfText(a, e)
if e > 0.05
    s = sprintf("  · %%%.1f", 100 * a / e);
else
    s = "";
end
s = string(s);
end
