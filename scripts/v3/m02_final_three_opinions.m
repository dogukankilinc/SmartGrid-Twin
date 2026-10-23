%% M02_FINAL_THREE_OPINIONS  v3-M2: üç görüş + uzlaşı — NİHAİ test (görülmemiş dönem, BİR KEZ çalıştırılır).
% Veri: workspace/test_haz_tem_2025 — 01.06–22.07.2025, ham CSV'lerden panelin yükleme hattıyla işlendi
% (74 invertör, test invertörü K02-INV21 dahil). Hiçbir eşik, kural veya model bu sonuçlara göre değiştirilmez.
% Görüşler v3-M01'de dondurulan haliyle: 1) sensör ve fizik kuralları, 2) çok etiketli CNN (v2-L06, dev eşikleri),
% 3) komşu karşılaştırması (bu veri setinin kendi invertörleri; meteoroloji sensörü ve M1 kullanmaz).
% Etiketlerin kendisi sensör kurallarından türediği için "doğruluk" yerine görüşler arası uyum ve özellikle
% 3. görüşün (bağımsız ölçüm zinciri) 1. görüşü TEYİT / ÇÜRÜTME oranları raporlanır.
% Çıktı: artifacts/final/v3_three_opinions_test.log, artifacts/final/v3_three_opinions_test.mat

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
base = gesConfig();
cfg = ges.ingest.workspaceConfig(base, "test_haz_tem_2025");
outDir = fullfile(root, "artifacts", "final");
logFile = fullfile(outDir, "v3_three_opinions_test.log");
assert(~isfile(logFile), "Nihai test daha önce çalıştırılmış (%s). Tekrar çalıştırılmaz.", logFile);
writelines("=== v3-M02 üç görüş + uzlaşı — NİHAİ test (bir kez) " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;

m = load(fullfile(cfg.paths.workspace, "manifest.mat")).manifest;
eng = ges.runtime.ReplayEngine(cfg, m.Start, m.End);
fleet = ges.opinions.fleetFromEngine(eng);
logMsg(sprintf("Veri seti: %d invertör, %s – %s; komşu grubu medyan %d invertör", numel(fleet.Ids), ...
    string(m.Start, "dd.MM.yyyy"), string(m.End, "dd.MM.yyyy"), median(cellfun(@numel, fleet.Peers))));
M = load(fullfile(base.paths.models, "cnn_ml", "resnet18_ml.mat"), "net", "thr", "classesOut", "inputSize");
M.Norm = load(fullfile(base.paths.models, "scalogram_norm.mat"));
t0 = dateshift(m.Start, "start", "day") + days(1);          % ilk gün eksik başlayabilir
t1 = dateshift(m.End, "start", "day");                       % son gün eksik bitebilir
T = ges.opinions.dayTable(cfg, fleet, t0, t1, Cnn=M);
logMsg(sprintf("Değerlendirilen dönem: %s – %s", string(t0, "dd.MM.yyyy"), string(t1 - days(1), "dd.MM.yyyy")));
logMsg("--- Tam mod (üç görüş)");
S = ges.opinions.reportDays(T, logMsg);

Tcore = T;
none = ges.opinions.visualOpinion([], []);
for r = 1:height(Tcore)
    Tcore.C(r) = ges.opinions.consensus([Tcore.O1(r), none, Tcore.O3(r)]);
end
labF = string(arrayfun(@(c) c.Label, T.C));
labK = string(arrayfun(@(c) c.Label, Tcore.C));
logMsg(sprintf("Çekirdek mod (sensör + komşular) tam modla aynı kararı veriyor: %%%.1f gün", 100 * mean(labF == labK)));
logMsg("--- Çekirdek mod (iki fiziksel görüş)");
Score = ges.opinions.reportDays(Tcore, logMsg);

h = T.Id == "K02-INV21";
if any(h)
    logMsg("--- Test invertörü K02-INV21 (eğitimde hiç kullanılmadı)");
    ges.opinions.reportDays(T(h, :), logMsg);
end
C = ges.opinions.compactTable(T);
Ccore = ges.opinions.compactTable(Tcore);
save(fullfile(outDir, "v3_three_opinions_test.mat"), "C", "Ccore", "S", "Score");
logMsg(sprintf("=== v3-M02 bitti (%.1f dk)", toc(tStart) / 60));
