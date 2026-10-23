%% M01_THREE_OPINIONS_DEV  v3-M1: üç görüş + uzlaşı — GELİŞTİRME değerlendirmesi (Mayıs 2025 doğrulama dilimi).
% Görüşler: 1) sensör ve fizik kuralları (etiketleme fonksiyonları), 2) çok etiketli görsel CNN (v2-L06; eşikleri
% Mayıs dev'inde seçildi, ağırlıkları Mayıs'ı görmedi), 3) komşu karşılaştırması (YENİ; meteoroloji sensörü ve
% M1 kullanmaz). 3. görüşün eşikleri fiziksel olarak sabitlendi (string payının %60'ı; tepe/sabah farkı 0.10);
% eğitim döneminde yalnızca sağlıklı günlerdeki yanlış alarm düzeyi kontrol edildi (sonuçlar bu günlükte).
% Bu betik kod hatalarını ve uzlaşı kuralının davranışını görmek içindir; nihai sayı v3-M2'de (test, bir kez).
% Revizyon (ilk çalıştırmanın ardından, yalnız bu geliştirme sonuçlarına bakılarak): tek görüşün sensörün "yok"
% kararına karşı iddiası saha kontrolü üretmez (iki görüş gerekir); hiçbir görüşün olmadığı gün "veri_yok".
% Komşu görüşünde tepe oranı yalnız öğleden sonra adımlarından (ısıl kısma ısı biriktikçe görülür).
% Çıktı: artifacts/logs/v3_m01.log, artifacts/v3/m01_dev.mat

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
tz = cfg.data.timeZone;
logFile = fullfile(root, "artifacts", "logs", "v3_m01.log");
writelines("=== v3-M01 üç görüş + uzlaşı (geliştirme: eğitim dönemi kontrolü + Mayıs 2025) " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
outDir = fullfile(root, "artifacts", "v3");
if ~isfolder(outDir), mkdir(outDir); end
tStart = tic;

eng = ges.runtime.ReplayEngine(cfg, datetime(2023, 12, 1, 4, 30, 0, TimeZone=tz), datetime(2025, 5, 31, 21, 0, 0, TimeZone=tz));
fleet = ges.opinions.fleetFromEngine(eng);
logMsg(sprintf("Komşu grubu: invertör başına medyan %d komşu (aynı kabin, AM/PM yönelim oranı benzer)", median(cellfun(@numel, fleet.Peers))));

%% 1) Eğitim dönemi (Oca 2024 – Nis 2025): yalnız sensör ↔ komşu (CNN bu günlerde eğitildi → dahil edilmez)
logMsg("--- Eğitim dönemi (2024-01-01 – 2025-04-30): sensör ve komşu görüşleri (CNN yok)");
Ttr = ges.opinions.dayTable(cfg, fleet, datetime(2024, 1, 1, TimeZone=tz), datetime(2025, 5, 1, TimeZone=tz));
Str = ges.opinions.reportDays(Ttr, logMsg);

%% 2) Mayıs 2025 (doğrulama dilimi): üç görüş
logMsg("--- Mayıs 2025 (doğrulama dilimi): üç görüş");
M = load(fullfile(cfg.paths.models, "cnn_ml", "resnet18_ml.mat"), "net", "thr", "classesOut", "inputSize");
M.Norm = load(fullfile(cfg.paths.models, "scalogram_norm.mat"));
Tdev = ges.opinions.dayTable(cfg, fleet, datetime(2025, 5, 1, TimeZone=tz), datetime(2025, 6, 1, TimeZone=tz), Cnn=M);
Sdev = ges.opinions.reportDays(Tdev, logMsg);

% Çekirdek mod (CNN yok) aynı günlerde: karar ne kadar değişir?
Tcore = Tdev;
none = ges.opinions.visualOpinion([], []);
for r = 1:height(Tcore)
    Tcore.C(r) = ges.opinions.consensus([Tcore.O1(r), none, Tcore.O3(r)]);
end
labF = string(arrayfun(@(c) c.Label, Tdev.C));
labK = string(arrayfun(@(c) c.Label, Tcore.C));
logMsg(sprintf("Çekirdek mod (yalnız sensör + komşular) ile tam mod aynı kararı veriyor: %%%.1f gün", 100 * mean(labF == labK)));
logMsg("--- Çekirdek mod uzlaşı istatistikleri (Mayıs 2025)");
Score = ges.opinions.reportDays(Tcore, logMsg);
Ctr = ges.opinions.compactTable(Ttr);
Cdev = ges.opinions.compactTable(Tdev);
Ccore = ges.opinions.compactTable(Tcore);
save(fullfile(outDir, "m01_dev.mat"), "Ctr", "Str", "Cdev", "Sdev", "Ccore", "Score");
logMsg(sprintf("=== v3-M01 bitti (%.1f dk)", toc(tStart) / 60));
