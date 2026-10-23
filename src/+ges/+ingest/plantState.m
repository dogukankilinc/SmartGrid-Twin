function S = plantState(cfg)
%PLANTSTATE Eğitimde öğrenilen ve sahaya taşınan "model durumu" (yeni veri işlenirken yeniden FIT EDİLMEZ).
%   SmartGridLab (K01-INV01 / K01-METEO) ve çoklu-kabin yapılarını destekler.

persistent cache
if ~isempty(cache) && cache.Root == cfg.paths.root
    S = cache.S;
    return
end
base = fullfile(cfg.paths.root, "artifacts", "processed");
oriFile = fullfile(cfg.paths.root, "artifacts", "interim", "train", "orientation.mat");
if isfile(oriFile)
    O = load(oriFile);
else
    O = struct("orientation", table("K01-INV01", 1, cfg.panelTiltDeg, cfg.panelAzimuthDeg, 1.0, ...
        VariableNames=["Id" "Cabin" "Tilt" "Azimuth" "AmPm"]), ...
        "sensorRows", table("K01-METEO", 0, 180, VariableNames=["Id" "Tilt" "Azimuth"]));
end

rows = {};
for split = ["train" "holdout"]
    f = dir(fullfile(base, split, "inverter", "*.mat"));
    for k = 1:numel(f)
        D = load(fullfile(f(k).folder, f(k).name), "info");
        if ~isfield(D, "info"), continue; end
        info = D.info;
        idStr = string(info.Id);
        if any(cellfun(@(x) string(x) == idStr, rows(:, min(1, end))))
            continue
        end
        num = double(regexp(idStr, "\d+", "match"));
        cabNum = 1;
        if ~isempty(num), cabNum = num(1); end
        vmp = info.Vmppt;
        if numel(vmp) < 4, vmp = [vmp, repmat(vmp(1), 1, 4 - numel(vmp))]; end
        inst = logical(info.Installed);
        if numel(inst) < 8, inst = [inst, false(1, 8 - numel(inst))]; end
        rows(end+1, :) = {idStr, cabNum, info.Rated, info.Capacity, inst, vmp, {string(info.Peers)}}; %#ok<AGROW>
    end
end

if isempty(rows)
    rows = {"K01-INV01", 1, cfg.inverterCapacityKw, cfg.dcCapacityKwp, ...
        [true false(1,7)], repmat(cfg.vmpNominal, 1, 4), {"K01-INV01"}};
end

Inv = cell2table(rows, VariableNames=["Id" "Cabin" "Rated" "Capacity" "Installed" "Vmppt" "Peers"]);
[tf, loc] = ismember(Inv.Id, O.orientation.Id);
Inv.AmPm = ones(height(Inv), 1);
Inv.AmPm(tf) = O.orientation.AmPm(loc(tf));
Inv.InstalledVolts = ges.prep.installedStringVolts(Inv.Installed, Inv.Vmppt);
Inv.CapPerVolt = Inv.Capacity ./ max(Inv.InstalledVolts, 1);
for c = unique(Inv.Cabin)'
    m = Inv.Cabin == c & isnan(Inv.AmPm);
    Inv.AmPm(m) = median(Inv.AmPm(Inv.Cabin == c), "omitmissing");
end
S.Inv = Inv;
[g, cab] = findgroups(Inv.Cabin);
S.CabinCapPerVolt = dictionary(cab, splitapply(@(x) median(x, "omitmissing"), Inv.CapPerVolt, g));
S.CabinAmPm = dictionary(cab, splitapply(@(x) median(x, "omitmissing"), Inv.AmPm, g));
S.CabinVmppt = dictionary(cab, splitapply(@(x) median(x, "all", "omitmissing"), Inv.Vmppt, g));
S.Sensors = O.sensorRows;

meteoFile = fullfile(base, "shared", "meteo_ref.mat");
if isfile(meteoFile)
    M = load(meteoFile).meteoRef.Properties.UserData;
    sc12 = 1.0; if isfield(M, "Scale12"), sc12 = M.Scale12; end
    scPeer = 1.0; if isfield(M, "ScalePeer"), scPeer = M.ScalePeer; end
    fbOrd = "PEER"; if isfield(M, "FallbackOrder"), fbOrd = M.FallbackOrder; end
    S.Meteo = struct("Scale12", sc12, "ScalePeer", scPeer, "FallbackOrder", fbOrd);
else
    S.Meteo = struct("Scale12", 1.0, "ScalePeer", 1.0, "FallbackOrder", "PEER");
end

m1File = fullfile(cfg.paths.models, cfg.files.m1);
if isfile(m1File)
    B = load(m1File);
    if isfield(B, "bundle") && isfield(B.bundle, "Fingerprints")
        S.Fingerprints = B.bundle.Fingerprints;
    else
        S.Fingerprints = table(Inv.Id, Inv.AmPm, mean(Inv.Vmppt, 2, "omitmissing"), Inv.Cabin, ...
            VariableNames=["Id" "AmPm" "Vmean" "Cabin"]);
    end
else
    S.Fingerprints = table(Inv.Id, Inv.AmPm, mean(Inv.Vmppt, 2, "omitmissing"), Inv.Cabin, ...
        VariableNames=["Id" "AmPm" "Vmean" "Cabin"]);
end
S.HistoryEnd = cfg.split.testStart;
cache = struct("Root", cfg.paths.root, "S", S);
end
