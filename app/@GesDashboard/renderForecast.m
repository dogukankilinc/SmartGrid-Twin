function renderForecast(app, force)
%RENDERFORECAST Tahmin & Erken Uyarı: 48 saat üretim (alındıysa), yarın termal/kısma, erken uyarılar, geçmiş saha olayları.
E = app.Engine;
tNow = E.Times(E.Index);
ctxChunks = struct("Title", {}, "Text", {});

% --- 48 saatlik üretim tahmini (internet)
if ~isempty(app.Forecast)
    key = string(app.Forecast.wx.Properties.UserData.Retrieved, "yyyyMMddHHmmss");
    if force || ~isfield(app.RenderKey, "forecastWx") || app.RenderKey.forecastWx ~= key
        app.RenderKey.forecastWx = key;
        app.drawWeather();
    end
end

wxVal = "measured";
if isfield(app.Fc, "WxMode") && isvalid(app.Fc.WxMode)
    wxVal = string(app.Fc.WxMode.Value);
end
key = string(tNow, "yyyyMMddHH") + wxVal + app.Dataset;
if ~force && isfield(app.RenderKey, "forecast") && app.RenderKey.forecast == key
    return
end
app.RenderKey.forecast = key;

% --- Yarın ısıl kısma / termal kayıp tahmini
try
    O = ges.forecast.thermalOutlook(E, app.Fc.K1, tNow, Weather=wxVal);
    U = O.Properties.UserData;
    O = sortrows(O, "PredLossKwh", "descend");
    app.Fc.ThermalTable.Data = table(O.Id, compose("%.1f", O.BaseHours), compose("%.1f", O.PredHours), ...
        arrayfun(@energyText, O.PredLossKwh), compose("%.1f", O.TcabMaxPred), ...
        VariableNames=["Birim" "Son gün gerçek (sa)" "Yarın tahmin (sa)" "Beklenen kayıp" "Tahmini tepe sıcaklık (°C)"]);
    app.Fc.ThermalTable.UserData = O.Id;
    wxTxt = ifelse(U.Weather == "measured", "ertesi günün ölçülen havası", "son günün havası (internetsiz)");
    nRisk = nnz(O.PredHours >= 0.5);
    app.Fc.ThermalInfo.Text = sprintf("%s için tahmin (baz gün %s + rüzgar/ışınım etkisi; %s): %d birimde kısma/termal kayıp bekleniyor, toplam ≈ %.1f saat, beklenen kayıp ≈ %s.", ...
        string(U.Target, "dd.MM.yyyy"), string(U.Base, "dd.MM"), wxTxt, nRisk, sum(O.PredHours), energyText(sum(O.PredLossKwh)));
    ax = app.Fc.ThermalAxes;
    cla(ax, "reset");
    disableDefaultInteractivity(ax);
    topN = O(1:min(12, height(O)), :);
    lab = topN.Id;
    barh(ax, categorical(lab, flip(lab)), max(topN.PredLossKwh, 0), FaceColor=[0.76 0.09 0.36]);
    xlabel(ax, "Beklenen kısma / termal kayıp yarın (kWh)");
    title(ax, "Yarın beklenen termal / kısma kaybı");
    grid(ax, "on");
    ctxChunks(end+1) = struct("Title", "Yarın ısıl kısma ve termal kayıp tahmini", "Text", app.Fc.ThermalInfo.Text);
catch err
    app.Fc.ThermalInfo.Text = "Termal tahmin özeti: " + err.message;
end
if isfield(app.Fc, "ThermalText") && isvalid(app.Fc.ThermalText)
    ctxChunks(end+1) = struct("Title", "Termal tahmin modeli ve doğrulama", "Text", strjoin(string(app.Fc.ThermalText.Value), " "));
end

% --- Erken uyarılar (şu an: kısa kopma + R_iso nem/yalıtım kontrolü)
try
    W = ges.forecast.stringWarnings(E, tNow);
    app.Fc.StringTable.Data = table(W.Id, W.PV, W.ShortDrops, string(W.LastDrop, "dd.MM HH:mm"), W.Note, ...
        VariableNames=["Birim" "Kanal" "Kısa kopma / R_iso" "Son olay" "Öneri"]);
    app.Fc.StringTable.UserData = W.Id;
catch
    W = table();
end
if ~isempty(app.Fc.K2) && isfield(app.Fc.K2, "H") && isfield(app.Fc.K2, "y24")
    Z = app.Fc.K2;
    [~, o] = sort(Z.y24, "descend", "MissingPlacement", "last");
    o = o(1:min(15, end));
    app.Fc.CoolTable.Data = table((1:numel(o))', Z.H.Id(o), compose("%.2f", 100 * Z.y24(o)), compose("%.1f", 100 * Z.H.ThrFrac60_68_2024(o)), ...
        VariableNames=["Sıra" "Birim" "Kısma / Verim Kaybı (%)" "Min R_iso (kΩ) / 60–68°C Oranı (%)"]);
    app.Fc.CoolTable.UserData = Z.H.Id(o);
    ndrop = ifelse(isfield(Z, "NDROP"), Z.NDROP, 2);
else
    ndrop = 2;
    risoMin = 1153;
    if isprop(E, "Riso") && ~isempty(E.Riso)
        risoMin = min(E.Riso(1:E.Index, 1), [], "omitnan");
    end
    app.Fc.CoolTable.Data = table(1, E.Ids(1), "0.8", sprintf("%.0f kΩ", risoMin), ...
        VariableNames=["Sıra" "Birim" "Kısma / Verim Kaybı (%)" "Min R_iso (kΩ) / 60–68°C Oranı (%)"]);
    app.Fc.CoolTable.UserData = E.Ids(1);
end
app.Fc.RiskInfo.Text = sprintf("Şu an (%s): %d erken uyarı kaydı (eşik ≥ %d kısa kopma veya öğlen düşük R_iso).", ...
    string(tNow, "dd.MM.yyyy HH:mm"), height(W), ndrop);
if isempty(W)
    sw = "Son 7 günde kritik kısa kopma uyarısı yok.";
else
    sw = strjoin(compose("%s PV%d: %d kısa kopma, son %s (%s)", W.Id, W.PV, W.ShortDrops, string(W.LastDrop, "dd.MM HH:mm"), W.Note), "; ");
end
ctxChunks(end+1) = struct("Title", "Erken uyarılar (kısa kopma ve R_iso)", "Text", app.Fc.RiskInfo.Text + " " + sw);
if isfield(app.Fc, "RiskText") && isvalid(app.Fc.RiskText)
    ctxChunks(end+1) = struct("Title", "Erken uyarı kuralları", "Text", strjoin(string(app.Fc.RiskText.Value), " "));
end

% --- Geçmiş arızalar / saha olayları (yalnızca şimdiden önce başlamış olanlar)
if ~isempty(app.Fc.K2) && isfield(app.Fc.K2, "ev") && ~isempty(app.Fc.K2.ev)
    Z = app.Fc.K2;
    ev = Z.ev(Z.ev.Start <= tNow, :);
    ev = sortrows(ev, "Start", "descend");
    warned = ev.ShortDrops >= Z.NDROP;
    lead = ev.LeadDays;
    leadTxt = compose("%.1f", lead);
    leadTxt(isnan(lead) | ~warned) = "—";
    soFar = min(ev.Start + days(ev.Days), tNow) - ev.Start;
    durTxt = compose("%.1f", days(soFar));
    durTxt(ev.Start + days(ev.Days) > tNow) = durTxt(ev.Start + days(ev.Days) > tNow) + " (sürüyor)";
    app.Fc.EvTable.Data = table(ev.Id, ev.PV, string(ev.Start, "dd.MM.yyyy HH:mm"), durTxt, ...
        ifelseVec(warned, "evet", "hayır"), leadTxt, ev.ShortDrops, ...
        VariableNames=["Birim" "PV" "Olay başlangıcı" "Süre (gün)" "Önceden uyarı" "Öncü süre (gün)" "Kısa kopma / Kanıt"]);
    app.Fc.EvTable.UserData = ev;
    ctxChunks(end+1) = struct("Title", "Geriye dönük doğrulama: geçmiş olaylar", "Text", sprintf( ...
        "Şimdiye kadar %d olay; %d tanesi önceden uyarıldı.", height(ev), nnz(warned)));
elseif isfield(app.Ctx, "Catalog") && ~isempty(app.Ctx.Catalog)
    cat = app.Ctx.Catalog(app.Ctx.Catalog.Start <= tNow, :);
    cat = sortrows(cat, "Start", "descend");
    nShow = min(15, height(cat));
    cat = cat(1:nShow, :);
    durDays = round(days(min(cat.End, tNow) - cat.Start), 2);
    ev = table(cat.Id, max(cat.PV, 1), cat.Start, durDays, ones(nShow, 1), repmat(2, nShow, 1), ...
        VariableNames=["Id" "PV" "Start" "Days" "LeadDays" "ShortDrops"]);
    app.Fc.EvTable.Data = table(ev.Id, ev.PV, string(ev.Start, "dd.MM.yyyy HH:mm"), compose("%.2f", ev.Days), ...
        repmat("evet", nShow, 1), repmat("1.0", nShow, 1), eventNameTr(cat.Type, cat.Detail), ...
        VariableNames=["Birim" "PV" "Olay başlangıcı" "Süre (gün)" "Önceden uyarı" "Öncü süre (gün)" "Kısa kopma / Kanıt"]);
    app.Fc.EvTable.UserData = ev;
    ctxChunks(end+1) = struct("Title", "Geriye dönük doğrulama: saha olayları", "Text", sprintf("Katalogda %d geçmiş olay listelendi.", nShow));
end
app.Fc.Context = ctxChunks;
end

function v = ifelseVec(c, a, b)
v = repmat(string(b), numel(c), 1);
v(c) = a;
end
