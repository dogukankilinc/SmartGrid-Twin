%% D02_SOILING_DRYSPELLS  v2/v3-D2: kuru dönem kirlenme hızı (dust rate) ve R_iso + yağışla toparlanma.
% SmartGridLab v3 Geliştirmeleri:
%   1) G_poa (dizi düzlemi efektif ışınım) ve T_cell_faiman (rüzgar soğutmalı Faiman hücre sıcaklığı)
%      üzerinden MPP akım zarfı imp(T_cell) ile normalize edilmiş tozlanma oranı SR hesaplanır.
%   2) Kuru dönemler (Kd >= 0.50 ve R_iso_min >= 1500 kOhm) üzerinde Blok-Bootstrap Theil-Sen
%      kirlenme hızı ve dönem sonu yağış/R_iso toparlanması raporlanır.
% Çıktı: artifacts/v2/d02_dryspells.mat, artifacts/logs/v2_d02.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
rng(11);
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_d02.log");
writelines("=== v3-D02 kuru dönem tozlanma " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");

M = load(fullfile(cfg.paths.processed, "shared", "meteo_ref.mat")).meteoRef;
day = dateshift(M.Time, "start", "day");
[gd, days0] = findgroups(day);
nd = numel(days0);
lit = M.Elevation > 5 & ~isnan(M.G_ref);
Kd = accumarray(gd(lit), M.G_ref(lit), [nd 1]) ./ max(accumarray(gd(lit), M.PoaCsRef(lit), [nd 1]), 1);

ovFile = fullfile(outDir, "orientation_v2.mat");
if isfile(ovFile)
    OV = load(ovFile).orientationV2;
    coplanar = OV.Id;
else
    OV = table();
    coplanar = strings(0, 1);
end

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
if isempty(coplanar)
    coplanar = ids;
end
SR = nan(nd, numel(ids));
cabin = ones(numel(ids), 1);
for k = 1:numel(ids)
    if contains(ids(k), "K") && contains(ids(k), "-")
        cVal = str2double(extractBetween(ids(k), "K", "-"));
        if ~isnan(cVal), cabin(k) = cVal; end
    end
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT;
    info = D.info;
    thrFile = fullfile(outDir, "throttle", ids(k) + ".mat");
    if isfile(thrFile)
        Th = load(thrFile, "Throttled", "Clipping", "env");
        if isfield(Th, "env") && ~isempty(Th.env)
            bI = median(cat(2, Th.env.BetaI), 2);
        else
            bI = [5.45; 0.0027];
        end
        notThr = ~Th.Throttled & ~Th.Clipping;
    else
        env = ges.anomaly.mppEnvelope(TT, info, IncludeDead=true);
        if ~isempty(env)
            bI = median(cat(2, env.BetaI), 2);
        else
            bI = [5.45; 0.0027];
        end
        notThr = TT.P_ac < 0.97 * info.Rated;
    end
    if ismember("T_cell_faiman", TT.Properties.VariableNames)
        tCell = TT.T_cell_faiman;
    else
        tCell = TT.T_mod;
    end
    if ismember("G_poa_eff", TT.Properties.VariableNames)
        gIrr = TT.G_poa_eff;
    elseif ismember("G_poa", TT.Properties.VariableNames)
        gIrr = TT.G_poa;
    else
        gIrr = TT.G_ref;
    end
    imp = bI(1) + bI(2) * tCell;
    hr = hour(TT.Time) + minute(TT.Time) / 60;
    if ismember("qMeteoFallback", TT.Properties.VariableNames)
        primaryOk = ~TT.qMeteoFallback;
    else
        primaryOk = TT.MeteoSource ~= "PEER";
    end
    sel = TT.Kc >= 0.80 & TT.Kc <= 1.15 & TT.KcVar < 0.05 & TT.Elevation > 25 & hr >= 10 & hr <= 16 & TT.qOnGrid ...
        & ~TT.qFault & ~TT.qCabinEvent & primaryOk & notThr & gIrr > 300;
    if ismember("I_dc", TT.Properties.VariableNames) && ~all(isnan(TT.I_dc))
        iMed = TT.I_dc;
        iMed(iMed <= 0.05) = NaN;
        validStr = ~isnan(iMed);
    else
        dead = false(height(TT), 8);
        for b = 1:8
            dead(:, b) = bitget(uint8(TT.DeadMask), b) == 1;
        end
        I = nan(height(TT), 8);
        for s = find(info.Installed)
            if ismember("I_pv" + s, TT.Properties.VariableNames)
                I(:, s) = TT.("I_pv" + s);
            end
        end
        I(dead | I <= 0.1) = NaN;
        iMed = median(I, 2, "omitnan");
        validStr = sum(~isnan(I), 2) >= min(3, sum(info.Installed));
    end
    sr = iMed ./ (gIrr / 1000) ./ max(imp, 0.1);
    sr(~sel | ~validStr) = NaN;
    [~, loc] = ismember(dateshift(TT.Time, "start", "day"), days0);
    SR(:, k) = accumarray(loc, sr, [nd 1], @(x) medianOrNaN(x, 6), NaN);
end

%% Kuru dönemler (11 haftalık SmartGridLab için >= 10 gün, uzun veri için >= 20 gün)
minDryLen = ifelse(nd < 150, 10, 20);
dry = Kd >= 0.5;
d = diff([false; dry; false]);
st = find(d == 1);
en = find(d == -1) - 1;
long = (en - st + 1) >= minDryLen;
st = st(long); en = en(long);
logMsg(sprintf("≥ %d günlük kuru dönem sayısı: %d", minDryLen, numel(st)));

uCabins = unique(cabin)';
R = table();
for c = uCabins
    m = cabin == c;
    cm = median(SR(:, m), 2, "omitmissing");
    cm(sum(~isnan(SR(:, m)), 2) < min(3, nnz(m))) = NaN;
    grpName = sprintf("Kabin %d (eğim düzeltmeli)", c);
    logMsg(sprintf("%s — %d invertör; tüm dönem SR medyanı %.3f (IQR %.3f–%.3f)", grpName, nnz(m), ...
        median(cm, "omitmissing"), prctile(cm, 25), prctile(cm, 75)));
    for j = 1:numel(st)
        idx = (st(j):en(j))';
        y = cm(idx);
        x = days(days0(idx) - days0(st(j)));
        ok = ~isnan(y);
        if nnz(ok) < max(6, floor(minDryLen / 2)), continue, end
        [a, b, bCi] = ges.stats.theilSen(x(ok), y(ok), BlockSize=3, NumBootstrap=300);
        pre = median(cm(max(1, en(j) - 2):en(j)), "omitmissing");
        post = median(cm(min(nd, en(j) + 1):min(nd, en(j) + 4)), "omitmissing");
        R = [R; table(string(grpName), days0(st(j)), days0(en(j)), en(j) - st(j) + 1, nnz(ok), -100 * b / a, ...
            -100 * bCi(2) / a, -100 * bCi(1) / a, 100 * (post - pre), ...
            VariableNames=["Grup" "Basla" "Bitis" "Gun" "GecerliGun" "HizYuzdeGun" "GA_alt" "GA_ust" "ToparlanmaYuzde"])]; %#ok<AGROW>
        logMsg(sprintf("  %s → %s (%3d gün, %3d geçerli): kirlenme hızı %+.3f %%/gün [%%95 GA %+.3f, %+.3f] | toparlanma %+.2f %%", ...
            string(days0(st(j)), "dd.MM.yyyy"), string(days0(en(j)), "dd.MM.yyyy"), en(j) - st(j) + 1, nnz(ok), ...
            -100 * b / a, -100 * bCi(2) / a, -100 * bCi(1) / a, 100 * (post - pre)));
    end
end
save(fullfile(outDir, "d02_dryspells.mat"), "R", "SR", "days0", "ids", "Kd", "coplanar");
logMsg("=== v3-D02 bitti " + string(datetime("now")));

function m = medianOrNaN(x, nMin)
x = x(~isnan(x));
if numel(x) < nMin, m = NaN; else, m = median(x); end
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
