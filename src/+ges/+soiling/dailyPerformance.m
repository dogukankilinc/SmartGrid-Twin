function T = dailyPerformance(TT, Steps, fb, opts)
%DAILYPERFORMANCE Tozlanma analizi için günlük performans, akım tabanlı SR ve frekans-solgunluk indeksleri.
%   T = ges.soiling.dailyPerformance(TT, Steps, fb)
%   TT    : işlenmiş invertör verisi (s03), Steps: M1 beklentisi (s05)
%   fb    : cwtfilterbank (64 örnek, skalogramlarla aynı)
%   T sütunları:
%     Day, PI        — Σ P_dc / Σ PdcWork_exp (açık, öğle, geçerli adımlar).
%     PISteps        — PI'ye giren adım sayısı (< MinSteps ise PI = NaN)
%     Fading         — kaba ölçeklerde Σ|CWT(güç)| / Σ|CWT(ışınım)| ("frekans solgunluğu")
%     ExpectedKwh    — o gün beklenen DC enerji (çalışan stringlerle), kayıp kWh hesabı için
%     SR_current     — Eğim (G_poa) ve Faiman sıcaklığı (T_cell_dyn) düzeltmeli akım bazlı tozlanma oranı
%     R_iso_min      — O günkü minimum DC yalıtım direnci (kOhm; yağış/nem doğrulaması için)
%     Kd             — Günlük açıklık indeksi (Σ G / Σ G_cs)
arguments
    TT timetable
    Steps timetable
    fb = []
    opts.MinElevation (1,1) double = 25
    opts.MinKc (1,1) double = 0.6
    opts.MinSteps (1,1) double = 8
    opts.CoarseScales (1,1) double = 12       % en kaba N ölçek (≥ ~4 saatlik periyotlar)
end

clipFree = ~TT.qClip & TT.qOnGrid & ~TT.qFault & ~TT.qDerate & ~TT.qCabinEvent & ~isnan(TT.P_dc);
if ismember("qThrottle", TT.Properties.VariableNames)
    clipFree = clipFree & ~TT.qThrottle;
end

% Birincil meteoroloji kaynağı kontrolü (sabit "K02" yerine hem K02 hem SmartGridLab desteklenir)
if ismember("qMeteoFallback", TT.Properties.VariableNames)
    primaryMeteo = ~TT.qMeteoFallback;
elseif ismember("MeteoSource", TT.Properties.VariableNames)
    primaryMeteo = TT.MeteoSource ~= "PEER";
else
    primaryMeteo = true(height(TT), 1);
end

% Küçük güçlü sistem (SmartGridLab 1.20 kWp) ve büyük sistem (50 kW) uyumlu minimum güç eşiği
pMax = max(Steps.PdcWork_exp, [], "omitnan");
if isempty(pMax) || isnan(pMax)
    minP = 0.05;
else
    minP = min(1.0, 0.05 * pMax);
end

m = clipFree & TT.Elevation > opts.MinElevation & TT.Kc > opts.MinKc ...
    & Steps.PdcWork_exp > minP & primaryMeteo;
day = dateshift(TT.Time, "start", "day");
[g, dayList] = findgroups(day);
nd = numel(dayList);
act = TT.P_dc;
act(~m) = 0;
expw = Steps.PdcWork_exp;
expw(~m | isnan(expw)) = 0;
n = accumarray(g, double(m), [nd 1]);
PI = accumarray(g, act, [nd 1]) ./ accumarray(g, expw, [nd 1]);
PI(n < opts.MinSteps) = NaN;
ew = Steps.PdcWork_exp;
ew(isnan(ew)) = 0;
expectedKwh = accumarray(g, ew * 0.25, [nd 1]);

% Eğim düzeltmeli ışınım (G_poa varsa o, yoksa G_ref) ve Faiman hücre sıcaklığı
if ismember("G_poa", TT.Properties.VariableNames)
    gIrr = TT.G_poa;
else
    gIrr = TT.G_ref;
end
if ismember("T_cell_faiman", TT.Properties.VariableNames)
    tCell = TT.T_cell_faiman;
elseif ismember("T_cell_dyn", TT.Properties.VariableNames)
    tCell = TT.T_cell_dyn;
else
    tCell = TT.T_mod;
end

% Akım tabanlı tozlanma oranı (SR_current)
if ismember("I_dc", TT.Properties.VariableNames)
    iSig = TT.I_dc;
elseif ismember("I_median", TT.Properties.VariableNames)
    iSig = TT.I_median;
elseif ismember("I_pv1", TT.Properties.VariableNames)
    iSig = TT.I_pv1;
else
    iSig = nan(height(TT), 1);
end
alphaI = 0.0005; % 1/°C kısa devre / MPP akım sıcaklık katsayısı
iCorr = iSig ./ (1 + alphaI * (tCell - 25)) ./ max(gIrr / 1000, 0.1);
mSr = m & gIrr > 250 & ~isnan(iCorr) & iCorr > 0.1;
srDay = accumarray(g, iCorr, [nd 1], @(x) medianWithMin(x, max(4, round(opts.MinSteps/2))), NaN);
srRef = prctile(srDay(~isnan(srDay)), 95);
if ~isnan(srRef) && srRef > 0
    SR_current = srDay / srRef;
else
    SR_current = PI;
end

% Günlük minimum R_iso ve günlük açıklık indeksi Kd
if ismember("R_iso", TT.Properties.VariableNames)
    R_iso_min = accumarray(g, TT.R_iso, [nd 1], @(x) minOrNaN(x), NaN);
else
    R_iso_min = nan(nd, 1);
end
lit = TT.Elevation > 5 & ~isnan(TT.G_ref) & ~isnan(TT.PoaCsRef);
Kd = accumarray(g(lit), TT.G_ref(lit), [nd 1]) ./ max(accumarray(g(lit), TT.PoaCsRef(lit), [nd 1]), 1);

% Frekans solgunluğu: 05:00-21:00 penceresinde güç ve ışınım CWT'lerinin kaba ölçek enerjisi
fading = nan(nd, 1);
if ~isempty(fb)
    hourOfDay = hours(TT.Time - day);
    win = hourOfDay >= 5 & hourOfDay < 21;
    for i = find(n >= opts.MinSteps)'
        rows = find(g == i & win);
        if numel(rows) ~= 64
            continue
        end
        p = fillmissing(TT.P_dc(rows), "linear", EndValues=0);
        gi = fillmissing(gIrr(rows), "linear", EndValues=0);
        wp = abs(wt(fb, p));
        wg = abs(wt(fb, gi));
        coarse = size(wp, 1) - opts.CoarseScales + 1:size(wp, 1);
        fading(i) = sum(wp(coarse, :), "all") / max(sum(wg(coarse, :), "all"), eps);
    end
end

T = table(dayList, PI, n, fading, expectedKwh, SR_current, R_iso_min, Kd, ...
    VariableNames=["Day" "PI" "PISteps" "Fading" "ExpectedKwh" "SR_current" "R_iso_min" "Kd"]);
end

function val = medianWithMin(x, nMin)
x = x(~isnan(x) & isfinite(x));
if numel(x) < nMin
    val = NaN;
else
    val = median(x);
end
end

function val = minOrNaN(x)
x = x(~isnan(x) & x > 0);
if isempty(x)
    val = NaN;
else
    val = min(x);
end
end
