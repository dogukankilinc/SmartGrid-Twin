%% E01_CLOUDINESS  v2/v3-E: bulutluluk oranı, Stein değişkenlik indeksi (VI) ve gökyüzü sınıfları.
% Tanımlar (ölçülen ışınım + mevsimsel Linke bulanıklıklı Ineichen açık gök modeli):
%   Açıklık indeksi  Kd = Σ G_ölçülen / Σ G_açıkgök (gün içi, güneş > 5°)
%   Bulutluluk oranı = 1 − Kd → bulutların kestiği ışınım payı
%   Değişkenlik indeksi VI (Stein vd. 2012) = Σ√(ΔG²+Δt²) / Σ√(ΔGcs²+Δt²), Δt = 15 dk
%   Gün sınıfı: açık (Kd ≥ 0,75 ve VI < 2,5), kapalı (Kd < 0,4), diğerleri parçalı
%   Bulut kenarı parlaması: G > 1,05 × G_açıkgök olan adımlar
% Çıktı: artifacts/v2/e01_cloudiness.mat, artifacts/logs/v2_e01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_e01.log");
writelines("=== v3-E01 bulutluluk ve gökyüzü sınıfları " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");

M = load(fullfile(cfg.paths.processed, "shared", "meteo_ref.mat")).meteoRef;
day = dateshift(M.Time, "start", "day");
[g, days0] = findgroups(day);
nd = numel(days0);
lit = M.Elevation > 5 & ~isnan(M.G_ref) & ~isnan(M.PoaCsRef);
G = M.G_ref;
Gcs = M.PoaCsRef;
Kd = accumarray(g(lit), G(lit), [nd 1]) ./ max(accumarray(g(lit), Gcs(lit), [nd 1]), 1);
cov = accumarray(g, double(lit), [nd 1]) ./ max(accumarray(g, double(M.Elevation > 5), [nd 1]), 1);
VI = nan(nd, 1);
for i = 1:nd
    r = find(g == i & lit);
    if numel(r) < 12, continue, end
    dG = diff(G(r));
    dGc = diff(Gcs(r));
    VI(i) = sum(sqrt(dG.^2 + 15^2)) / sum(sqrt(dGc.^2 + 15^2));
end
ok = cov >= 0.8 & ~isnan(VI);
sky = repmat("parçalı", nd, 1);
sky(Kd < 0.4) = "kapalı";
sky(Kd >= 0.75 & VI < 2.5) = "açık";
sky(~ok) = "veri yetersiz";
enh = lit & G > 1.05 * Gcs & M.Elevation > 20;
logMsg(sprintf("Gün sayısı %d, değerlendirilebilir %d", nd, nnz(ok)));
logMsg(sprintf("Tüm dönem: bulutluluk oranı (1−Kd) ortalaması %.1f %% | açık %d gün, parçalı %d, kapalı %d", ...
    100 * (1 - mean(Kd(ok), "omitnan")), nnz(sky == "açık"), nnz(sky == "parçalı"), nnz(sky == "kapalı")));
logMsg(sprintf("Bulut kenarı parlaması adımı (G > 1,05·Gcs, güneş > 20°): %d (gündüz adımlarının %.2f %%)", ...
    nnz(enh), 100 * nnz(enh) / max(nnz(lit & M.Elevation > 20), 1)));

mo = dateshift(days0, "start", "month");
[gm, months] = findgroups(mo);
logMsg("");
logMsg("AY        bulutluluk  açık  parçalı  kapalı  ort.VI  ışınım (kWh/m²)  açık-gök potansiyeli (kWh/m²)");
H = accumarray(g(lit), G(lit) * 0.25 / 1000, [nd 1]);
Hcs = accumarray(g(lit), Gcs(lit) * 0.25 / 1000, [nd 1]);
Mo = table();
for i = 1:numel(months)
    s = gm == i & ok;
    cl = 1 - sum(H(s)) / max(sum(Hcs(s)), eps);
    Mo = [Mo; table(months(i), cl, nnz(sky(s) == "açık"), nnz(sky(s) == "parçalı"), nnz(sky(s) == "kapalı"), ...
        mean(VI(s), "omitnan"), sum(H(gm == i)), sum(Hcs(gm == i)), ...
        VariableNames=["Month" "CloudLoss" "Clear" "Partly" "Overcast" "VI" "H" "Hcs"])]; %#ok<AGROW>
    logMsg(sprintf("%s     %5.1f %%     %3d    %3d      %3d     %.2f      %6.1f            %6.1f", string(months(i), "yyyy-MM"), ...
        100 * cl, Mo.Clear(end), Mo.Partly(end), Mo.Overcast(end), Mo.VI(end), Mo.H(end), Mo.Hcs(end)));
end
save(fullfile(outDir, "e01_cloudiness.mat"), "days0", "Kd", "VI", "sky", "cov", "Mo", "H", "Hcs");
logMsg("=== v3-E01 bitti " + string(datetime("now")));
