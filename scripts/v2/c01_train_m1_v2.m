%% C01_TRAIN_M1_V2  v2-C: kısma-farkında beklenen güç modeli (M1-v2) ve v1 ile karşılaştırma.
% Değişiklik: eğitim ve invertöre özgü kalibrasyon haritaları yalnızca KISILMAMIŞ adımlardan
% (v2-B01 string V/I imzası; imzası olmayan 8 invertörde iç sıcaklık > 56 °C adımlar dışlanır).
% Değerlendirme (aynı bölme, v1 ile karşılaştırılabilir):
%   E1 doğruluk: Mayıs 2025 (doğrulama) ve Haz–Tem 2025 (ikinci bakış; v1 nihai testinde bir kez
%      kullanılmıştı) — sağlıklı + kısılmamış adımlarda nMAE (% kapasite)
%   E2 potansiyel takibi: KISILMIŞ adımlarda model beklentisi / fizik potansiyeli (Ppot, v2-B01).
%      İyi model ≈ 1 (kısılmamış güç); kısmayı öğrenmiş model < 1
%   E3 alarm: kısılmış adımların kaçında beklenen-gerçek açığı ≥ %10 (kısma görünür mü)
% Çıktılar: artifacts/models/m1_expected_power_v2eval.mat (eğitim < 2025-05-01),
%           artifacts/v2/c01_eval.mat, artifacts/logs/v2_c01.log
% Test invertörü (K02-INV21) bu betikte YÜKLENMEZ.

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
rng(42);
logFile = fullfile(root, "artifacts", "logs", "v2_c01.log");
writelines("=== v2-C01 M1-v2 " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
maxTrainPerInverter = 6000;
hotFallback = 56;                                   % °C, imzasız invertörlerde dışlama eşiği (v2-B01 doz-yanıt)
tz = cfg.data.timeZone;
evalEnd = datetime(2100, 1, 1, TimeZone=tz);          % SMA: veri sonuna kadar (test dilimi dahil, ikinci bakış)
if ~isfolder(fileparts(logFile)), mkdir(fileparts(logFile)); end
if ~isfolder(fullfile(root, "artifacts", "v2")), mkdir(fullfile(root, "artifacts", "v2")); end

v1 = load(fullfile(cfg.paths.models, "m1_expected_power.mat")).bundle;
oriFile = fullfile(cfg.paths.interim, "train", "orientation.mat");
hasOri = isfile(oriFile);
if hasOri, O = load(oriFile).orientation; end
files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
n = numel(files);
trainX = cell(n, 1); trainY = cell(n, 1); calib = cell(n, 1); evalD = cell(n, 1);
ids = strings(n, 1);
fingerprints = table();
nThr = 0; nHot = 0;
for k = 1:n
    S = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = S.TT(S.TT.Time < evalEnd, :);
    info = S.info;
    info.Id = string(info.Id);
    ids(k) = info.Id;
    thrFile = fullfile(root, "artifacts", "v2", "throttle", ids(k) + ".mat");
    hasSig = isfile(thrFile);
    if hasSig
        Th = load(thrFile, "Time", "Throttled", "Ppot", "Valid", "Clipping");
        [tf, loc] = ismember(TT.Time, Th.Time);
        TT.qThrottle = false(height(TT), 1);
        TT.qThrottle(tf) = Th.Throttled(loc(tf));
        TT.Ppot = nan(height(TT), 1);
        TT.Ppot(tf) = double(Th.Ppot(loc(tf)));
        nThr = nThr + nnz(TT.qThrottle);
    else
        tHot = nan(height(TT), 1);          % SMA: kabin sıcaklığı yoksa sıcak-yedek dışlama uygulanmaz (T_mod 56 °C normal çalışma)
        if ismember("T_cab", TT.Properties.VariableNames) && any(~isnan(TT.T_cab)), tHot = double(TT.T_cab); end
        TT.qThrottle = tHot > hotFallback & TT.Elevation > 15;
        TT.Ppot = nan(height(TT), 1);
        nHot = nHot + nnz(TT.qThrottle);
    end
    vm = mean(double(info.Vmppt), "omitnan");
    if isnan(vm) || vm <= 0, vm = 200; end
    fp = struct("AmPm", 1.0, "Vmean", vm, "Cabin", 1);
    if hasOri && any(O.Id == info.Id)
        o = O(O.Id == info.Id, :);
        fp = struct("AmPm", o.AmPm(1), "Vmean", vm, "Cabin", o.Cabin(1));
    end
    fingerprints = [fingerprints; struct2table(fp)]; %#ok<AGROW>
    [X, y, aux] = ges.model.m1Features(TT, info, fp);
    isTrain = TT.Time < cfg.split.validationStart;
    h = find(aux.Healthy & isTrain);
    calib{k} = struct("X", X(h,:), "y", y(h), "Elevation", TT.Elevation(h), "SunAz", TT.SunAzimuth(h));
    if numel(h) > maxTrainPerInverter
        h = h(sort(randperm(numel(h), maxTrainPerInverter)));
    end
    trainX{k} = X(h,:);
    trainY{k} = y(h);
    e = find(~isTrain & aux.Lit);
    % v1 tahmini (aynı öznitelikler; v1 eğitiminde kısma dışlanmamıştı)
    y1 = predict(v1.Gbt, X(e,:));
    j1 = find(string({v1.CalibrationGbt.Id}) == ids(k), 1);
    if ~isempty(j1)
        y1 = y1 .* ges.model.applyCalibration(v1.CalibrationGbt(j1).Map, TT.Elevation(e), TT.SunAzimuth(e));
    end
    evalD{k} = struct("X", X(e,:), "Time", TT.Time(e), "P_dc", TT.P_dc(e), "VInst", aux.VInst, "VWork", aux.VWork(e), ...
        "Healthy", aux.Healthy(e), "Throttled", TT.qThrottle(e), "HasSig", hasSig, "Ppot", TT.Ppot(e), ...
        "Elevation", TT.Elevation(e), "SunAz", TT.SunAzimuth(e), "G", TT.G_ref(e), "OnGrid", TT.qOnGrid(e), ...
        "Clip", TT.qClip(e), "Cap", info.Capacity, "Y1", y1);
end
fingerprints.Id = ids;
XT = vertcat(trainX{:});
yT = vertcat(trainY{:});
logMsg(sprintf("Eğitim satırı %d (alt örneklenmiş) | dışlanan kısma adımı: imzalı %d, sıcak-yedek %d (%.0f s)", ...
    numel(yT), nThr, nHot, toc(tStart)));

tree = templateTree(MaxNumSplits=255, MinLeafSize=40);
gbtArgs = {"Method", "LSBoost", "NumLearningCycles", 400, "LearnRate", 0.1, "Learners", tree, ...
    "NumBins", 128, "CategoricalPredictors", "Cabin"};
gbt = fitrensemble(XT, yT, gbtArgs{:});
res = yT - predict(gbt, XT);
keep = abs(res - median(res)) < 5 * 1.4826 * mad(res, 1);
gbt = compact(fitrensemble(XT(keep,:), yT(keep), gbtArgs{:}));
logMsg(sprintf("GBT-v2 eğitildi (%.2f%% aykırı çıkarıldı, %.0f s)", 100 * mean(~keep), toc(tStart)));
maps = cell(n, 1);
for k = 1:n
    c = calib{k};
    maps{k} = ges.model.calibrationMap(c.Elevation, c.SunAz, c.y ./ predict(gbt, c.X));
end

%% Değerlendirme
periods = struct("Ad", {"Mayıs 2025 (doğrulama)", "Haz–Tem 2025 (ikinci bakış)"}, ...
    "T0", {cfg.split.validationStart, cfg.split.testStart}, "T1", {cfg.split.testStart, evalEnd});
R = table();
for k = 1:n
    v = evalD{k};
    if isempty(v.Time), continue, end
    y2 = predict(gbt, v.X) .* ges.model.applyCalibration(maps{k}, v.Elevation, v.SunAz);
    for p = 1:numel(periods)
        s = v.Time >= periods(p).T0 & v.Time < periods(p).T1;
        if nnz(s) < 50, continue, end
        cap = v.Cap;
        h = s & v.Healthy & ~v.Throttled;
        e1 = v.Y1(h) .* v.VWork(h) / 1000 - v.P_dc(h);
        e2 = y2(h) .* v.VWork(h) / 1000 - v.P_dc(h);
        thr = s & v.Throttled & v.HasSig & ~isnan(v.Ppot) & v.Ppot > 5;
        r1 = (v.Y1(thr) .* v.VWork(thr) / 1000) ./ v.Ppot(thr);
        r2 = (y2(thr) .* v.VWork(thr) / 1000) ./ v.Ppot(thr);
        gap1 = (v.Y1(thr) .* v.VInst / 1000 - v.P_dc(thr)) ./ (v.Y1(thr) .* v.VInst / 1000);
        gap2 = (y2(thr) .* v.VInst / 1000 - v.P_dc(thr)) ./ (y2(thr) .* v.VInst / 1000);
        R = [R; table(ids(k), string(periods(p).Ad), 100 * mean(abs(e1)) / cap, 100 * mean(abs(e2)) / cap, ...
            100 * mean(e1) / cap, 100 * mean(e2) / cap, nnz(thr), median(r1), median(r2), mean(gap1 >= 0.10), mean(gap2 >= 0.10), ...
            VariableNames=["Id" "Donem" "nMAE_v1" "nMAE_v2" "nMBE_v1" "nMBE_v2" "NThr" "PotRatio_v1" "PotRatio_v2" ...
            "ThrVisible_v1" "ThrVisible_v2"])]; %#ok<AGROW>
    end
end
for p = string({periods.Ad})
    x = R(R.Donem == p, :);
    w = x.NThr;
    logMsg("");
    logMsg(p + sprintf(" — %d invertör", height(x)));
    logMsg(sprintf("  E1 nMAE (sağlıklı+kısılmamış, medyan, %d invertör): v1 %.2f %%  → v2 %.2f %% | nMBE v1 %+.2f → v2 %+.2f", ...
        nnz(~isnan(x.nMAE_v1)), median(x.nMAE_v1, "omitnan"), median(x.nMAE_v2, "omitnan"), ...
        median(x.nMBE_v1, "omitnan"), median(x.nMBE_v2, "omitnan")));
    xs = x(w >= 10, :);
    logMsg(sprintf("  E2 kısılmış adımda beklenen/potansiyel (medyan, %d invertör): v1 %.3f → v2 %.3f", height(xs), ...
        median(xs.PotRatio_v1, "omitnan"), median(xs.PotRatio_v2, "omitnan")));
    logMsg(sprintf("  E3 kısılmış adımların açığı ≥ %%10 görünen oranı (ağırlıklı): v1 %.1f %% → v2 %.1f %%", ...
        100 * sum(xs.ThrVisible_v1 .* xs.NThr) / sum(xs.NThr), 100 * sum(xs.ThrVisible_v2 .* xs.NThr) / sum(xs.NThr)));
    worst = sortrows(xs, "PotRatio_v1");
    logMsg("  Kısmayı en çok öğrenmiş v1 invertörleri (beklenen/potansiyel):");
    for i = 1:min(5, height(worst))
        logMsg(sprintf("    %s: v1 %.2f → v2 %.2f (n=%d)", worst.Id(i), worst.PotRatio_v1(i), worst.PotRatio_v2(i), worst.NThr(i)));
    end
end

bundle = v1;
bundle.Version = "M1-v2-eval";
bundle.Created = datetime("now");
bundle.Gbt = gbt;
bundle.CalibrationGbt = cell2struct([cellstr(ids)'; maps'], ["Id" "Map"], 1);
bundle.Fingerprints = fingerprints;
bundle.TrainEnd = cfg.split.validationStart;
bundle.Notes = "Eğitim ve kalibrasyon yalnızca kısılmamış adımlardan (v2-B01 V/I imzası; imzasızlarda T_cab ≤ 56 °C).";
save(fullfile(cfg.paths.models, "m1_expected_power_v2eval.mat"), "bundle");
save(fullfile(root, "artifacts", "v2", "c01_eval.mat"), "R");
logMsg("=== v2-C01 bitti " + string(datetime("now")) + sprintf(" (%.0f s)", toc(tStart)));
