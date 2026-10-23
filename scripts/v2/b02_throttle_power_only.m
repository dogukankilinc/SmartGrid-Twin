%% B02_THROTTLE_POWER_ONLY  v2-B02: PV gerilimi ölçülmeyen invertörler için güç+sıcaklık kısma imzası.
% SmartGridLab (WR13TL22-8231) sisteminde V_dc ve I_dc mevcut olduğundan tüm adımlarda B01 V/I imzası
% aktiftir; bu betik V/I imzası üzerinde güç+sıcaklık kuralının çapraz doğrulamasını raporlar ve
% gerilimsiz cihaz varsa uygular.

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = cfg.paths.throttleP;
if ~isfolder(outDir), mkdir(outDir); end
logFile = fullfile(root, "artifacts", "logs", "v2_b02.log");
writelines("=== v2-B02 güç+sıcaklık kısma imzası " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;

TTH = 58;                       % °C
DELTA = 0.08;                   % beklenenin altı oranı
gridT = [54 56 58 60 62];
gridD = [0.05 0.08 0.12];

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
hasVI = arrayfun(@(i) isfile(fullfile(cfg.paths.throttle, i + ".mat")), ids);
logMsg(sprintf("V/I imzalı %d invertör (doğrulama), gerilimsiz %d invertör (uygulama): %s", nnz(hasVI), nnz(~hasVI), ...
    strjoin(ids(~hasVI), ", ")));

cnt = zeros(numel(gridT), numel(gridD), 4);
lossP = 0; lossVI = 0; lossPonTP = 0; lossVIonTP = 0;
dayTP = 0; dayFP = 0; dayFN = 0; dayTN = 0;
perInv = table();
fpWeak = 0; fpTotal = 0;
for k = find(hasVI)'
    [TT, Steps] = loadInv(cfg, ids(k));
    Th = load(fullfile(cfg.paths.throttle, ids(k) + ".mat"), "Time", "Throttled", "Valid", "LossKw");
    [tf, loc] = ismember(TT.Time, Th.Time);
    ref = false(height(TT), 1);  refValid = false(height(TT), 1);  refLoss = zeros(height(TT), 1);
    ref(tf) = Th.Throttled(loc(tf));
    refValid(tf) = Th.Valid(loc(tf));
    refLoss(tf) = double(Th.LossKw(loc(tf)));
    [base, r, expW, tCab] = ruleInputs(TT, Steps);
    cmp = base & refValid;
    for a = 1:numel(gridT)
        for b = 1:numel(gridD)
            f = cmp & tCab >= gridT(a) & r < 1 - gridD(b);
            cnt(a, b, 1) = cnt(a, b, 1) + nnz(f & ref);
            cnt(a, b, 2) = cnt(a, b, 2) + nnz(f & ~ref);
            cnt(a, b, 3) = cnt(a, b, 3) + nnz(~f & ref & cmp & tCab >= gridT(a));
            cnt(a, b, 4) = cnt(a, b, 4) + nnz(~f & ref & refValid);
        end
    end
    f = cmp & tCab >= TTH & r < 1 - DELTA;
    lP = max(expW - TT.P_dc, 0);
    lossP = lossP + sum(lP(f)) * 0.25;
    lossVI = lossVI + sum(refLoss(ref & refValid)) * 0.25;
    lossPonTP = lossPonTP + sum(lP(f & ref)) * 0.25;
    lossVIonTP = lossVIonTP + sum(refLoss(f & ref)) * 0.25;
    fpTotal = fpTotal + nnz(f & ~ref);
    fpWeak = fpWeak + nnz(f & ~ref & TT.NumWeak > 0);
    day = dateshift(TT.Time, "start", "day");
    [g, ~] = findgroups(day);
    dP = accumarray(g, double(f)) >= 4;
    dV = accumarray(g, double(ref & refValid)) >= 4;
    dEval = accumarray(g, double(cmp)) >= 8;
    dayTP = dayTP + nnz(dP & dV & dEval);
    dayFP = dayFP + nnz(dP & ~dV & dEval);
    dayFN = dayFN + nnz(~dP & dV & dEval);
    dayTN = dayTN + nnz(~dP & ~dV & dEval);
    perInv = [perInv; table(ids(k), nnz(f & ref) / max(nnz(f), 1), nnz(f & ref) / max(nnz(ref & cmp & tCab >= TTH), 1), ...
        nnz(f), VariableNames=["Id" "Precision" "RecallHot" "Flags"])]; %#ok<AGROW>
end
i0 = find(gridT == TTH);  j0 = find(gridD == DELTA);
tp = cnt(i0, j0, 1); fp = cnt(i0, j0, 2);
logMsg(sprintf("Doğrulama (%d V/I invertör), kural T ≥ %d °C, oran < %.2f: TP=%d, FP=%d", nnz(hasVI), TTH, 1 - DELTA, tp, fp));

%% Uygulama: gerilimsiz invertörler (varsa)
app = table();
for k = find(~hasVI)'
    [TT, Steps] = loadInv(cfg, ids(k));
    [base, r, expW, tCab] = ruleInputs(TT, Steps);
    Throttled = base & tCab >= TTH & r < 1 - DELTA;
    LossKw = single(max(expW - TT.P_dc, 0) .* Throttled);
    Ppot = single(expW);
    Ppot(~base) = NaN;
    Valid = base;
    Time = TT.Time;
    Source = "P";
    save(fullfile(outDir, ids(k) + ".mat"), "Time", "Throttled", "LossKw", "Ppot", "Valid", "Source", "TTH", "DELTA");
    lit = TT.Elevation > 5;
    status = TT.qDerate & lit;
    app = [app; table(ids(k), nnz(Throttled) / 4, sum(LossKw) * 0.25 / 1000, ...
        sum(TT.P_dc(lit & ~isnan(TT.P_dc))) * 0.25 / 1000, max(tCab, [], "omitmissing"), ...
        nnz(status & Throttled) / max(nnz(status), 1), nnz(status), nnz(status & base), ...
        VariableNames=["Id" "ThrottleHours" "LossMWh" "EnergyMWh" "TcabMax" "StatusCoveredByRule" "StatusSteps" "StatusStepsInBase"])]; %#ok<AGROW>
end
if ~isempty(app)
    app.LossPct = 100 * app.LossMWh ./ max(app.EnergyMWh + app.LossMWh, eps);
end
summary = struct("TTH", TTH, "DELTA", DELTA, "gridT", gridT, "gridD", gridD, "cnt", cnt, ...
    "precision", tp / max(tp + fp, 1), "recallHot", tp / max(tp + cnt(i0, j0, 3), 1), ...
    "recallAll", tp / max(tp + cnt(i0, j0, 4), 1), "day", [dayTP dayFP dayFN dayTN], ...
    "lossRatio", lossP / max(lossVI, eps), "lossRatioTP", lossPonTP / max(lossVIonTP, eps), ...
    "perInv", perInv, "applied", app);
save(fullfile(root, "artifacts", "v2", "b02_summary.mat"), "summary");
logMsg("=== v2-B02 bitti " + string(datetime("now")) + sprintf(" (%.0f s)", toc(tStart)));

%% ---------------------------------------------------------------------------
function [TT, Steps] = loadInv(cfg, id)
S = load(fullfile(cfg.paths.processed, "train", "inverter", id + ".mat"), "TT", "info");
TT = S.TT;
anomFile = fullfile(cfg.paths.anomaly, id + ".mat");
if isfile(anomFile)
    A = load(anomFile, "Steps");
    [tf, loc] = ismember(TT.Time, A.Steps.Time);
    Steps = struct("PdcWork_exp", nan(height(TT), 1));
    Steps.PdcWork_exp(tf) = A.Steps.PdcWork_exp(loc(tf));
else
    Steps = struct("PdcWork_exp", max(double(TT.G_ref) / 1000 * S.info.Capacity, 0));
end
end

function [base, r, expW, tCab] = ruleInputs(TT, Steps)
expW = double(Steps.PdcWork_exp);
tCab = double(TT.T_mod);
if ismember("T_cab", TT.Properties.VariableNames) && any(~isnan(TT.T_cab))
    tCab = double(TT.T_cab);
end
pMin = min(5.0, 0.15 * max(expW, [], "omitnan"));
base = TT.Elevation > 15 & TT.G_ref > 250 & TT.qOnGrid & ~TT.qFault & ~TT.qCabinEvent & ~TT.qClip ...
    & ~TT.qMissing & ~isnan(TT.P_dc) & TT.SkyStep == "clear" & ~isnan(tCab) & expW > pMin;
r = TT.P_dc ./ max(expW, eps);
end
