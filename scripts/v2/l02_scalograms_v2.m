%% L02_SCALOGRAMS_V2  v2-L2: CNN v2 için skalogram veri seti (gerçek + sentetik), v2 etiket ve beklentiyle.
% s07 + s08'in v2 karşılığı. Farklar:
%   * Etiketler: v2-L01 (ısıl kısma V/I veya güç+sıcaklık imzasıyla; v1'de 225 gün → v2'de 12 751 gün)
%   * Mavi kanal (eksik üretim) kısma-farkında M1-v2 beklentisinden (anomaly_v2 adımları)
%   * Sınıflar: healthy, string_fault, inverter_trip, thermal_derating, grid_event. "soiling" ÇIKARILDI:
%     v2 tozlanma etiketli günlerin %65'i, fiziksel tozlanma ölçümünün (D02) ~%1 kayıp bulduğu sensörle
%     aynı düzlemdeki dizilerde %4–15 eksik gösteriyor → etiket fizikle çelişiyor, eğitime alınmaz.
%   * Yalnızca fizik-RGB (v1'de jet tüm mimarilerde daha kötüydü)
%   * Normalizasyon v1 ile aynı (artifacts/models/scalogram_norm.mat; çalışma zamanı uyumu)
% Seçim (eğitim/doğrulama; test dilimi ve test invertörü okunmaz): invertör başına üst sınır (olay boyunca
% eşit aralıkla), kabin olayında gün başına en fazla 6 invertör, sağlıklı: tüm "transient" + ay×gökyüzü tabakalı.
% Sentetik (yalnızca eğitim, az örnekli sınıflar): trip 900, ölü string 500, zayıf string 300.
% Çıktı: scalogram_v2/<split>/<Id>/<gün>_rgb.png, scalogram_v2/labels.mat (chosen, synthetic), artifacts/logs/v2_l02.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
rng(7);
logFile = fullfile(root, "artifacts", "logs", "v2_l02.log");
writelines("=== v2-L02 skalogramlar (v2) " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
classes = ["healthy" "string_fault" "inverter_trip" "thermal_derating" "grid_event"];
caps = struct("string_fault", 40, "inverter_trip", 60, "thermal_derating", 30);
gridPerCabinDay = 6;
healthyStratified = struct("train", 3000, "val", 600);
out = fullfile(root, "scalogram_v2");
norm = load(fullfile(cfg.paths.models, "scalogram_norm.mat"));

labels = load(fullfile(root, "artifacts", "v2", "cnn", "day_labels_v2.mat")).labels;
labels = labels(ismember(string(labels.Label), classes), :);
sel = false(height(labels), 1);
reason = strings(height(labels), 1);
for sp = ["train" "val"]
    inSplit = labels.Split == sp;
    for c = string(fieldnames(caps))'
        rows = find(inSplit & labels.Label == c);
        ids = unique(labels.Id(rows));
        for i = 1:numel(ids)
            r = rows(labels.Id(rows) == ids(i));
            if numel(r) > caps.(c)
                r = r(round(linspace(1, numel(r), caps.(c))));
            end
            sel(r) = true;
            reason(r) = "class_cap";
        end
    end
    rows = find(inSplit & labels.Label == "grid_event");
    g = findgroups(labels.Cabin(rows), labels.Day(rows));
    for gi = unique(g)'
        r = rows(g == gi);
        r = r(randperm(numel(r), min(numel(r), gridPerCabinDay)));
        sel(r) = true;
        reason(r) = "grid_cap";
    end
    r = find(inSplit & labels.Label == "healthy" & labels.Detail == "transient");
    sel(r) = true;
    reason(r) = "healthy_transient";
    pool = find(inSplit & labels.Label == "healthy" & labels.Detail ~= "transient");
    strata = findgroups(month(labels.Day(pool)), labels.Sky(pool));
    perStratum = ceil(healthyStratified.(sp) / max(strata));
    for s = unique(strata)'
        r = pool(strata == s);
        r = r(randperm(numel(r), min(numel(r), perStratum)));
        sel(r) = true;
        reason(r) = "healthy_stratified";
    end
end
chosen = labels(sel, :);
chosen.Selection = reason(sel);
chosen.File = strings(height(chosen), 1);
chosen.Ok = false(height(chosen), 1);
logMsg(sprintf("Seçilen gerçek invertör-gün: %d", height(chosen)));

ids = unique(chosen.Id);
for i = 1:numel(ids)
    [TT, Steps] = getDevice(cfg, ids(i));
    for r = find(chosen.Id == ids(i))'
        [sig, ok] = ges.scalogram.dailySignals(TT, Steps, chosen.Capacity(r), chosen.Day(r));
        if ~ok
            continue
        end
        rgb = ges.scalogram.makeImages(norm.fb, sig, norm.scale);
        rel = chosen.Split(r) + "/" + ids(i) + "/" + string(chosen.Day(r), "yyyy-MM-dd") + "_rgb.png";
        d = fullfile(out, chosen.Split(r), ids(i));
        if ~isfolder(d), mkdir(d); end
        imwrite(rgb, fullfile(out, rel));
        chosen.File(r) = rel;
        chosen.Ok(r) = true;
    end
    if mod(i, 20) == 0
        logMsg(sprintf("  gerçek: %d/%d invertör (%.0f s)", i, numel(ids), toc(tStart)));
    end
end
chosen = chosen(chosen.Ok, :);
chosen.Label = categorical(string(chosen.Label), classes);
logMsg("Gerçek görüntüler (bölme × sınıf):");
for sp = ["train" "val"]
    logMsg(sprintf("  %-5s %s", sp, strjoin(compose("%s %d", classes', countcats(chosen.Label(chosen.Split == sp))), ", ")));
end

%% Sentetik (yalnızca eğitim dilimi, v2 güçlü-sağlıklı açık/parçalı günler üzerine)
targets = struct("inverter_trip", 900, "string_dead", 500, "string_weak", 300);
labelOf = struct("inverter_trip", "inverter_trip", "string_dead", "string_fault", "string_weak", "string_fault");
base = labels(labels.Split == "train" & labels.Label == "healthy" & labels.Detail == "strong" & ismember(labels.Sky, ["clear" "partly"]), :);
plan = table();
for ty = string(fieldnames(targets))'
    r = randi(height(base), targets.(ty), 1);
    plan = [plan; table(base.Id(r), base.Day(r), base.Capacity(r), repmat(ty, numel(r), 1), VariableNames=["Id" "Day" "Capacity" "Fault"])]; %#ok<AGROW>
end
plan.Seed = (1:height(plan))';
rows = cell(height(plan), 1);
ids = unique(plan.Id);
for i = 1:numel(ids)
    [TT, Steps, info] = getDevice(cfg, ids(i));
    nStrings = sum(info.Installed);
    d = fullfile(out, "synthetic", ids(i));
    if ~isfolder(d), mkdir(d); end
    for r = find(plan.Id == ids(i))'
        [sig, ok, expN] = ges.scalogram.dailySignals(TT, Steps, plan.Capacity(r), plan.Day(r));
        if ~ok
            continue
        end
        sig = ges.scalogram.injectFault(sig, expN, plan.Fault(r), nStrings, plan.Seed(r));
        rgb = ges.scalogram.makeImages(norm.fb, sig, norm.scale);
        rel = "synthetic/" + ids(i) + "/" + sprintf("%s_%s_%05d_rgb.png", string(plan.Day(r), "yyyy-MM-dd"), plan.Fault(r), plan.Seed(r));
        imwrite(rgb, fullfile(out, rel));
        rows{r} = table(rel, ids(i), plan.Day(r), "train", string(labelOf.(plan.Fault(r))), "synthetic", ...
            VariableNames=["File" "Id" "Day" "Split" "Label" "LabelSource"]);
    end
end
synthetic = vertcat(rows{:});
synthetic.Label = categorical(synthetic.Label, classes);
logMsg(sprintf("Sentetik: %s", strjoin(compose("%s %d", classes', countcats(synthetic.Label)), ", ")));
save(fullfile(out, "labels.mat"), "chosen", "synthetic", "classes");
logMsg("=== v2-L02 bitti " + string(datetime("now")) + sprintf(" (%.0f s)", toc(tStart)));

function [TT, Steps, info] = getDevice(cfg, id)
% İşlenmiş veri + M1-v2 adımları (test dilimi hariç)
S = load(fullfile(cfg.paths.processed, "train", "inverter", id + ".mat"), "TT", "info");
TT = S.TT(S.TT.Time < cfg.split.testStart, :);
info = S.info;
Steps = load(fullfile(cfg.paths.anomaly, id + ".mat"), "Steps").Steps;
Steps = Steps(Steps.Time < cfg.split.testStart, :);
end
