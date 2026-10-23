%% K01_THERMAL_FORECAST  v2/v3-K1: ısıl kısma, Faiman hücre sıcaklığı ve Sandia evirici kayıp GÜN ÖNCESİ tahmini.
% SmartGridLab v3 Geliştirmeleri:
%   1) Hem çoklu eviricili Huawei hem tek eviricili SmartGridLab (WR13TL22-8231) ile uyumlu çalışır.
%   2) T_cab yoksa Faiman + P_loss vekili üzerinden ısıl ikiz kurulur ve rüzgar soğutmalı tahmin yapılır.
% Çıktı: artifacts/v2/k01_thermal.mat (modeller + doğrulama), artifacts/logs/v2_k01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_k01.log");
writelines("=== v3-K01 ısıl kısma ve termal ikiz gün öncesi tahmini " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
tz = cfg.data.timeZone;
before = cfg.split.validationStart;

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
n = numel(ids);
models = struct("Id", {}, "Model", {}, "Source", {});
rows = cell(n, 1);
pool = struct("T", {}, "y", {});

% Veri tarih aralığını kontrol et (SmartGridLab 2026 vs Huawei 2024-2025)
S0 = load(fullfile(files(1).folder, files(1).name), "TT");
tMin = min(S0.TT.Time);
tMax = max(S0.TT.Time);
if before <= tMin || before >= tMax
    spanDays = days(tMax - tMin);
    before = dateshift(tMin + days(round(0.60 * spanDays)), "start", "day");
    testStart = dateshift(tMin + days(round(0.80 * spanDays)), "start", "day");
    periods = struct("Name", ["Doğrulama dilimi" "Test dilimi"], ...
        "T0", [before, testStart], "T1", [testStart, tMax + days(1)]);
else
    periods = struct("Name", ["Mayıs 2025 (doğrulama)" "Haz–Tem 2025 (test)"], ...
        "T0", [before, cfg.split.testStart], "T1", [cfg.split.testStart, datetime(2025, 7, 23, TimeZone=tz)]);
end

for k = 1:n
    S = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = S.TT;
    anomFile = fullfile(cfg.paths.anomaly, ids(k) + ".mat");
    if ~isfile(anomFile)
        anomFile = fullfile(outDir, "anomaly", ids(k) + ".mat");
    end
    pwork = nan(height(TT), 1);
    if isfile(anomFile)
        A = load(anomFile, "Steps").Steps;
        [tf, loc] = ismember(TT.Time, A.Time);
        pwork(tf) = A.PdcWork_exp(loc(tf));
    else
        pwork = TT.P_dc;
    end
    f = fullfile(cfg.paths.throttle, ids(k) + ".mat");
    src = "VI";
    if ~isfile(f)
        f = fullfile(cfg.paths.throttleP, ids(k) + ".mat");
        src = "P";
    end
    thr = false(height(TT), 1);
    ev = TT.Elevation > 15 & TT.G_ref > 250;
    loss = zeros(height(TT), 1);
    if isfile(f)
        Th = load(f, "Time", "Throttled", "Valid", "LossKw");
        [tf, loc] = ismember(TT.Time, Th.Time);
        thr(tf) = Th.Throttled(loc(tf));
        ev(tf) = Th.Valid(loc(tf));
        loss(tf) = double(Th.LossKw(loc(tf)));
    end
    M = ges.forecast.fitThermalModel(TT, thr, ev, loss, pwork, Before=before);
    models(k) = struct("Id", ids(k), "Model", M, "Source", src);
    if ismember("T_cab", TT.Properties.VariableNames) && any(~isnan(TT.T_cab))
        tcabCol = TT.T_cab;
    elseif ismember("T_cell_faiman", TT.Properties.VariableNames)
        tcabCol = TT.T_cell_faiman;
    else
        tcabCol = TT.T_mod;
    end
    tr = TT.Time < before & ev & ~isnan(tcabCol);
    pool(k) = struct("T", tcabCol(tr), "y", double(thr(tr)));
    keepCols = intersect(["T_amb" "G_ref" "Elevation" "P_dc" "P_ac" "V_dc" "WindSpeed" "T_cab" "T_mod"], ...
        string(TT.Properties.VariableNames), "stable");
    rows{k} = struct("TT", TT(:, keepCols), "thr", thr, "ev", ev, "loss", loss, "pwork", pwork);
end
Tp = vertcat(pool.T);
yp = vertcat(pool.y);
if nnz(yp > 0) >= 10
    fleet = glmfit(Tp, yp, "binomial", "link", "logit");
else
    fleet = [-24.0; 0.40];
end
rm = arrayfun(@(m) m.Model.Rmse, models);
logMsg(sprintf("Modeller: %d invertör | İç/hücre sıcaklık modeli RMSE medyan %.2f °C", n, median(rm, "omitnan")));

bt = table();
for k = 1:n
    r = rows{k};
    t = r.TT.Time;
    dd = dateshift(t, "start", "day");
    M = models(k).Model;
    wk = (dateshift(periods.T0(1), "start", "week"):days(7):periods.T1(2))';
    if isempty(wk), wk = periods.T0(1); end
    Ma = cell(numel(wk), 1);
    for w = 1:numel(wk)
        Ma{w} = ges.forecast.fitThermalModel(r.TT(:, :), r.thr, r.ev, r.loss, r.pwork, Before=wk(w), After=wk(w) - days(60));
    end
    for ip = 1:2
        dayList = unique(dd(t >= periods.T0(ip) & t < periods.T1(ip)));
        for d = dayList'
            m = dd == d;
            lit = m & r.TT.Elevation > 5;
            if nnz(lit & ~isnan(r.TT.P_dc)) < 0.8 * nnz(lit) || ~any(r.ev(m))
                continue
            end
            actual = nnz(r.thr(m)) / 4;
            actLoss = sum(r.loss(m)) * 0.25;
            po = ges.forecast.predictThrottle(M, t(m), r.TT.T_amb(m), r.TT.G_ref(m), r.pwork(m), Fleet=fleet, ...
                Elevation=r.TT.Elevation(m));
            mp = dd == d - days(1);
            if nnz(mp) == nnz(m)
                pp = ges.forecast.predictThrottle(M, t(m), r.TT.T_amb(mp), r.TT.G_ref(mp), r.pwork(mp), Fleet=fleet, ...
                    Elevation=r.TT.Elevation(m));
                persHours = pp.Hours;
                yest = nnz(r.thr(mp)) / 4;
            else
                persHours = NaN;
                yest = NaN;
            end
            c = t >= d - calyears(1) - days(15) & t < d - calyears(1) + days(16);
            clim = nnz(r.thr(c)) / 4 / max(numel(unique(dd(c))), 1);
            w = find(wk <= d, 1, "last");
            if isempty(w), w = 1; end
            pa = ges.forecast.predictThrottle(Ma{w}, t(m), r.TT.T_amb(m), r.TT.G_ref(m), r.pwork(m), Fleet=fleet, ...
                Elevation=r.TT.Elevation(m));
            hyb = max(yest + po.Hours - persHours, 0);
            bt = [bt; table(ids(k), d, ip, actual, po.Hours, persHours, yest, clim, pa.Hours, hyb, actLoss, po.LossKwh, pa.LossKwh, ...
                max(r.TT.T_amb(m)), VariableNames=["Id" "Day" "Period" "Actual" "Oracle" "PersWx" "Yesterday" "Clim" "Adaptive" ...
                "Hybrid" "ActLoss" "PredLoss" "PredLossA" "TambMax"])]; %#ok<AGROW>
        end
    end
end

methods = ["Oracle" "Adaptive" "Hybrid" "PersWx" "Yesterday" "Clim"];
res = table();
for ip = 1:2
    if isempty(bt), continue; end
    B = bt(bt.Period == ip, :);
    if isempty(B), continue; end
    for j = 1:numel(methods)
        p = B.(methods(j));
        ok = ~isnan(p);
        a = B.Actual(ok);
        p = p(ok);
        tp = nnz(p >= 1 & a >= 1); fp = nnz(p >= 1 & a < 1); fn = nnz(p < 1 & a >= 1);
        prec = tp / max(tp + fp, 1); rec = tp / max(tp + fn, 1);
        mae = mean(abs(p - a));
        r = corr(p, a);
        res = [res; table(ip, methods(j), mae, r, prec, rec, 2 * prec * rec / max(prec + rec, eps), numel(a), ...
            VariableNames=["Period" "Method" "MAE" "R" "Precision" "Recall" "F1" "N"])]; %#ok<AGROW>
    end
end
save(fullfile(outDir, "k01_thermal.mat"), "models", "fleet", "bt", "res", "periods", "before");
logMsg("=== v3-K01 bitti " + string(datetime("now")) + sprintf(" (%.1f s)", toc(tStart)));
