%% S04_TRAIN_EXPECTED_POWER  Faz 2: beklenen güç modeli (M1, arayüzdeki "kesikli çizgi").
% Hedef: efektif string akımı y = 1000*P_dc / V_work (ges.model.m1Features).
% Modeller (yalnızca sağlıklı eğitim adımlarıyla, < validationStart):
%   PHYS   : invertör başına y = a * G_poa * (1 + γ (T_cell_dyn - 25))   — fizik taban çizgisi
%   GBT    : global LSBoost (meteoroloji + güneş geometrisi + mevsim + parmak izi)
%   GBT+C  : GBT × invertöre özgü gölge/kalibrasyon haritası
%   MLP    : global sinir ağı (fitrnet)
%   MLP+C  : MLP × kalibrasyon haritası
% Ayrıca DC->AC dönüşüm için hem doğrusal Eta hem de Sandia 3-terimli + gerilim bağımlı
% kayıp modeli (EtaSandia) öğrenilir.

clear;
addpath(fileparts(fileparts(mfilename("fullpath"))));
setupGes();
cfg = gesConfig();
rng(42);
gamma = -0.0037;
maxTrainPerInverter = 6000;
tStart = tic;
logDir = fullfile(cfg.paths.root, "artifacts", "logs");
if ~isfolder(logDir)
    mkdir(logDir);
end
diary(fullfile(logDir, "s04_" + string(datetime("now", Format="yyyyMMdd_HHmmss")) + ".log"));

%% 1) Veri seti
oriFile = fullfile(cfg.paths.interim, "train", "orientation.mat");
hasOri = isfile(oriFile);
if hasOri
    O = load(oriFile).orientation;
end
files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
n = numel(files);
trainX = cell(n, 1);
trainY = cell(n, 1);
calib = cell(n, 1);
val = cell(n, 1);
ids = strings(n, 1);
fingerprints = table();
for k = 1:n
    S = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = S.TT(S.TT.Time < cfg.split.testStart, :);
    info = S.info;
    ids(k) = string(info.Id);
    vmean = mean(double(info.Vmppt), "omitnan");
    if isnan(vmean) || vmean <= 0, vmean = 200; end
    cab = 1;
    if isfield(info, "Cabin") && ~isempty(info.Cabin) && ~isnan(info.Cabin)
        cab = info.Cabin;
    end
    ampm = 1.0;
    if hasOri && any(O.Id == info.Id)
        o = O(O.Id == info.Id, :);
        ampm = o.AmPm(1);
        cab = o.Cabin(1);
    end
    fp = struct("AmPm", ampm, "Vmean", vmean, "Cabin", cab);
    fingerprints = [fingerprints; struct2table(fp)]; %#ok<AGROW>
    [X, y, aux] = ges.model.m1Features(TT, info, fp);

    isTrain = TT.Time < cfg.split.validationStart;
    h = find(aux.Healthy & isTrain);
    if numel(h) < 30
        h = find(aux.Healthy);
    end
    vdcCol = repmat(vmean, height(TT), 1);
    if ismember("V_dc", TT.Properties.VariableNames)
        vdcCol = fillmissing(double(TT.V_dc), "constant", vmean);
    elseif ismember("V_pv1", TT.Properties.VariableNames)
        vdcCol = fillmissing(double(TT.V_pv1), "constant", vmean);
    end
    calib{k} = struct("X", X(h,:), "y", y(h), "Elevation", TT.Elevation(h), "SunAz", TT.SunAzimuth(h), ...
        "G", X.G(h), "T_mod", X.T_mod(h), "P_dc", TT.P_dc(h), "P_ac", TT.P_ac(h), "V_dc", vdcCol(h));
    if numel(h) > maxTrainPerInverter
        h = h(sort(randperm(numel(h), maxTrainPerInverter)));
    end
    trainX{k} = X(h,:);
    trainY{k} = y(h);

    v = find(~isTrain & aux.Lit);
    if isempty(v)
        v = find(aux.Lit);
    end
    val{k} = struct("X", X(v,:), "y", y(v), "Time", TT.Time(v), "P_dc", TT.P_dc(v), ...
        "VInst", aux.VInst, "VWork", aux.VWork(v), "Healthy", aux.Healthy(v), "Sky", TT.SkyStep(v), ...
        "Elevation", TT.Elevation(v), "SunAz", TT.SunAzimuth(v), "G", X.G(v), "T_mod", X.T_mod(v), ...
        "OnGrid", TT.qOnGrid(v), "Clip", TT.qClip(v), "NumDead", TT.NumDead(v), "Capacity", info.Capacity);
end
fingerprints.Id = ids;
XT = vertcat(trainX{:});
yT = vertcat(trainY{:});
fprintf("Eğitim satırı: %d (alt örneklenmiş), %d invertör (%.0f s)\n", numel(yT), n, toc(tStart));

%% 2) Fizik taban çizgisi
physA = nan(n, 1);
for k = 1:n
    c = calib{k};
    basis = c.G .* (1 + gamma * (c.T_mod - 25));
    physA(k) = basis \ c.y;
end

%% 3) Global modeller — iki geçişli sağlam (robust) eğitim
minLeaf = min(40, max(5, floor(height(XT) / 40)));
tree = templateTree(MaxNumSplits=255, MinLeafSize=minLeaf);
gbtArgs = {"Method", "LSBoost", "NumLearningCycles", 400, "LearnRate", 0.1, "Learners", tree, ...
    "NumBins", 128, "CategoricalPredictors", "Cabin"};
gbt = fitrensemble(XT, yT, gbtArgs{:});
res = yT - predict(gbt, XT);
keep = abs(res - median(res, "omitnan")) < 5 * max(1.4826 * mad(res, 1), 1e-3);
fprintf("Sağlam eğitim: %.2f%% aykırı satır çıkarıldı\n", 100 * mean(~keep));
gbt = compact(fitrensemble(XT(keep,:), yT(keep), gbtArgs{:}));
fprintf("GBT eğitildi (%.0f s)\n", toc(tStart));

mlp = compact(fitrnet(XT(keep,:), yT(keep), LayerSizes=[64 32], Activations="relu", ...
    Standardize=true, IterationLimit=400, Lambda=1e-5, CategoricalPredictors="Cabin"));
fprintf("MLP eğitildi (%.0f s)\n", toc(tStart));

%% 4) İnvertöre özgü kalibrasyon haritaları + DC->AC verim (Doğrusal + Sandia 3-Terimli)
mapsGbt = cell(n, 1);
mapsMlp = cell(n, 1);
pdcAll = [];
pacAll = [];
vdcAll = [];
for k = 1:n
    c = calib{k};
    mapsGbt{k} = ges.model.calibrationMap(c.Elevation, c.SunAz, c.y ./ predict(gbt, c.X));
    mapsMlp{k} = ges.model.calibrationMap(c.Elevation, c.SunAz, c.y ./ predict(mlp, c.X));
    pdcAll = [pdcAll; c.P_dc]; %#ok<AGROW>
    pacAll = [pacAll; c.P_ac]; %#ok<AGROW>
    vdcAll = [vdcAll; c.V_dc]; %#ok<AGROW>
end
pMinEta = min(2.0, 0.05 * max(pdcAll, [], "omitnan"));
okEta = pdcAll > pMinEta & pacAll > 0 & ~isnan(pdcAll) & ~isnan(pacAll);
if nnz(okEta) >= 10
    eta = robustfit(pdcAll(okEta), pacAll(okEta));
else
    eta = [0; 0.9356];
end
% Sandia 3-terimli + gerilim bağımlı kayıp modeli: P_loss = c0 + c1*Pdc + c2*Pdc^2 + cV*(Vdc - Vnom)*Pdc
vNom = median(vdcAll(okEta), "omitnan");
if isnan(vNom) || vNom <= 0, vNom = 200; end
pLossObs = max(pdcAll(okEta) - pacAll(okEta), 0);
Xloss = [ones(nnz(okEta), 1), pdcAll(okEta), pdcAll(okEta).^2, (vdcAll(okEta) - vNom) .* pdcAll(okEta)];
if nnz(okEta) >= 20 && rank(Xloss) == 4
    bLoss = Xloss \ pLossObs;
else
    bLoss = [0.005; 1 - eta(2); 0.01; 0];
end
etaSandia = struct("c0", bLoss(1), "c1", bLoss(2), "c2", bLoss(3), "cV", bLoss(4), "Vnom", vNom);
fprintf("DC->AC: P_ac = %.4f + %.4f * P_dc | Sandia c0=%.4f, c1=%.4f, c2=%.4f, cV=%.5f (Vnom=%.1f V)\n", ...
    eta(1), eta(2), etaSandia.c0, etaSandia.c1, etaSandia.c2, etaSandia.cV, etaSandia.Vnom);

%% 5) Doğrulama
models = ["PHYS" "GBT" "GBT+C" "MLP" "MLP+C"];
rows = cell(n, numel(models));
skyRows = cell(n, numel(models));
predVal = cell(n, numel(models));
for k = 1:n
    v = val{k};
    if isempty(v.y)
        continue
    end
    yG = predict(gbt, v.X);
    yM = predict(mlp, v.X);
    yhat = {physA(k) * v.G .* (1 + gamma * (v.T_mod - 25)), yG, ...
        yG .* ges.model.applyCalibration(mapsGbt{k}, v.Elevation, v.SunAz), yM, ...
        yM .* ges.model.applyCalibration(mapsMlp{k}, v.Elevation, v.SunAz)};
    for m = 1:numel(models)
        pdcWork = yhat{m} .* v.VWork / 1000;
        pdcInst = yhat{m} .* v.VInst / 1000;
        predVal{k, m} = pdcInst;
        [rows{k, m}, skyRows{k, m}] = evaluate(v, pdcWork, pdcInst, ids(k), models(m));
    end
end
metrics = vertcat(rows{:});
skyMetrics = vertcat(skyRows{:});
fprintf("\n=== Doğrulama (sağlıklı adımlar) — model başına medyan / filo toplamı ===\n");
disp(groupsummary(metrics, "Model", "median", ["nMAE" "nRMSE" "nMBE" "DailyEnergyErr"]));
disp(groupsummary(metrics, "Model", "sum", ["FalseAlarmEvents" "AlarmEvents" "DeadSteps" "DeadStepsDetected"]));
if ~isempty(skyMetrics)
    fprintf("\n=== Gökyüzü sınıfına göre nMAE (medyan, %%) ===\n");
    disp(unstack(groupsummary(skyMetrics, ["Model" "Sky"], "median", "nMAE"), "median_nMAE", "Sky"));
end

%% 6) Kaydet
bundle = struct();
bundle.Version = "M1-v2";
bundle.Created = datetime("now");
bundle.Gbt = gbt;
bundle.Mlp = mlp;
bundle.PhysA = table(ids, physA, VariableNames=["Id" "A"]);
bundle.CalibrationGbt = cell2struct([cellstr(ids)'; mapsGbt'], ["Id" "Map"], 1);
bundle.CalibrationMlp = cell2struct([cellstr(ids)'; mapsMlp'], ["Id" "Map"], 1);
bundle.Eta = eta;
bundle.EtaSandia = etaSandia;
bundle.Gamma = gamma;
bundle.Fingerprints = fingerprints;
bundle.FeatureNames = string(XT.Properties.VariableNames);
bundle.TrainEnd = cfg.split.validationStart;
outDir = cfg.paths.models;
if ~isfolder(outDir)
    mkdir(outDir);
end
save(fullfile(outDir, "m1_expected_power.mat"), "bundle");
save(fullfile(outDir, "m1_validation.mat"), "metrics", "skyMetrics", "models", "ids");

%% 7) Şekil: doğrulama örnek günleri
figDir = fullfile(cfg.paths.root, "artifacts", "figures");
if ~isfolder(figDir), mkdir(figDir); end
pick = ["K02-INV03" "K02-INV25"];
if ~all(ismember(pick, ids))
    pick = ids(1:min(2, numel(ids)))';
end
fig = figure(Visible="off", Position=[50 50 1500 700]);
tl = tiledlayout(fig, numel(pick), 1, TileSpacing="compact");
for i = 1:numel(pick)
    k = find(ids == pick(i), 1);
    v = val{k};
    if isempty(v.Time), continue, end
    ax = nexttile(tl);
    tWin0 = v.Time(1);
    win = v.Time >= tWin0 & v.Time < tWin0 + days(7);
    yyaxis(ax, "left");
    plot(ax, v.Time(win), v.P_dc(win), "-", LineWidth=1.4, Color=[0.1 0.3 0.7]);
    hold(ax, "on");
    plot(ax, v.Time(win), predVal{k, 3}(win), "--", LineWidth=1.4, Color=[0.9 0.4 0.1]);
    ylabel(ax, "DC güç (kW)");
    yyaxis(ax, "right");
    plot(ax, v.Time(win), v.G(win), ":", Color=[0.5 0.5 0.5]);
    ylabel(ax, "Işınım (W/m^2)");
    legend(ax, ["Gerçek" "Beklenen (GBT+C)" "Işınım"], Location="northwest");
    title(ax, pick(i) + " — doğrulama haftası");
    grid(ax, "on");
end
exportgraphics(fig, fullfile(figDir, "f04_m1_validation_week.png"), Resolution=110);
close(fig);
fprintf("Toplam süre: %.0f s\n", toc(tStart));
diary("off");

%% ---------------------------------------------------------------------------
function [row, skyRow] = evaluate(v, pdcWork, pdcInst, id, model)
cap = v.Capacity;
h = v.Healthy & ~isnan(pdcWork);
err = pdcWork(h) - v.P_dc(h);
day = dateshift(v.Time, "start", "day");
[g, ~] = findgroups(day(h));
eAct = splitapply(@sum, v.P_dc(h), g);
ePred = splitapply(@sum, pdcWork(h), g);

valid = v.G > 150 & v.Elevation > 10 & v.OnGrid & ~v.Clip & ~isnan(pdcInst);
level = ges.anomaly.deviationLevel(v.P_dc, pdcInst, valid);
rise = [false; diff(level >= 3) == 1] | (level(1) >= 3 & (1:numel(level))' == 1);
trueIssue = v.NumDead > 0 | ~v.Healthy;
row = table(id, model, 100 * mean(abs(err), "omitnan") / cap, 100 * sqrt(mean(err.^2, "omitnan")) / cap, ...
    100 * mean(err, "omitnan") / cap, 100 * median(abs(ePred - eAct) ./ max(eAct, eps), "omitnan"), ...
    nnz(rise & ~trueIssue), nnz(rise), nnz(v.NumDead > 0 & valid), nnz(v.NumDead > 0 & valid & level >= 2), ...
    VariableNames=["Id" "Model" "nMAE" "nRMSE" "nMBE" "DailyEnergyErr" "FalseAlarmEvents" "AlarmEvents" ...
    "DeadSteps" "DeadStepsDetected"]);
skyRow = table();
for s = ["clear" "partly" "overcast"]
    m = h & v.Sky == s;
    if nnz(m) > 5
        e = pdcWork(m) - v.P_dc(m);
        skyRow = [skyRow; table(id, model, s, 100 * mean(abs(e), "omitnan") / cap, ...
            VariableNames=["Id" "Model" "Sky" "nMAE"])]; %#ok<AGROW>
    end
end
end
