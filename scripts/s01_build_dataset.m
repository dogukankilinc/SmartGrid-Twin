%% S01_BUILD_DATASET  Faz 1a: SMA Sunny Portal CSV raporlarından birleşik cihaz zaman serileri.
% SmartGridLab (BTÜ, WR13TL22-8231 1.20 kWp, Satellite Sensor) için uyarlanmış.
% Her cihazın (invertör = K01-INV01, meteoroloji = K01-METEO, tesis = K01-PLANT) verilerini
% 15 dakikalık düzenli timetable'da birleştirir ve artifacts/interim/<split>/<tür>/<Id>.mat kaydeder.
% Eğitim ve holdout havuzları AYRI klasörlere yazılır.
%
% NOT: SMA verisi tek birleşik CSV'de gelir (readSmaReport ile 3 mantıksal cihaza ayrılır).
% Veri temizleme ve kalite bayrakları Faz 1b'de (s03) eklenir.

clear;                                                  % betikler ortak çalışma alanını paylaşır
addpath(fileparts(fileparts(mfilename("fullpath"))));   % proje kökü
setupGes();
cfg = gesConfig();

% Holdout veri klasörü boş olabilir; toleranslı çalış
splits = ["train"];
roots  = [cfg.paths.rawTrain];
if isfolder(cfg.paths.rawHoldout) && ~isempty(dir(fullfile(cfg.paths.rawHoldout,"*.csv")))
    splits(end+1) = "holdout";
    roots(end+1)  = cfg.paths.rawHoldout;
end

for i = 1:numel(splits)
    registry = buildSplit(cfg, splits(i), roots(i));
    fprintf("\n[%s] %d cihaz işlendi.\n", splits(i), height(registry));
    if height(registry) > 0 && ismember("Kind", registry.Properties.VariableNames) && ...
            ismember("Cabin", registry.Properties.VariableNames)
        disp(groupsummary(registry, ["Kind" "Cabin"], {"min" "max"}, ["ValidPct" "NumGroups"]));
    end
end

function registry = buildSplit(cfg, split, root)
%BUILDSPLIT SMA birleşik CSV'leri tara, yükle ve kaydet.
catalog = ges.io.scanReports(root);
if isempty(catalog)
    warning("s01:noCatalog","[%s] Katalog boş: %s", split, root);
    registry = table();
    return
end
% Holdout cihaz filtresi (tek eviricili sistemde boş dizi — tüm veriler eğitimde)
if split == "train" && ~isempty(cfg.split.holdoutDevices)
    catalog = catalog(~ismember(catalog.Device, cfg.split.holdoutDevices), :);
end

outRoot = fullfile(cfg.paths.interim, split);
[ids, first] = unique(catalog.Id, "stable");
rows = cell(numel(ids), 1);
tStart = tic;
for k = 1:numel(ids)
    files = catalog.File(catalog.Id == ids(k));
    meta  = catalog(first(k), ["Device" "Id" "Kind" "Cabin" "Inv" "StringTag"]);
    [TT, report] = ges.io.loadDevice(files, TimeStep=cfg.data.timeStep, TimeZone=cfg.data.timeZone);
    TT.Properties.UserData = struct("Meta", table2struct(meta), "Load", report, "Split", split);
    rows{k} = ges.io.summarizeDevice(TT, meta, report);
    if height(TT) > 0
        outDir = fullfile(outRoot, meta.Kind);
        if ~isfolder(outDir); mkdir(outDir); end
        save(fullfile(outDir, ids(k) + ".mat"), "TT");
    end
    if mod(k,5) == 0 || k == numel(ids)
        fprintf("[%s] %3d/%d  %-20s  %.0f s\n", split, k, numel(ids), ids(k), toc(tStart));
    end
end
registry = struct2table(vertcat(rows{:}));
save(fullfile(outRoot, "registry.mat"), "registry");
writetable(registry, fullfile(outRoot, "registry.csv"));
writetable(registry, fullfile(outRoot, "registry.csv"));
end
