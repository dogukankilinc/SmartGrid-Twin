function sig = throttleSignature(TT, info, env, opts)
%THROTTLESIGNATURE Adım adım "gizli kısma" (MPP dışı çalışma) ve 4-kadranlı (dV, dI) dizi teşhis imzası.
%   sig = ges.anomaly.throttleSignature(TT, info, env) — env: ges.anomaly.mppEnvelope çıktısı
%   Her MPPT için göreli gerilim fazlası dV = (V − Vmp)/Vmp ve göreli akım açığı
%   dI = (i − imp)/imp hesaplanır; invertör düzeyinde MPPT'lerin medyanı alınır.
%   4-Kadranlı (dV, dI) Fiziksel Teşhis Uzayı:
%     1. Kadran (Throttled)   : dV > TauV (+6%) ve dI < -TauI (-8%) (veya Voc'ye açık devre sıçraması:
%                               29.08.2026 11:30 AM V_dc=230V, I_dc=0.015A) → MPP'den Voc'ye kaçış
%     2. Kadran (CurrentDrop) : |dV| <= 0.05 ve dI <= -0.30 → paralel alt-dizi/string akım kaybı
%     3. Kadran (VoltageDrop) : dV < -0.05 ve dI > -0.15 → bypass diyot kısa devresi / modül çökmesi
%     4. Kadran (SoilingHint) : |dV| <= 0.04 ve -0.15 <= dI <= -0.04 → homojen tozlanma bandı
arguments
    TT timetable
    info (1,1) struct
    env struct
    opts.TauV (1,1) double = 0.06
    opts.TauI (1,1) double = 0.08
    opts.MinShare (1,1) double = 0.6
    opts.MinG (1,1) double = 250
    opts.MinElev (1,1) double = 15
end

n = height(TT);
nM = numel(env);
dVm = nan(n, nM);
dIm = nan(n, nM);
pPot = zeros(n, 1);
dead = false(n, 8);
if ismember("DeadMask", TT.Properties.VariableNames)
    mask = uint8(fillmissing(TT.DeadMask, "constant", 0));
    for b = 1:8
        dead(:, b) = bitget(mask, b) == 1;
    end
end

[gRef, tEff] = effectiveMeteo(TT);
g = gRef / 1000;
vars = TT.Properties.VariableNames;
hasPv8 = all(ismember("V_pv" + (1:8), vars));

for m = 1:nM
    s = env(m).Strings;
    Vs = zeros(n, numel(s));
    Is = zeros(n, numel(s));
    for k = 1:numel(s)
        vn = "V_pv" + s(k);
        in = "I_pv" + s(k);
        if hasPv8 || ismember(vn, vars)
            Vs(:, k) = double(TT.(vn));
        elseif s(k) == 1 && ismember("V_dc", vars)
            Vs(:, k) = double(TT.V_dc);
        else
            Vs(:, k) = NaN;
        end
        if hasPv8 || ismember(in, vars)
            Is(:, k) = double(TT.(in));
        elseif s(k) == 1 && ismember("I_dc", vars)
            Is(:, k) = double(TT.I_dc);
        else
            Is(:, k) = 0;
        end
    end
    Vs(Vs <= 0) = NaN;
    V = mean(Vs, 2, "omitnan");
    live = numel(s) - sum(dead(:, s), 2);
    I = sum(max(Is, 0), 2, "omitnan");
    Vmp = env(m).BetaV(1) + env(m).BetaV(2) * tEff + env(m).BetaV(3) * log(max(g, 0.05));
    imp = env(m).BetaI(1) + env(m).BetaI(2) * tEff;
    i = I ./ max(live, 1) ./ max(g, 0.01);
    ok = live > 0 & V > 80;
    dVm(ok, m) = (V(ok) - Vmp(ok)) ./ Vmp(ok);
    dIm(ok, m) = (i(ok) - imp(ok)) ./ imp(ok);
    pPot = pPot + max(live, 0) .* imp .* max(g, 0) .* Vmp / 1000;
end

rated = 1.20;
if isfield(info, "Rated") && ~isempty(info.Rated) && ~isnan(info.Rated)
    rated = info.Rated;
end
onGrid = true(n, 1);
if ismember("qOnGrid", vars)
    onGrid = TT.qOnGrid;
end
% Açık devreye sıçrayan kısma adımlarında (örn. 29.08.2026 11:30 AM V_dc=230V, I_dc=0.015A)
% gerilim bilgisini kaybetmemek için V > 80 olan gündüz adımlarını da değerlendiririz
hasDc = sum(~isnan(dVm), 2) > 0;
valid = (onGrid | hasDc) & gRef > opts.MinG & TT.Elevation > opts.MinElev & ~isnan(tEff) & hasDc;

sig.dV = median(dVm, 2, "omitnan");
sig.dI = median(dIm, 2, "omitnan");
agree = sum(dVm > opts.TauV & dIm < -opts.TauI, 2) ./ max(sum(~isnan(dVm), 2), 1);
sig.Clipping = TT.P_ac >= 0.97 * rated;
sig.Valid = valid;
sig.Throttled = valid & ~sig.Clipping & sig.dV > opts.TauV & sig.dI < -opts.TauI & agree >= opts.MinShare;

% 4-Kadranlı teşhis bayrakları (tek evirici DC tanı uzayı)
sig.CurrentDrop = valid & ~sig.Clipping & abs(sig.dV) <= 0.05 & sig.dI <= -0.30;
sig.VoltageDrop = valid & ~sig.Clipping & sig.dV < -0.05 & sig.dI > -0.15;
sig.SoilingHint = valid & ~sig.Clipping & abs(sig.dV) <= 0.04 & sig.dI >= -0.15 & sig.dI <= -0.04;
quad = zeros(n, 1, "uint8");
quad(sig.SoilingHint) = 4;
quad(sig.VoltageDrop) = 3;
quad(sig.CurrentDrop) = 2;
quad(sig.Throttled) = 1;
sig.Quadrant = quad;

sig.Ppot = pPot;
sig.Ppot(~valid) = NaN;
sig.LossKw = zeros(n, 1);
pdcActual = fillmissing(double(TT.P_dc), "constant", 0);
sig.LossKw(sig.Throttled) = max(pPot(sig.Throttled) - pdcActual(sig.Throttled), 0);
end

function [gRef, tEff] = effectiveMeteo(TT)
vars = TT.Properties.VariableNames;
if ismember("G_poa", vars) && any(~isnan(TT.G_poa))
    gRef = double(TT.G_poa);
elseif ismember("PoaCsRef", vars) && ismember("GhiCs", vars) && any(TT.GhiCs > 50)
    ratio = min(max(double(TT.PoaCsRef) ./ max(double(TT.GhiCs), 20), 0.5), 1.8);
    gRef = double(TT.G_ref) .* ratio;
else
    gRef = double(TT.G_ref);
end

vWind = zeros(height(TT), 1);
for wn = ["WindSpeed" "W_spd" "Wind"]
    if ismember(wn, vars)
        vWind = fillmissing(double(TT.(wn)), "constant", 0);
        break
    end
end

if ismember("T_cell_dyn", vars) && any(~isnan(TT.T_cell_dyn))
    tEff = double(TT.T_cell_dyn);
elseif ismember("T_amb", vars) && any(vWind > 0)
    u0 = 25.0;
    u1 = 6.84;
    tSs = double(TT.T_amb) + gRef ./ max(u0 + u1 * max(vWind, 0), 10);
    tEff = tSs;
    alpha = 0.25;
    for k = 2:numel(tEff)
        if ~isnan(tEff(k-1)) && ~isnan(tSs(k))
            tEff(k) = alpha * tEff(k-1) + (1 - alpha) * tSs(k);
        end
    end
else
    tEff = double(TT.T_mod);
end
end
