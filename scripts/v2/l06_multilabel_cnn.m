%% L06_MULTILABEL_CNN  v2-L6: çok etiketli görsel ajan — aynı günde birden fazla sorun (ör. string arızası + ısıl kısma).
% Sorun (v2-L05): tek etiketli CNN, yazın string arızası olan günlerde invertör aynı anda kıstığı için zikzağı görüp
% "ısıl kısma" diyor (string duyarlılığı %7). Çözüm: 4 bağımsız çıkış (sigmoid) — string arızası, trip, ısıl kısma,
% şebeke/kabin olayı; hiçbiri yoksa gün sağlıklı.
% Hedefler: etiketleme fonksiyonlarının o gün tetiklenen TÜM oyları (v2-L01 Votes): dead|weak → string, trip → trip,
%   derate → ısıl kısma, grid → şebeke. Belirsiz / kullanılamaz / tozlanma günleri dışarıda.
% Veri: v2-L02 görüntüleri + (i) iki sorunun birlikte olduğu ek gerçek günler (invertör başına ≤ 30) + (ii) gerçek
%   ısıl kısma günlerine fiziksel ölü string eklenmiş sentetik örnekler (yalnızca eğitim) + L02 sentetikleri.
% Model: ResNet-18 (v2-L03 dev'de en iyi tek mimari), ImageNet ön eğitimli, sigmoid çıkış, ağırlıklı ikili çapraz entropi.
% Eşikler: her etiket için YALNIZCA dev'de F1'i en yüksek yapan eşik. Dev = v2-L03 ile aynı gruplu bölme.
% Nihai test (bir kez): workspace/test_haz_tem_2025 (görülmemiş 01.06–22.07.2025, ham dosyalardan), dev eşikleriyle.
% Çıktı: artifacts/models/cnn_ml/resnet18_ml.mat, artifacts/logs/v2_l06.log, artifacts/final/v2_multilabel_test.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
rng(31);
logFile = fullfile(root, "artifacts", "logs", "v2_l06.log");
writelines("=== v2-L06 çok etiketli CNN " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(datetime("now", Format="HH:mm:ss")) + "  " + string(m), logFile, WriteMode="append");
tStart = tic;
tags = ["string_fault" "inverter_trip" "thermal_derating" "grid_event"];
tagsTr = ["string arızası" "trip" "ısıl kısma" "şebeke/kabin"];
sroot = fullfile(root, "scalogram_v2");
norm = load(fullfile(cfg.paths.models, "scalogram_norm.mat"));
outDir = fullfile(cfg.paths.models, "cnn_ml");
if ~isfolder(outDir), mkdir(outDir); end

%% 1) Çok etiketli hedefler
labels = load(fullfile(root, "artifacts", "v2", "cnn", "day_labels_v2.mat")).labels;
labels = labels(~ismember(string(labels.Label), ["uncertain" "unusable" "soiling"]), :);
labels.Y = multiHot(labels.Votes);
L = load(fullfile(sroot, "labels.mat"));
E = load(fullfile(cfg.paths.models, "cnn_v2", "ensemble.mat")).ensemble;
devIds = E.DevIds;
key = @(T) T.Id + "|" + string(T.Day, "yyyyMMdd");
[tf, loc] = ismember(key(L.chosen), key(labels));
real = L.chosen(tf, ["File" "Id" "Day" "Split" "Capacity"]);
real.Y = labels.Y(loc(tf), :);

% (i) iki sorunun birlikte olduğu ek gerçek günler (string + ısıl kısma)
both = labels(labels.Y(:, 1) & labels.Y(:, 3) & ~ismember(key(labels), key(real)), :);
extra = table();
for i = unique(both.Id)'
    r = find(both.Id == i);
    if numel(r) > 30, r = r(round(linspace(1, numel(r), 30))); end
    extra = [extra; both(r, :)]; %#ok<AGROW>
end
extra.File = strings(height(extra), 1);
ok = false(height(extra), 1);
for i = unique(extra.Id)'
    [TT, St] = getDevice(cfg, i);
    for r = find(extra.Id == i)'
        [sig, ok(r)] = ges.scalogram.dailySignals(TT, St, extra.Capacity(r), extra.Day(r));
        if ok(r)
            rel = "ml_extra/" + extra.Split(r) + "/" + i + "/" + string(extra.Day(r), "yyyy-MM-dd") + "_rgb.png";
            d = fileparts(fullfile(sroot, rel));
            if ~isfolder(d), mkdir(d); end
            imwrite(ges.scalogram.makeImages(norm.fb, sig, norm.scale), fullfile(sroot, rel));
            extra.File(r) = rel;
        end
    end
end
extra = extra(ok, ["File" "Id" "Day" "Split" "Capacity" "Y"]);
% (ii) sentetik: gerçek ısıl kısma günlerine ölü string (yalnızca eğitim dilimi, dev invertörleri hariç)
pool = labels(labels.Split == "train" & labels.Y(:, 3) & ~any(labels.Y(:, [1 2 4]), 2) & ~ismember(labels.Id, devIds), :);
pick = pool(randperm(height(pool), min(600, height(pool))), :);
synT = table();
for i = unique(pick.Id)'
    [TT, St, info] = getDevice(cfg, i);
    for r = find(pick.Id == i)'
        [sig, okk, expN] = ges.scalogram.dailySignals(TT, St, pick.Capacity(r), pick.Day(r));
        if ~okk, continue, end
        sig = ges.scalogram.injectFault(sig, expN, "string_dead", sum(info.Installed), 1000 + r);
        rel = "synthetic_ml/" + i + "/" + string(pick.Day(r), "yyyy-MM-dd") + sprintf("_deadOnThermal_%05d_rgb.png", r);
        d = fileparts(fullfile(sroot, rel));
        if ~isfolder(d), mkdir(d); end
        imwrite(ges.scalogram.makeImages(norm.fb, sig, norm.scale), fullfile(sroot, rel));
        synT = [synT; table(rel, i, pick.Day(r), "train", [1 0 1 0], VariableNames=["File" "Id" "Day" "Split" "Y"])]; %#ok<AGROW>
    end
end
syn0 = L.synthetic(:, ["File" "Id" "Day" "Split"]);
syn0.Y = double(string(L.synthetic.Label) == tags);
trainT = [real(real.Split == "train" & ~ismember(real.Id, devIds), ["File" "Id" "Y"])
          extra(extra.Split == "train" & ~ismember(extra.Id, devIds), ["File" "Id" "Y"])
          synT(~ismember(synT.Id, devIds), ["File" "Id" "Y"])
          syn0(~ismember(syn0.Id, devIds), ["File" "Id" "Y"])];
devT = [real((real.Split == "train" & ismember(real.Id, devIds)) | real.Split == "val", ["File" "Id" "Y"])
        extra((extra.Split == "train" & ismember(extra.Id, devIds)) | extra.Split == "val", ["File" "Id" "Y"])];
logMsg(sprintf("Eğitim %d görüntü (ek iki-sorunlu gerçek %d, ölü-string-üstü-kısma sentetik %d) | dev %d", height(trainT), ...
    nnz(extra.Split == "train" & ~ismember(extra.Id, devIds)), height(synT), height(devT)));
logMsg("Pozitif sayıları (eğitim): " + strjoin(compose("%s %d", tagsTr', sum(trainT.Y, 1)'), ", ") + ...
    sprintf(" · string+kısma birlikte %d", nnz(trainT.Y(:, 1) & trainT.Y(:, 3))));
logMsg("Pozitif sayıları (dev)    : " + strjoin(compose("%s %d", tagsTr', sum(devT.Y, 1)'), ", ") + ...
    sprintf(" · string+kısma birlikte %d", nnz(devT.Y(:, 1) & devT.Y(:, 3))));

%% 2) Model ve eğitim
net = imagePretrainedNetwork("resnet18", NumClasses=numel(tags));
sm = net.Layers(arrayfun(@(l) isa(l, "nnet.cnn.layer.SoftmaxLayer"), net.Layers)).Name;
net = replaceLayer(net, sm, sigmoidLayer(Name="sigmoid"));
inputSize = net.Layers(1).InputSize;
pos = sum(trainT.Y, 1);
w = 1 ./ sqrt(max(pos, 1));
w = w / mean(w);
lossFcn = @(Yp, T) crossentropy(Yp, T, w, ClassificationMode="multilabel", WeightsFormat="C");
dsTrain = makeDs(sroot, trainT, inputSize, true);
dsDev = makeDs(sroot, devT, inputSize, false);
opts = trainingOptions("adam", InitialLearnRate=1e-4, MaxEpochs=10, MiniBatchSize=64, Shuffle="every-epoch", ...
    ValidationData=dsDev, ValidationFrequency=60, OutputNetwork="best-validation", ExecutionEnvironment="gpu", ...
    Verbose=false, Plots="none", L2Regularization=1e-4);
tT = tic;
net = trainnet(dsTrain, net, lossFcn, opts);
logMsg(sprintf("ResNet-18 çok etiketli eğitim: %.1f dk", toc(tT) / 60));

%% 3) Dev'de etiket başına eşik; tek etiketli topluluk ile karşılaştırma
Pdev = minibatchpredict(net, makeDs(sroot, devT, inputSize, false, true), ExecutionEnvironment="gpu");
thr = zeros(1, numel(tags));
for k = 1:numel(tags)
    cand = 0.1:0.05:0.9;
    f = arrayfun(@(t) f1score(Pdev(:, k) >= t, devT.Y(:, k) == 1), cand);
    [~, j] = max(f);
    thr(k) = cand(j);
end
Ydev = Pdev >= thr;
logMsg("Dev eşikleri: " + strjoin(compose("%s %.2f", tagsTr', thr'), ", "));
reportML("Dev — çok etiketli", Ydev, devT.Y == 1, tagsTr, logMsg);
% Tek etiketli topluluk karşılaştırması: topluluk dosyaları sadeleştirmede kaldırıldı (2026-10-12); sonuç v2_l06.log'da
hasEnsemble = all(arrayfun(@isfile, fullfile(cfg.paths.models, "cnn_v2", E.Models + ".mat")));
if hasEnsemble
    [S1, ~] = singleLabelOnehot(cfg, sroot, devT.File, E, tags);
    reportML("Dev — tek etiketli topluluk (karşılaştırma)", S1, devT.Y == 1, tagsTr, logMsg);
end
classesOut = tags; %#ok<NASGU>
save(fullfile(outDir, "resnet18_ml.mat"), "net", "thr", "classesOut", "inputSize", "devIds");

%% 4) Nihai test (bir kez): görülmemiş dönem, yükleme hattıyla işlenmiş veri
wsc = ges.ingest.workspaceConfig(cfg, "test_haz_tem_2025");
catalog = load(fullfile(wsc.paths.anomaly, "events_catalog.mat")).catalog;
fl = dir(fullfile(wsc.paths.processed, "train", "inverter", "K*.mat"));
testT = table();
imgs = {};
rng(5);
for k = 1:numel(fl)
    S = load(fullfile(fl(k).folder, fl(k).name), "TT", "D", "info");
    id = string(S.info.Id);
    TT = mergeThrottle(S.TT, wsc, id);
    A = load(fullfile(wsc.paths.anomaly, id + ".mat"), "Steps").Steps;
    F = ges.label.applyLabelingFunctions(ges.label.dayFeatures(TT, A, S.D, S.info, catalog(catalog.Id == id, :)));
    F = F(~ismember(string(F.Label), ["uncertain" "unusable" "soiling"]), :);
    Y = multiHot(F.Votes);
    % Seçim: tüm arızalı günler (invertör başına ≤ 30) + sağlıklı günlerden ≤ 8
    fr = find(any(Y, 2));
    if numel(fr) > 30, fr = fr(round(linspace(1, numel(fr), 30))); end
    hr = find(~any(Y, 2));
    hr = hr(randperm(numel(hr), min(8, numel(hr))));
    for r = [fr; hr]'
        [sig, okk] = ges.scalogram.dailySignals(S.TT, A, S.info.Capacity, F.Day(r));
        if okk
            imgs{end+1} = ges.scalogram.makeImages(norm.fb, sig, norm.scale); %#ok<SAGROW>
            testT = [testT; table(id, F.Day(r), Y(r, :), VariableNames=["Id" "Day" "Y"])]; %#ok<AGROW>
        end
    end
end
Xte = cat(4, imgs{:});
Pte = minibatchpredict(net, imresize(Xte, inputSize(1:2)), ExecutionEnvironment="gpu");
Yte = Pte >= thr;
ft = fullfile(root, "artifacts", "final", "v2_multilabel_test.log");
writelines("=== v2-L06 çok etiketli CNN — NİHAİ test (bir kez) " + string(datetime("now")), ft);
logT = @(m) writelines(string(m), ft, WriteMode="append");
logT(sprintf("Test: %d gün, %d invertör (K02-INV21 dahil); pozitifler: %s; string+kısma birlikte %d", height(testT), ...
    numel(unique(testT.Id)), strjoin(compose("%s %d", tagsTr', sum(testT.Y, 1)'), ", "), nnz(testT.Y(:, 1) & testT.Y(:, 3))));
reportML("Test — çok etiketli (dev eşikleri)", Yte, testT.Y == 1, tagsTr, logT);
if hasEnsemble
    S1t = singleLabelOnehot(cfg, [], Xte, E, tags);
    reportML("Test — tek etiketli topluluk (karşılaştırma)", S1t, testT.Y == 1, tagsTr, logT);
    m = testT.Y(:, 1) & testT.Y(:, 3);
    logT(sprintf("String + ısıl kısma birlikte olan %d günde string duyarlılığı: çok etiketli %%%.1f, tek etiketli %%%.1f; kısma duyarlılığı: %%%.1f / %%%.1f", ...
        nnz(m), 100 * mean(Yte(m, 1)), 100 * mean(S1t(m, 1)), 100 * mean(Yte(m, 3)), 100 * mean(S1t(m, 3))));
end
logMsg(sprintf("=== v2-L06 bitti (%.1f dk)", toc(tStart) / 60));

%% ---------------------------------------------------------------------------
function Y = multiHot(votes)
v = string(votes);
Y = double([contains(v, "dead") | contains(v, "weak"), contains(v, "trip"), contains(v, "derate"), contains(v, "grid")]);
end

function ds = makeDs(sroot, T, inputSize, augment, imagesOnly)
if nargin < 5, imagesOnly = false; end
imds = imageDatastore(fullfile(sroot, T.File));
f = @(I) {imresize(I, inputSize(1:2))};
if augment
    f = @(I) {imresize(circshift(I, randi([-6 6]), 2), inputSize(1:2))};
end
dsI = transform(imds, f);                         % hücre döndürmeli: combine görüntü ve hedefi yan yana koyar
if imagesOnly
    ds = dsI;
else
    ds = combine(dsI, arrayDatastore(single(T.Y), IterationDimension=1));
end
end

function f = f1score(p, t)
tp = nnz(p & t);
f = 2 * tp / max(nnz(p) + nnz(t), 1);
end

function reportML(name, P, T, tagsTr, logMsg)
f = arrayfun(@(k) f1score(P(:, k), T(:, k)), 1:numel(tagsTr));
rc = arrayfun(@(k) nnz(P(:, k) & T(:, k)) / max(nnz(T(:, k)), 1), 1:numel(tagsTr));
pr = arrayfun(@(k) nnz(P(:, k) & T(:, k)) / max(nnz(P(:, k)), 1), 1:numel(tagsTr));
healthyOk = mean(~any(P, 2) == ~any(T, 2));
exact = mean(all(P == T, 2));
logMsg(sprintf("%s: tam eşleşme %%%.1f · sağlıklı/sağlıksız doğruluk %%%.1f", name, 100 * exact, 100 * healthyOk));
for k = 1:numel(tagsTr)
    logMsg(sprintf("    %-15s (pozitif %4d): kesinlik %.2f · duyarlılık %.2f · F1 %.2f", tagsTr(k), nnz(T(:, k)), pr(k), rc(k), f(k)));
end
end

function [S, P] = singleLabelOnehot(cfg, sroot, src, E, tags)
% Tek etiketli v2 topluluğunun kararını çok etiketli biçime çevirir (her gün tek etiket)
sc = cell(1, numel(E.Models));
for j = 1:numel(E.Models)
    S2 = load(fullfile(cfg.paths.models, "cnn_v2", E.Models(j) + ".mat"), "net", "inputSize");
    if isempty(sroot)
        sc{j} = minibatchpredict(S2.net, imresize(src, S2.inputSize(1:2)));
    else
        sc{j} = minibatchpredict(S2.net, augmentedImageDatastore(S2.inputSize(1:2), imageDatastore(fullfile(sroot, src))));
    end
end
d = ges.model.ensembleVote(sc, E.Method, E.Weights, MinAgree=E.MinAgree);
lab = E.Classes(d);
S = string(lab(:)) == tags;
P = [];
end

function [TT, Steps, info] = getDevice(cfg, id)
S = load(fullfile(cfg.paths.processed, "train", "inverter", id + ".mat"), "TT", "info");
TT = S.TT(S.TT.Time < cfg.split.testStart, :);
info = S.info;
Steps = load(fullfile(cfg.paths.anomaly, id + ".mat"), "Steps").Steps;
Steps = Steps(Steps.Time < cfg.split.testStart, :);
end

function TT = mergeThrottle(TT, wsc, id)
TT.qThrottle = false(height(TT), 1);
TT.ThrottleLossKw = zeros(height(TT), 1);
TT.Ppot = nan(height(TT), 1);
f = fullfile(wsc.paths.throttle, id + ".mat");
if isfile(f)
    Th = load(f, "Time", "Throttled", "LossKw", "Ppot");
    [tf, loc] = ismember(TT.Time, Th.Time);
    TT.Ppot(tf) = double(Th.Ppot(loc(tf)));
else
    Th = load(fullfile(wsc.paths.throttleP, id + ".mat"), "Time", "Throttled", "LossKw");
    [tf, loc] = ismember(TT.Time, Th.Time);
end
TT.qThrottle(tf) = Th.Throttled(loc(tf));
TT.ThrottleLossKw(tf) = double(Th.LossKw(loc(tf)));
end
