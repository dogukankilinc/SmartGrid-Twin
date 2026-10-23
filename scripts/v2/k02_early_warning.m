%% K02_EARLY_WARNING  v2/v3-K2: 4 kanallı erken uyarı geriye dönük doğrulaması (ShortDrops, R_iso, VoltageDip, EtaDrift).
% SmartGridLab v3 Geliştirmeleri:
%   1) Kanal 1 (ShortDrops) : 1–3 adımlık kısa DC/string kopmaları (MC4 konnektör / sigorta gevşekliği).
%   2) Kanal 2 (R_iso)      : Yalıtım direncinin kuru öğlede < 2000 kOhm kalması veya 7 günlük sabah R_iso düşüşü.
%   3) Kanal 3 (VoltageDip) : MPP gerilim zarfının (V_mp) %5 altına kısa süreli çökmeler (bypass diyot uyarısı).
%   4) Kanal 4 (EtaDrift)   : Sandia evirici verim modeline göre dönüşüm veriminde > %1.0 negatif kayma.
% Çıktı: artifacts/v2/k02_early_warning.mat, artifacts/logs/v2_k02.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_k02.log");
writelines("=== v3-K02 4 kanallı erken uyarı doğrulaması " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
NDROP = 2;
DECL = 0.05;

catFile = fullfile(cfg.paths.anomaly, "events_catalog.mat");
if ~isfile(catFile)
    catFile = fullfile(outDir, "events_catalog_v2.mat");
end
if isfile(catFile)
    C = load(catFile).catalog;
else
    C = table(strings(0,1), zeros(0,1), strings(0,1), zeros(0,1), zeros(0,1), NaT(0,1), NaT(0,1), zeros(0,1), zeros(0,1), false(0,1), ...
        VariableNames=["Id" "Cabin" "Type" "PV" "Severity" "Start" "End" "DurationDays" "LossKwh" "Chronic"]);
end
sd = C(C.Type == "string_dead" & C.DurationDays >= 1, :);

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
ev = table();
ctl = table();
ch4Summary = table();

for k = 1:numel(ids)
    S = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = S.TT;
    t = TT.Time;
    pvCols = intersect("I_pv" + (1:8), string(TT.Properties.VariableNames), "stable");
    if numel(pvCols) == 8
        sf = ges.prep.stringFeatures(TT{:, pvCols}, S.info.Installed);
        dead = sf.Dead;
        nrm = sf.Norm;
        visible = TT.Elevation > 10 & TT.G_ref > 400 & sf.Median > 2;
        nrm(~visible | dead) = NaN;
    else
        dead = false(height(TT), 8);
        for b = 1:8
            dead(:, b) = bitget(uint8(TT.DeadMask), b) == 1;
        end
        nrm = ones(height(TT), 8);
    end
    shortStart = false(size(dead));
    for p = 1:8
        d = diff([false; dead(:, p); false]);
        s0 = find(d == 1);
        e0 = find(d == -1) - 1;
        len = e0 - s0 + 1;
        shortStart(s0(len <= 3), p) = true;
    end
    dayIdx = dateshift(t, "start", "day");
    feat = @(p, tEnd) features(t, shortStart(:, p), nrm(:, p), tEnd);
    E = sd(sd.Id == ids(k), :);
    for e = 1:height(E)
        if E.Start(e) < t(1) + days(46) || ~S.info.Installed(max(E.PV(e), 1))
            continue
        end
        tEnd = E.Start(e) - hours(1);
        [nd, decl, cov] = feat(E.PV(e), tEnd);
        lead = NaN;
        for back = 14:-1:1
            [nd2, decl2] = feat(E.PV(e), tEnd - days(back));
            if nd2 >= NDROP || decl2 >= DECL
                lead = back;
                break
            end
        end
        if nd >= NDROP || decl >= DECL
            lead = max(lead, 0, "omitnan");
        end
        ev = [ev; table(ids(k), E.PV(e), E.Start(e), E.DurationDays(e), nd, decl, cov, lead, ...
            VariableNames=["Id" "PV" "Start" "Days" "ShortDrops" "Decline" "Coverage" "LeadDays"])]; %#ok<AGROW>
    end

    mondays = unique(dayIdx(weekday(dayIdx) == 2 & dayIdx > t(1) + days(min(46, floor(days(t(end)-t(1))/3)))));
    for p = find(S.info.Installed)
        Ep = E(E.PV == p, :);
        for m = mondays'
            if any(Ep.Start >= m & Ep.Start < m + days(14)) || any(Ep.Start < m & Ep.End > m - days(7))
                continue
            end
            [nd, decl, cov] = feat(p, m);
            if cov < 0.3
                continue
            end
            ctl = [ctl; table(ids(k), p, m, nd, decl, VariableNames=["Id" "PV" "Week" "ShortDrops" "Decline"])]; %#ok<AGROW>
        end
    end

    % 4 Kanallı SmartGridLab Erken Uyarı Taraması (ShortDrops, R_iso, VoltageDip, EtaDrift)
    nShort = nnz(shortStart);
    if ismember("R_iso", TT.Properties.VariableNames)
        nRisoWetMorning = nnz(TT.Elevation > 2 & TT.Elevation < 25 & TT.R_iso < 1500);
        nRisoDryNoonWarn = nnz(TT.Elevation > 35 & TT.G_ref > 500 & TT.R_iso < 2000);
    else
        nRisoWetMorning = 0; nRisoDryNoonWarn = 0;
    end
    if ismember("V_dc", TT.Properties.VariableNames)
        vdc = TT.V_dc;
    elseif ismember("V_pv1", TT.Properties.VariableNames)
        vdc = TT.V_pv1;
    else
        vdc = nan(height(TT), 1);
    end
    [~, ~, fOut] = ges.solar.cellTemperatureFaiman(TT.T_amb, TT.G_ref, zeros(height(TT), 1), Vdc=vdc);
    vExp = fOut.VmpStc + fOut.BetaV * (fOut.TcellDyn - 25) + fOut.CvLogG * log(max(TT.G_ref / 1000, 0.05));
    dV = (vdc - vExp) ./ max(vExp, 100);
    nVdip = nnz(TT.G_ref > 300 & TT.qOnGrid & dV < -0.05);

    okEta = TT.G_ref > 400 & TT.P_dc > 0.15 * S.info.Capacity & TT.P_ac > 0;
    eta = TT.P_ac ./ TT.P_dc;
    etaMed = median(eta(okEta), "omitnan");
    nEtaDrift = nnz(okEta & (eta - etaMed) < -0.015);
    ch4Summary = [ch4Summary; table(ids(k), nShort, nRisoWetMorning, nRisoDryNoonWarn, nVdip, nEtaDrift, ...
        VariableNames=["Id" "ShortDrops" "RisoWetMorningSteps" "RisoDryNoonWarns" "VoltageDipSteps" "EtaDriftSteps"])]; %#ok<AGROW>
end

logMsg(sprintf("4 Kanallı Erken Uyarı Özeti (%d invertör):", height(ch4Summary)));
for i = 1:min(10, height(ch4Summary))
    logMsg(sprintf("  %s: KısaKopma=%d | R_iso SabahNem=%d, ÖğleUyarı=%d | GerilimÇökmesi(dV<-5%%)=%d | VerimKayması=%d", ...
        ch4Summary.Id(i), ch4Summary.ShortDrops(i), ch4Summary.RisoWetMorningSteps(i), ...
        ch4Summary.RisoDryNoonWarns(i), ch4Summary.VoltageDipSteps(i), ch4Summary.EtaDriftSteps(i)));
end

save(fullfile(outDir, "k02_early_warning.mat"), "ev", "ctl", "ch4Summary", "NDROP", "DECL");
logMsg("=== v3-K02 bitti " + string(datetime("now")) + sprintf(" (%.1f s)", toc(tStart)));

function [nd, decl, cov] = features(t, shortStart, nrm, tEnd)
w7 = t >= tEnd - days(7) & t < tEnd;
wRef = t >= tEnd - days(45) & t < tEnd - days(15);
nd = nnz(shortStart(w7));
m7 = median(nrm(w7), "omitmissing");
mR = median(nrm(wRef), "omitmissing");
decl = 1 - m7 / mR;
if isnan(decl)
    decl = 0;
end
cov = mean(~isnan(nrm(w7)));
end
