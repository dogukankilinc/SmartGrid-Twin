function env = mppEnvelope(TT, info, opts)
%MPPENVELOPE Bir invertörün MPPT girişleri için "kısılmamış" çalışma zarfını veriden öğrenir.
%   env = ges.anomaly.mppEnvelope(TT, info)
%   Fizik: MPP'de string/dizi gerilimi esas olarak hücre sıcaklığına (rüzgar soğutmalı Faiman
%   T_cell_dyn veya T_mod + rüzgar düzeltmesi) ve zayıfça dizi düzlemi ışınımının (G_poa)
%   logaritmasına bağlıdır; akım ise G_poa ile doğrusal orantılıdır.
%   İnvertör gücü kıstığında (termal derating / aktif güç sınırı) çalışma noktası MPP'den
%   Voc'ye doğru kayar: gerilim YÜKSELİR, akım DÜŞER. Bu yüzden kısılmamış çalışma,
%     - gerilimin ALT zarfı:  Vmp(T,G)  = a + b·T_eff + c·ln(G_poa/1000)  (q = QV alt quantile)
%     - akımın ÜST zarfı:     imp(T)    = d + e·T_eff  [A / string / (kW/m²)] (q = QI üst quantile)
%   ile tanımlanır (quantile regresyon, IRLS).
%   SmartGridLab tek evirici (V_dc, I_dc / V_pv1, I_pv1) ve çoklu MPPT (V_pv1..8) yapılarını
%   ortak destekler; kısa veri setlerinde (11 hafta) MinSteps eşiğini otomatik uyarlar.
arguments
    TT timetable
    info (1,1) struct
    opts.QV (1,1) double = 0.25
    opts.QI (1,1) double = 0.75
    opts.MinG (1,1) double = 250
    opts.MinElev (1,1) double = 15
    opts.MinSteps (1,1) double = 300
    opts.IncludeDead (1,1) logical = false
end

env = struct("Pair", {}, "Strings", {}, "BetaV", {}, "BetaI", {}, "N", {}, "ResidV", {}, "ResidI", {});
hasPv8 = all(ismember("V_pv" + (1:8), TT.Properties.VariableNames));
hasSingleDc = all(ismember(["V_dc" "I_dc"], TT.Properties.VariableNames)) || ...
    all(ismember(["V_pv1" "I_pv1"], TT.Properties.VariableNames));
if ~hasPv8 && ~hasSingleDc
    return
end

[gRef, tEff, vWind] = effectiveMeteo(TT);
installed = true(1, 8);
if isfield(info, "Installed") && ~isempty(info.Installed)
    installed = logical(info.Installed(:)');
    if numel(installed) < 8
        installed = [installed, false(1, 8 - numel(installed))];
    end
elseif ~hasPv8
    installed = [true, false(1, 7)];
end

rated = 1.20;
if isfield(info, "Rated") && ~isempty(info.Rated) && ~isnan(info.Rated)
    rated = info.Rated;
end
onGrid = true(height(TT), 1);
if ismember("qOnGrid", TT.Properties.VariableNames)
    onGrid = TT.qOnGrid;
end
base = onGrid & gRef > opts.MinG & TT.Elevation > opts.MinElev & ~isnan(tEff) ...
    & TT.P_ac < 0.95 * rated;
if ismember("qPowerLimit", TT.Properties.VariableNames)
    base = base & ~TT.qPowerLimit;
end
if ismember("qCabinEvent", TT.Properties.VariableNames)
    base = base & ~TT.qCabinEvent;
end

dead = false(height(TT), 8);
if ismember("DeadMask", TT.Properties.VariableNames)
    dead = deadBits(TT.DeadMask);
end

% Kısa veri setlerinde (örn. 11 haftalık SmartGridLab) MinSteps uyarlaması
minStepsEff = opts.MinSteps;
if height(TT) < 12000
    minStepsEff = min(opts.MinSteps, max(30, floor(0.15 * nnz(base))));
end

for j = 1:4
    s = (2 * j - 1):(2 * j);
    s = s(installed(s));
    if isempty(s)
        continue
    end
    [V, I] = pairSignals(TT, s, hasPv8);
    live = numel(s) - sum(dead(:, s), 2);
    vFloor = 80;
    iFloor = min(0.2, 0.05 * rated);
    if opts.IncludeDead
        use = base & live > 0 & V > vFloor & I > iFloor * live;
    else
        use = base & ~any(dead(:, s), 2) & V > vFloor & I > iFloor * numel(s);
        live = repmat(numel(s), height(TT), 1);
    end
    if nnz(use) < minStepsEff
        continue
    end
    g = gRef(use) / 1000;
    T = tEff(use);
    XV = [ones(nnz(use), 1), T, log(max(g, 0.05))];
    bV = quantreg(XV, V(use), opts.QV);
    i = I(use) ./ live(use) ./ g;                     % A / canlı string / (kW/m²)
    XI = [ones(nnz(use), 1), T];
    bI = quantreg(XI, i, opts.QI);
    rV = (V(use) - XV * bV) ./ max(XV * bV, 1);
    rI = (i - XI * bI) ./ max(XI * bI, 0.1);
    % Rüzgar hızı artığı bilgisi (varsa)
    env(end+1) = struct("Pair", j, "Strings", s, "BetaV", bV, "BetaI", bI, "N", nnz(use), ...
        "ResidV", 1.4826 * median(abs(rV(rV <= 0)), "omitnan"), ...
        "ResidI", 1.4826 * median(abs(rI(rI >= 0)), "omitnan")); %#ok<AGROW>
end
end

function [gRef, tEff, vWind] = effectiveMeteo(TT)
% Eğim düzeltmeli G_poa ve rüzgar soğutmalı dinamik Faiman hücre sıcaklığı T_cell_dyn
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
    % Dinamik Faiman hücre sıcaklığı: rüzgar soğutmasını ve 15 dk ısıl ataleti içerir
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

function [V, I] = pairSignals(TT, s, hasPv8)
vars = TT.Properties.VariableNames;
if ~hasPv8 && isscalar(s) && s == 1 && ismember("V_dc", vars) && ismember("I_dc", vars)
    V = double(TT.V_dc);
    V(V <= 0) = NaN;
    I = max(double(TT.I_dc), 0);
    return
end
Vs = zeros(height(TT), numel(s));
Is = zeros(height(TT), numel(s));
for k = 1:numel(s)
    vn = "V_pv" + s(k);
    in = "I_pv" + s(k);
    if ismember(vn, vars)
        Vs(:, k) = double(TT.(vn));
    elseif s(k) == 1 && ismember("V_dc", vars)
        Vs(:, k) = double(TT.V_dc);
    else
        Vs(:, k) = NaN;
    end
    if ismember(in, vars)
        Is(:, k) = double(TT.(in));
    elseif s(k) == 1 && ismember("I_dc", vars)
        Is(:, k) = double(TT.I_dc);
    else
        Is(:, k) = 0;
    end
end
Vs(Vs <= 0) = NaN;
V = mean(Vs, 2, "omitnan");
I = sum(max(Is, 0), 2, "omitnan");
end

function D = deadBits(mask)
mask = uint8(fillmissing(mask, "constant", 0));
D = false(numel(mask), 8);
for b = 1:8
    D(:, b) = bitget(mask, b) == 1;
end
end

function b = quantreg(X, y, q)
% Quantile regresyon: yinelemeli yeniden ağırlıklı en küçük kareler (IRLS)
b = X \ y;
for it = 1:60
    r = y - X * b;
    w = q ./ max(abs(r), 1e-6);
    w(r < 0) = (1 - q) ./ max(abs(r(r < 0)), 1e-6);
    Xw = X .* w;
    bNew = (X' * Xw) \ (Xw' * y);
    if max(abs(bNew - b)) < 1e-8 * max(1, max(abs(b)))
        b = bNew;
        break
    end
    b = bNew;
end
end
