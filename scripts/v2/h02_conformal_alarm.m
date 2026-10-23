%% H02_CONFORMAL_ALARM  v2-H2: uyumlu tahmin (split-conformal, Mondrian) ile garantili yanlış alarm eşikleri.
% Sabit %5/10/15 eşikleri hava ve kabinden bağımsızdır: bulutlu günde fazla, açık günde az hassas.
% Split-conformal: model (M1-v2, eğitim < 2025-05-01) ile kalibrasyon kümesinde (Mayıs 2025, modelin
% görmediği) uygunsuzluk skoru s = (P_beklenen_çalışan − P) / P_beklenen_çalışan; Mondrian
% kutuları = kabin × gök sınıfı (açık / parçalı / kapalı). Eşik q_α = kutudaki skorların
% ⌈(n+1)(1−α)⌉/n yüzdeliği → değiştirilebilirlik varsayımı altında sağlıklı adımda P(s > q_α) ≤ α.
% Kalibrasyon ve değerlendirme kümelerinde yalnızca SAĞLIKLI ve KISILMAMIŞ adımlar skor üretir;
% kısılmış adımlar ayrı (kısma algılayıcısı) sınıflandırılır.
% Değerlendirme (Haz–Tem 2025, ikinci bakış): (i) sağlıklı adımlarda gerçekleşen aşım oranı ≈ α mı,
% (ii) ölü string adımlarında (tüm-string beklentisine göre) yakalama oranı, (iii) sabit eşiklerle kıyas.
% Test invertörü YÜKLENMEZ. Çıktı: artifacts/v2/h02_conformal.mat, artifacts/logs/v2_h02.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
logFile = fullfile(root, "artifacts", "logs", "v2_h02.log");
writelines("=== v2-H02 conformal alarm " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tz = cfg.data.timeZone;
% SMA SmartGridLab: kalibrasyon = doğrulama dilimi (20 Eyl – 03 Eki 2026), değerlendirme = test dilimi (>= 04 Eki 2026)
cal0 = cfg.split.validationStart; cal1 = cfg.split.testStart;
tst0 = cal1; tst1 = datetime(2100, 1, 1, TimeZone=tz);
if ~isfolder(fileparts(logFile)), mkdir(fileparts(logFile)); end
if ~isfolder(fullfile(root, "artifacts", "v2")), mkdir(fullfile(root, "artifacts", "v2")); end
alphas = [0.01 0.05];

bundle = load(fullfile(cfg.paths.models, "m1_expected_power_v2eval.mat")).bundle;
fps = bundle.Fingerprints;
files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
C = table(); T = table();
for k = 1:numel(ids)
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT(D.TT.Time >= cal0 & D.TT.Time < tst1, :);
    if height(TT) < 100, continue, end
    info = D.info;
    info.Id = string(info.Id);
    f = fps(fps.Id == ids(k), :);
    if isempty(f), f = fps(1, :); end
    fp = struct("AmPm", f.AmPm, "Vmean", f.Vmean, "Cabin", f.Cabin);
    thrFile = fullfile(root, "artifacts", "v2", "throttle", ids(k) + ".mat");
    thr = false(height(TT), 1);                        % imzasız invertörlerde yedek (T_cab varsa)
    if ismember("T_cab", TT.Properties.VariableNames), thr = TT.T_cab > 56; end
    if isfile(thrFile)
        Th = load(thrFile, "Time", "Throttled");
        [tf, loc] = ismember(TT.Time, Th.Time);
        thr = false(height(TT), 1);
        thr(tf) = Th.Throttled(loc(tf));
    end
    ex = ges.anomaly.expectedPower(bundle, TT, info, fp);
    valid = TT.G_ref > 150 & TT.Elevation > 10 & TT.qOnGrid & ~TT.qClip & ~TT.qCabinEvent & ~isnan(TT.P_dc) ...
        & ~TT.qFault & ex.PdcWork > 0.05;
    healthy = valid & ~thr & TT.NumDead == 0 & TT.NumWeak == 0;
    deadSt = valid & ~thr & TT.NumDead > 0;
    sWork = (ex.PdcWork - TT.P_dc) ./ ex.PdcWork;      % sağlıklı skor (çalışan stringlere göre)
    sAll = (ex.Pdc - TT.P_dc) ./ ex.Pdc;               % tüm-string beklentisine göre (arıza yakalama)
    sky = repmat("parçalı", height(TT), 1);
    sky(TT.Kc >= 0.85 & TT.KcVar < 0.05) = "açık";
    sky(TT.Kc < 0.4) = "kapalı";
    inCal = TT.Time < cal1;
    C = [C; table(repmat(f.Cabin, nnz(healthy & inCal), 1), sky(healthy & inCal), sWork(healthy & inCal), ...
        VariableNames=["Cabin" "Sky" "S"])]; %#ok<AGROW>
    m = (healthy | deadSt) & ~inCal;
    T = [T; table(repmat(ids(k), nnz(m), 1), repmat(f.Cabin, nnz(m), 1), sky(m), sWork(m), sAll(m), deadSt(m), ...
        TT.NumDead(m), VariableNames=["Id" "Cabin" "Sky" "SWork" "SAll" "Dead" "NumDead"])]; %#ok<AGROW>
end
logMsg(sprintf("Kalibrasyon skorları (Mayıs 2025, sağlıklı+kısılmamış): %d | değerlendirme adımları (Haz–Tem): %d (ölü stringli %d)", ...
    height(C), height(T), nnz(T.Dead)));

Q = table();
for a = alphas
    for c = unique(C.Cabin)'
        for s = ["açık" "parçalı" "kapalı"]
            x = C.S(C.Cabin == c & C.Sky == s);
            x = x(~isnan(x));
            if numel(x) < 30, continue, end
            lev = min(1, ceil((numel(x) + 1) * (1 - a)) / numel(x));
            Q = [Q; table(a, c, s, quantile(x, lev), numel(x), VariableNames=["Alpha" "Cabin" "Sky" "Q" "N"])]; %#ok<AGROW>
        end
    end
end
logMsg("");
logMsg("Eşikler q_α (beklenen çalışan güce göre eksik oranı), kabin × gök sınıfı:");
for i = 1:height(Q)
    logMsg(sprintf("  α=%.2f Kabin %2d %-7s: q = %5.1f %% (n=%d)", Q.Alpha(i), Q.Cabin(i), Q.Sky(i), 100 * Q.Q(i), Q.N(i)));
end
logMsg("");
logMsg("DEĞERLENDİRME (Haz–Tem 2025; Kabin 12 verisi 23 Mayıs'ta bittiği için yok):");
for a = alphas
    q = nan(height(T), 1);
    for i = 1:height(Q)
        if Q.Alpha(i) ~= a, continue, end
        q(T.Cabin == Q.Cabin(i) & T.Sky == Q.Sky(i)) = Q.Q(i);
    end
    h = ~T.Dead & ~isnan(q);
    fa = mean(T.SWork(h) > q(h));
    det = mean(T.SAll(T.Dead & ~isnan(q)) > q(T.Dead & ~isnan(q)));
    logMsg(sprintf("  Conformal α = %.2f: sağlıklı adımda aşım (yanlış alarm) %.2f %% (hedef ≤ %.0f %%) | ölü string adımı yakalama %.1f %%", ...
        a, 100 * fa, 100 * a, 100 * det));
    for s = ["açık" "parçalı" "kapalı"]
        hs = h & T.Sky == s;
        if nnz(hs) > 30
            logMsg(sprintf("      %-7s: yanlış alarm %.2f %% (n=%d)", s, 100 * mean(T.SWork(hs) > q(hs)), nnz(hs)));
        end
    end
end
for thrFix = [0.05 0.10 0.15]
    h = ~T.Dead;
    logMsg(sprintf("  Sabit eşik %%%2.0f: sağlıklı adımda aşım %.2f %% | ölü string yakalama %.1f %% | gök sınıfına göre aşım: açık %.2f %%, parçalı %.2f %%, kapalı %.2f %%", ...
        100 * thrFix, 100 * mean(T.SWork(h) > thrFix), 100 * mean(T.SAll(T.Dead) > thrFix), ...
        100 * mean(T.SWork(h & T.Sky == "açık") > thrFix), 100 * mean(T.SWork(h & T.Sky == "parçalı") > thrFix), ...
        100 * mean(T.SWork(h & T.Sky == "kapalı") > thrFix)));
end
oneDead = T.Dead & T.NumDead == 1;
logMsg(sprintf("  Tek ölü stringli adımlarda tüm-string eksik oranı medyanı %.1f %% (n=%d) — 7 stringde teorik ~%%14", ...
    100 * median(T.SAll(oneDead), "omitnan"), nnz(oneDead)));
save(fullfile(root, "artifacts", "v2", "h02_conformal.mat"), "Q", "C", "T");
logMsg("=== v2-H02 bitti " + string(datetime("now")));
