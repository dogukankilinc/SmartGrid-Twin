%% B01_THROTTLE_SCAN  v2-B: gizli kısma (MPP dışı çalışma) ve 4-kadranlı (dV, dI) taraması.
% Yöntem: ges.anomaly.mppEnvelope (kısılmamış V/I zarfı, IRLS quantile regresyon) +
%         ges.anomaly.throttleSignatureRolling (gerilim fazlası + akım açığı → kısma; Ppot = MPP potansiyeli)
% Hem çoklu evirici filosunu hem de tek eviricili SmartGridLab (WR13TL22-8231) sistemini destekler.

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2", "throttle");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_b01.log");
writelines("=== v2-B01 gizli kısma ve 4-kadranlı MPP taraması " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tz = cfg.data.timeZone;

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");

% Veri aralığına göre dinamik ay sınırları
S0 = load(fullfile(files(1).folder, files(1).name), "TT");
tMin = dateshift(min(S0.TT.Time), "start", "month");
tMax = dateshift(max(S0.TT.Time), "start", "month") + calmonths(1);
nMo = max(1, split(between(tMin, tMax, "months"), "months"));
monthEdges = tMin + calmonths(0:nMo);

validSteps = zeros(numel(ids), nMo);
thrSteps = zeros(numel(ids), nMo);
lossMWh = zeros(numel(ids), nMo);
prodMWh = zeros(numel(ids), nMo);
tcabEdges = 25:2:76;
tcabValid = zeros(1, numel(tcabEdges) - 1);
tcabThr = zeros(1, numel(tcabEdges) - 1);
V1 = [0 0];  V2 = [0 0];  V3 = [0 0];
closure = [];
dVhist = zeros(1, 61);
dVedges = -0.10:0.005:0.20;
envAll = cell(numel(ids), 1);
noSig = strings(0, 1);
t0 = tic;

for k = 1:numel(ids)
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT;
    env = ges.anomaly.mppEnvelope(TT, D.info, IncludeDead=true);
    envAll{k} = env;
    [sig, rinfo] = ges.anomaly.throttleSignatureRolling(TT, D.info);
    if isempty(env) || rinfo.MonthsWithEnvelope == 0
        logMsg(ids(k) + ": zarf kurulamadı (PV gerilim verisi yok veya yetersiz) → kısma tespiti YAPILAMAZ");
        noSig(end+1) = ids(k); %#ok<SAGROW>
        continue
    end
    Time = TT.Time;
    Throttled = sig.Throttled;
    Valid = sig.Valid;
    dV = single(sig.dV);
    dI = single(sig.dI);
    Clipping = sig.Clipping;
    Quadrant = sig.Quadrant;
    CurrentDrop = sig.CurrentDrop;
    VoltageDrop = sig.VoltageDrop;

    pMinUn = min(1.0, 0.1 * D.info.Capacity);
    mb = discretize(Time, monthEdges);
    un = Valid & ~Throttled & ~Clipping & TT.Kc > 0.8 & TT.P_dc > pMinUn;
    ratio = TT.P_dc ./ sig.Ppot;
    kAll = median(ratio(un), "omitnan");
    if isnan(kAll) || kAll <= 0, kAll = 1.0; end
    scale = ones(height(TT), 1) * kAll;
    for m = 1:nMo
        s = un & mb == m;
        if nnz(s) >= 15
            scale(mb == m) = median(ratio(s), "omitnan");
        end
    end
    Ppot = single(sig.Ppot .* scale);
    LossKw = zeros(height(TT), 1, "single");
    LossKw(Throttled) = single(max(double(Ppot(Throttled)) - fillmissing(double(TT.P_dc(Throttled)), "constant", 0), 0));
    save(fullfile(outDir, ids(k) + ".mat"), "Time", "Throttled", "Valid", "dV", "dI", "Ppot", ...
        "LossKw", "Clipping", "Quadrant", "CurrentDrop", "VoltageDrop", "env", "scale");

    for m = 1:nMo
        s = mb == m;
        validSteps(k, m) = nnz(Valid & s);
        thrSteps(k, m) = nnz(Throttled & s);
        lossMWh(k, m) = sum(LossKw(s)) * 0.25 / 1000;
        prodMWh(k, m) = sum(max(TT.P_dc(s), 0), "omitnan") * 0.25 / 1000;
    end
    tCab = double(TT.T_mod);
    if ismember("T_cab", TT.Properties.VariableNames) && any(~isnan(TT.T_cab))
        tCab = double(TT.T_cab);
    end
    tb = discretize(tCab, tcabEdges);
    for b = 1:numel(tcabEdges) - 1
        tcabValid(b) = tcabValid(b) + nnz(Valid & tb == b);
        tcabThr(b) = tcabThr(b) + nnz(Throttled & tb == b);
    end
    derSt = Valid & TT.qDerate;
    if ismember("Status", TT.Properties.VariableNames)
        st = string(TT.Status);
        derSt = derSt | (Valid & (contains(st, "derating", IgnoreCase=true) | contains(st, "Power limit", IgnoreCase=true)));
    end
    if ismember("qPowerLimit", TT.Properties.VariableNames)
        derSt = derSt | (Valid & TT.qPowerLimit);
    end
    V1 = V1 + [nnz(derSt & Throttled), nnz(derSt)];
    winter = Valid & ismember(month(Time), [12 1 2]) & TT.Kc > 0.85;
    V2 = V2 + [nnz(winter & Throttled), nnz(winter)];
    cloudCool = Valid & TT.KcVar > 0.1 & tCab < 50;
    V3 = V3 + [nnz(cloudCool & Throttled), nnz(cloudCool)];
    r = TT.P_dc(un) ./ double(Ppot(un));
    closure = [closure; single(r(isfinite(r)))]; %#ok<AGROW>
    dVhist = dVhist + histcounts(sig.dV(Valid & ~Clipping), [dVedges Inf]);
    if mod(k, 10) == 0
        logMsg(sprintf("  %d/%d invertör (%.0f s)", k, numel(ids), toc(t0)));
    end
end

monthLabel = string(monthEdges(1:end-1), "yyyy-MM");
logMsg("");
logMsg(sprintf("KAPSAM: %d/%d invertörde imza hesaplandı; hesaplanamayan: %s", numel(ids) - numel(noSig), numel(ids), strjoin(noSig, ", ")));
logMsg("DOĞRULAMA");
logMsg(sprintf("V1 durum/sınır kısma gösteren adımlar: %d; algılayıcı yakaladı %d (%%%.1f)", V1(2), V1(1), 100 * V1(1) / max(V1(2), 1)));
logMsg(sprintf("V2 kış (Ara–Şub) açık-gök adımları: %d; kısma işaretli %d (%%%.2f)", V2(2), V2(1), 100 * V2(1) / max(V2(2), 1)));
logMsg(sprintf("V3 değişken bulutlu + serin (< 50 °C) adımlar: %d; kısma işaretli %d (%%%.2f)", V3(2), V3(1), 100 * V3(1) / max(V3(2), 1)));
if ~isempty(closure)
    logMsg(sprintf("V4 kısılmamış açık-gök adımlarda P_dc/Ppot: medyan %.3f, IQR %.3f–%.3f, %%5–95 %.3f–%.3f (n=%d)", ...
        median(closure), prctile(closure, 25), prctile(closure, 75), prctile(closure, 5), prctile(closure, 95), numel(closure)));
end
logMsg("");
logMsg("AYLIK ÖZET (geçerli gündüz adımlarında kısma oranı; kısma kaybı; DC üretim)");
for m = 1:nMo
    logMsg(sprintf("  %s  kısma %%%5.2f | kayıp %8.4f MWh | üretim %8.4f MWh | kayıp/üretim %%%4.2f", ...
        monthLabel(m), 100 * sum(thrSteps(:, m)) / max(sum(validSteps(:, m)), 1), sum(lossMWh(:, m)), sum(prodMWh(:, m)), ...
        100 * sum(lossMWh(:, m)) / max(sum(prodMWh(:, m)), eps)));
end
[~, o] = sort(sum(lossMWh, 2), "descend");
logMsg("");
logMsg("İNVERTÖR BAZINDA KISMA ÖZETİ");
for i = o(1:min(10, numel(o)))'
    logMsg(sprintf("  %s: %.4f MWh (%%%.2f), kısma oranı %%%.2f", ids(i), sum(lossMWh(i, :)), ...
        100 * sum(lossMWh(i, :)) / max(sum(prodMWh(i, :)), eps), 100 * sum(thrSteps(i, :)) / max(sum(validSteps(i, :)), 1)));
end
save(fullfile(root, "artifacts", "v2", "b01_summary.mat"), "ids", "monthEdges", "validSteps", "thrSteps", "lossMWh", "prodMWh", ...
    "tcabEdges", "tcabValid", "tcabThr", "V1", "V2", "V3", "closure", "dVhist", "dVedges", "envAll");
logMsg("=== v2-B01 bitti " + string(datetime("now")) + sprintf(" (%.0f s)", toc(t0)));
