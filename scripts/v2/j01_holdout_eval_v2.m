%% J01_HOLDOUT_EVAL_V2  v2 yöntemlerinin görülmemiş TEST diliminde (SMA SmartGridLab, K01-INV01, >= 04 Eki 2026) değerlendirmesi.
% Kural: v2 yöntem ve eşikleri (TauV = 0,06, M1-v2, conformal eşikler) eğitim/doğrulama diliminde
% DONDURULDU; bu betiğin sonuçlarına göre eşik ayarlanmaz.
% Tek eviricili sistemde "test cihazı" yoktur; test = zaman bloğu (cfg.split.testStart ve sonrası).
% Kısma algılayıcısı NEDENSEL kayan pencere kullanır (throttleSignatureRolling), tüm seri üzerinde
% çalıştırılır ve yalnızca test dilimi raporlanır. Veri: processed/holdout/inverter/*.mat varsa o, yoksa
% processed/train/inverter/*.mat içinden testStart sonrası satırlar.
% Ölçülenler:
%   K1 kısma algılayıcısı: durum kodlu kısmayı yakalama, açık-gök yanlış pozitif oranı,
%      potansiyel kapanışı (kısılmamış adımda P/Ppot), iç/modül sıcaklık doz-yanıtı, kısma kaybı
%   K2 M1 soğuk başlangıç: v1 ↔ v2 nMAE (sağlıklı + kısılmamış), kısılmış adımda beklenen/potansiyel
%   K3 conformal α = 0,05: (a) eğitim/doğrulamada kalibre edilmiş eşiklerin aktarımı,
%      (b) test diliminin ilk yarısından cihaza özgü yeniden kalibrasyon
% Çıktı: artifacts/final/v2_holdout.log, v2_holdout.mat

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "final");
if ~isfolder(outDir), mkdir(outDir); end
logFile = fullfile(outDir, "v2_holdout.log");
writelines("=== v2 TEST DİLİMİ (K01-INV01), nedensel yöntem " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");

hFiles = dir(fullfile(cfg.paths.processed, "holdout", "inverter", "*.mat"));
if ~isempty(hFiles)
    H = load(fullfile(hFiles(1).folder, hFiles(1).name), "TT", "info");
    TTall = H.TT;
else
    tFiles = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
    H = load(fullfile(tFiles(1).folder, tFiles(1).name), "TT", "info");
    TTall = H.TT;
end
info = H.info;
info.Id = string(info.Id);
TT = TTall;
isTest = TT.Time >= cfg.split.testStart;
vars = TT.Properties.VariableNames;
if ismember("Status", vars), st = string(TT.Status); else, st = repmat("", height(TT), 1); end

%% K1
[sig, rinfo] = ges.anomaly.throttleSignatureRolling(TT, info);
V = sig.Valid & isTest;
Thr = sig.Throttled;
der = V & (contains(st, "derating", IgnoreCase=true) | contains(st, "Power limit", IgnoreCase=true));
if ismember("qPowerLimit", vars), der = der | (V & TT.qPowerLimit); end
clearSky = V & TT.Kc > 0.85;
un = V & ~Thr & ~sig.Clipping & TT.Kc > 0.8;
r = TT.P_dc(un) ./ sig.Ppot(un);
logMsg(sprintf("K1 imzalı ay %d | durum kodlu/planlı kısma %d, yakalanan %.0f %% | açık-gök kısma işareti %.2f %% (n=%d)", ...
    rinfo.MonthsWithEnvelope, nnz(der), 100 * nnz(der & Thr) / max(nnz(der), 1), 100 * nnz(clearSky & Thr) / max(nnz(clearSky), 1), nnz(clearSky)));
logMsg(sprintf("   kısılmamış açık-gök adımda P/Ppot medyan %.3f (IQR %.3f–%.3f, n=%d)", median(r, "omitnan"), prctile(r, 25), prctile(r, 75), nnz(un)));
if ismember("T_cab", vars) && any(~isnan(TT.T_cab)), tc = double(TT.T_cab); else, tc = double(TT.T_mod); end
edges = 20:5:80;
b = discretize(tc, edges);
for i = 1:numel(edges) - 1
    m = V & ~sig.Clipping & b == i;
    if nnz(m) > 20
        logMsg(sprintf("   sıcaklık %d–%d °C: kısma %.1f %% (n=%d)", edges(i), edges(i + 1), 100 * mean(Thr(m)), nnz(m)));
    end
end
logMsg(sprintf("   kısma kaybı %.3f MWh = DC üretimin %.2f %%", sum(sig.LossKw(isTest), "omitnan") * 0.25 / 1000, ...
    100 * sum(sig.LossKw(isTest), "omitnan") / max(sum(max(TT.P_dc(isTest), 0), "omitnan"), eps)));

%% K2 M1 soğuk başlangıç (kalibrasyon haritası yok)
vm = mean(double(info.Vmppt), "omitnan");
if isnan(vm) || vm <= 0, vm = 200; end
fp = struct("AmPm", 1.0, "Vmean", vm, "Cabin", 1);
oriFile = fullfile(cfg.paths.interim, "train", "orientation.mat");
if isfile(oriFile)
    O = load(oriFile).orientation;
    if any(O.Id == info.Id)
        o = O(O.Id == info.Id, :);
        fp = struct("AmPm", o.AmPm(1), "Vmean", vm, "Cabin", o.Cabin(1));
    end
end
b1 = load(fullfile(cfg.paths.models, "m1_expected_power.mat")).bundle;
b2 = load(fullfile(cfg.paths.models, cfg.files.m1)).bundle;
ex1 = ges.anomaly.expectedPower(b1, TT, info, fp, UseCalibration=false);
ex2 = ges.anomaly.expectedPower(b2, TT, info, fp, UseCalibration=false);
[~, ~, aux] = ges.model.m1Features(TT, info, fp);
h = aux.Healthy & ~Thr;
cap = info.Capacity;
for p = ["tüm dönem" "test dilimi"]
    m = h;
    if p == "test dilimi", m = h & isTest; end
    e1 = ex1.PdcWork(m) - TT.P_dc(m);
    e2 = ex2.PdcWork(m) - TT.P_dc(m);
    logMsg(sprintf("K2 %s: nMAE v1 %.2f %% → v2 %.2f %% | nMBE v1 %+.2f → v2 %+.2f (n=%d)", p, 100 * mean(abs(e1)) / cap, ...
        100 * mean(abs(e2)) / cap, 100 * mean(e1) / cap, 100 * mean(e2) / cap, nnz(m)));
end
thr = Thr & isTest & sig.Ppot > 0.05;
logMsg(sprintf("   kısılmış adımda beklenen/potansiyel: v1 %.3f → v2 %.3f (n=%d)", median(ex1.PdcWork(thr) ./ sig.Ppot(thr), "omitnan"), ...
    median(ex2.PdcWork(thr) ./ sig.Ppot(thr), "omitnan"), nnz(thr)));

%% K3 conformal α = 0,05
Q = table(); qFile = fullfile(root, "artifacts", "v2", "h02_conformal.mat");
if isfile(qFile), Q = load(qFile, "Q").Q; Q = Q(Q.Alpha == 0.05, :); end
sky = repmat("parçalı", height(TT), 1);
sky(TT.Kc >= 0.85 & TT.KcVar < 0.05) = "açık";
sky(TT.Kc < 0.4) = "kapalı";
q = nan(height(TT), 1);
for i = 1:height(Q)
    q(sky == Q.Sky(i)) = Q.Q(i);
end
validW = TT.G_ref > 150 & TT.Elevation > 10 & TT.qOnGrid & ~TT.qClip & ~TT.qCabinEvent & ~isnan(TT.P_dc) ...
    & ~TT.qFault & ex2.PdcWork > 0.05 & ~Thr & TT.NumWeak == 0;
sW = (ex2.PdcWork - TT.P_dc) ./ ex2.PdcWork;
sA = (ex2.Pdc - TT.P_dc) ./ ex2.Pdc;
tMid = cfg.split.testStart + (max(TT.Time) - cfg.split.testStart) / 2;
warm1 = isTest & TT.Time < tMid;
hEv = validW & isTest & ~warm1;
deadEv = hEv & TT.NumDead > 0;
logMsg(sprintf("K3a doğrulamada kalibre eşikler (aktarım): aşım %.2f %% (n=%d) | ölü string adımı yakalama %.1f %% (n=%d)", ...
    100 * mean(sW(hEv) > q(hEv), "omitnan"), nnz(hEv), 100 * mean(sA(deadEv) > q(deadEv), "omitnan"), nnz(deadEv)));
qd = nan(height(TT), 1);
for s = ["açık" "parçalı" "kapalı"]
    x = sW(validW & warm1 & sky == s);
    x = x(~isnan(x));
    if numel(x) >= 30
        qd(sky == s) = quantile(x, min(1, ceil((numel(x) + 1) * 0.95) / numel(x)));
    end
end
logMsg(sprintf("K3b cihaza özgü (test dilimi ilk yarısı): aşım %.2f %% (n=%d) | ölü string adımı yakalama %.1f %% (n=%d) | sabit %%10: aşım %.2f %%, yakalama %.1f %%", ...
    100 * mean(sW(hEv) > qd(hEv), "omitnan"), nnz(hEv), 100 * mean(sA(deadEv) > qd(deadEv), "omitnan"), nnz(deadEv), ...
    100 * mean(sW(hEv) > 0.10), 100 * mean(sA(deadEv) > 0.10)));
save(fullfile(outDir, "v2_holdout.mat"), "sig", "rinfo");
logMsg("=== bitti " + string(datetime("now")));
