%% L01_LABEL_DAYS_V2  v2-L1: CNN yeniden eğitimi için zayıf denetimli gün etiketleri (v2 kanıtlarıyla).
% s06'nın v2 karşılığı: kısma-farkında M1 (anomaly_v2 adımları), gizli ısıl kısma imzası (V/I, PV gerilimi
% yoksa güç+sıcaklık) ve v2 olay kataloğu ile etiketleme fonksiyonları (ges.label.*) yeniden çalışır.
% v1 etiketleri kısmayı göremediği için ısıl kısma günlerini çoğunlukla "tozlanma"/"belirsiz" diye
% etiketliyordu → CNN de öyle öğrendi. Eğitim + doğrulama dilimi (< testStart); test dilimi ve test
% invertörü okunmaz. Çıktı: artifacts/v2/cnn/day_labels_v2.mat, artifacts/logs/v2_l01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2", "cnn");
if ~isfolder(outDir), mkdir(outDir); end
logFile = fullfile(root, "artifacts", "logs", "v2_l01.log");
writelines("=== v2-L01 gün etiketleri (v2) " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;

catalog = load(fullfile(cfg.paths.anomaly, "events_catalog.mat")).catalog;
files = dir(fullfile(cfg.paths.processed, "train", "inverter", "K*.mat"));
parts = cell(numel(files), 1);
for k = 1:numel(files)
    S = load(fullfile(files(k).folder, files(k).name), "TT", "D", "info");
    id = string(S.info.Id);
    TT = S.TT(S.TT.Time < cfg.split.testStart, :);
    TT.qThrottle = false(height(TT), 1);
    TT.ThrottleLossKw = zeros(height(TT), 1);
    TT.Ppot = nan(height(TT), 1);
    f = fullfile(cfg.paths.throttle, id + ".mat");
    if isfile(f)
        Th = load(f, "Time", "Throttled", "LossKw", "Ppot");
        [tf, loc] = ismember(TT.Time, Th.Time);
        TT.Ppot(tf) = double(Th.Ppot(loc(tf)));
    else
        Th = load(fullfile(cfg.paths.throttleP, id + ".mat"), "Time", "Throttled", "LossKw");
        [tf, loc] = ismember(TT.Time, Th.Time);
    end
    TT.qThrottle(tf) = Th.Throttled(loc(tf));
    TT.ThrottleLossKw(tf) = double(Th.LossKw(loc(tf)));
    A = load(fullfile(cfg.paths.anomaly, id + ".mat"), "Steps").Steps;
    A = A(ismember(A.Time, TT.Time), :);
    F = ges.label.dayFeatures(TT, A, S.D, S.info, catalog(catalog.Id == id, :));
    F = ges.label.applyLabelingFunctions(F);
    F.Cabin = repmat(double(extractBetween(id, "K", "-")), height(F), 1);
    F.Capacity = repmat(S.info.Capacity, height(F), 1);
    parts{k} = F;
    if mod(k, 20) == 0
        logMsg(sprintf("  %d/%d (%.0f s)", k, numel(files), toc(tStart)));
    end
end
labels = vertcat(parts{:});
labels.Split = repmat("train", height(labels), 1);
labels.Split(labels.Day >= dateshift(cfg.split.validationStart, "start", "day")) = "val";
labels = movevars(labels, ["Id" "Cabin" "Day" "Split" "Label" "Detail" "L1" "Confidence" "Votes"], Before=1);
save(fullfile(outDir, "day_labels_v2.mat"), "labels");

% v1 ile karşılaştırma (aynı invertör-günler) — v1 etiketleri sadeleştirmede kaldırıldı (2026-10-12); sonuç v2_l01.log'da
v1File = fullfile(cfg.paths.processed, "train", "labels", "day_labels.mat");
if isfile(v1File)
    v1 = load(v1File).labels;
    [tf, loc] = ismember(labels.Id + string(labels.Day, "yyyyMMdd"), v1.Id + string(v1.Day, "yyyyMMdd"));
    logMsg(sprintf("v2 etiketli invertör-gün: %d (v1 ile eşleşen %d)", height(labels), nnz(tf)));
    cls = categories(labels.Label);
    logMsg("Sınıf dağılımı (v1 → v2, eşleşen günler):");
    for c = cls'
        logMsg(sprintf("  %-17s %6d → %6d", c{1}, nnz(string(v1.Label(loc(tf))) == c{1}), nnz(string(labels.Label(tf)) == c{1})));
    end
    X = labels(tf, :);
    Y = v1(loc(tf), :);
    th = string(X.Label) == "thermal_derating";
    logMsg(sprintf("v2'de ısıl kısma etiketli %d günün v1 etiketi: %s", nnz(th), ...
        strjoin(compose("%s %d", string(categories(categorical(string(Y.Label(th))))), countcats(categorical(string(Y.Label(th))))), ", ")));
    so = string(Y.Label) == "soiling";
    logMsg(sprintf("v1'de tozlanma etiketli %d günün v2 etiketi: %s", nnz(so), ...
        strjoin(compose("%s %d", string(categories(categorical(string(X.Label(so))))), countcats(categorical(string(X.Label(so))))), ", ")));
    logMsg(sprintf("v2 tozlanma etiketi alan invertör sayısı: %d; bunların sensörle aynı düzlemdeki (D02'de ölçülebilen) kısmı aşağıda", ...
        numel(unique(labels.Id(string(labels.Label) == "soiling")))));
end
D2 = load(fullfile(root, "artifacts", "v2", "d02_dryspells.mat"), "coplanar");
so2 = string(labels.Label) == "soiling";
logMsg(sprintf("  v2 tozlanma günü %d; aynı düzlemdeki invertörlerde %d (%%%.0f)", nnz(so2), nnz(so2 & ismember(labels.Id, D2.coplanar)), ...
    100 * mean(ismember(labels.Id(so2), D2.coplanar))));
logMsg("=== v2-L01 bitti " + string(datetime("now")) + sprintf(" (%.0f s)", toc(tStart)));
