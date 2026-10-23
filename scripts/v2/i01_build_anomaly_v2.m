%% I01_BUILD_ANOMALY_V2  v2-I: çalışma zamanı için v2 adım/olay dosyaları (s05'in v2 karşılığı).
% M1-v2 (kısma-farkında) beklentisi + v2 dedektörleri (gizli ısıl kısma dahil) + v2 sağlık durumu
% ("thermal" durumu). Tüm dönem (Ara 2023 – Tem 2025), eğitim invertörleri. Test dilimi verisi
% üretilir ama ReplayEngine / loadContext onu zaten oynatmaz (Horizon < testStart).
% SMA tek evirici (K01-INV01) için de çalışır. Kısma adımları: V/I imzası (B01) veya PV gerilimi yoksa güç+sıcaklık imzası (B02, 8 invertör).
% Çıktılar: cfg.paths.anomaly/<Id>.mat (Steps, Events), events_catalog.mat; artifacts/logs/v2_i01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
logFile = fullfile(root, "artifacts", "logs", "v2_i01.log");
writelines("=== v2-I01 anomaly_v2 " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
outDir = cfg.paths.anomaly;
if ~isfolder(outDir), mkdir(outDir); end
if ~isfolder(fileparts(logFile)), mkdir(fileparts(logFile)); end

bundle = load(fullfile(cfg.paths.models, cfg.files.m1)).bundle;
fps = bundle.Fingerprints;
meteoRef = load(fullfile(cfg.paths.processed, "shared", "meteo_ref.mat")).meteoRef;
t = meteoRef.Time;
files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
n = numel(files);
residual = nan(numel(t), n);
validAll = false(numel(t), n);
eventsAll = cell(n, 1);
stateCounts = zeros(n, numel(ges.anomaly.stateNames()));
for k = 1:n
    S = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = S.TT;
    info = S.info;
    TT.qThrottle = false(height(TT), 1);
    TT.ThrottleLossKw = zeros(height(TT), 1);
    thrFile = fullfile(cfg.paths.throttle, info.Id + ".mat");
    thrFileP = fullfile(cfg.paths.throttleP, info.Id + ".mat");   % v2-B02: PV gerilimsiz invertörler
    sigName = "V/I imzası";
    if ~isfile(thrFile) && isfile(thrFileP)
        thrFile = thrFileP;
        sigName = "güç+sıcaklık imzası";
    end
    if isfile(thrFile)
        Th = load(thrFile, "Time", "Throttled", "LossKw");
        [tf, loc] = ismember(TT.Time, Th.Time);
        TT.qThrottle(tf) = Th.Throttled(loc(tf));
        TT.ThrottleLossKw(tf) = double(Th.LossKw(loc(tf)));
    end
    info.Id = string(info.Id);
    f = fps(fps.Id == info.Id, :);
    if isempty(f), f = fps(1, :); end
    fp = struct("AmPm", f.AmPm, "Vmean", f.Vmean, "Cabin", f.Cabin);
    ex = ges.anomaly.expectedPower(bundle, TT, info, fp);
    s = ges.anomaly.detectSteps(TT, ex);
    events = ges.anomaly.inverterEvents(TT, ex, s, info.Id, f.Cabin, sigName);
    state = ges.anomaly.healthState(TT, s, events);
    Steps = timetable(TT.Time, ex.Pdc, ex.PdcWork, ex.Pac, s.Deficit, s.ResidualDeficit, s.DeficitLevel, ...
        sum(s.StringDead, 2), state, s.Throttle, s.ThrottleDuty, TT.ThrottleLossKw, ...
        VariableNames=["Pdc_exp" "PdcWork_exp" "Pac_exp" "Deficit" "ResidualDeficit" "DeficitLevel" ...
        "NumDeadSustained" "HealthState" "Throttle" "ThrottleDuty" "ThrottleLossKw"]);
    Steps.Properties.DimensionNames{1} = 'Time';
    Events = events;
    save(fullfile(outDir, info.Id + ".mat"), "Steps", "Events");
    [tf, loc] = ismember(TT.Time, t);
    residual(loc(tf), k) = s.ResidualDeficit(tf);
    validAll(loc(tf), k) = s.Valid(tf);
    eventsAll{k} = events;
    lit = TT.Elevation > 5;
    stateCounts(k, :) = countcats(state(lit))';
    if mod(k, 20) == 0
        logMsg(sprintf("  %d/%d (%.0f s)", k, n, toc(tStart)));
    end
end
nValid = sum(validAll, 2);
fracOver = sum(validAll & residual < -0.10, 2) ./ nValid;
fracUnder = sum(validAll & residual > 0.10, 2) ./ nValid;
sustain = @(m) movmin(double(m), [3 0], Endpoints="fill") == 1;
minInv = min(20, max(n, 1));
multiFleet = n >= 5;   % tek eviricili sistemde filo-ortak karar anlamsız (3. görüş / peer katmanı bakar)
meteoSuspect = multiFleet & sustain(nValid >= minInv & fracOver >= 0.6);
fleetDeficit = multiFleet & sustain(nValid >= minInv & fracUnder >= 0.6);
plant = [labelPlant(ges.anomaly.buildEpisodes(t, meteoSuspect, zeros(size(t)), MinSteps=4), "meteo_sensor_suspect")
         labelPlant(ges.anomaly.buildEpisodes(t, fleetDeficit, zeros(size(t)), MinSteps=4), "fleet_underperformance")];
catalog = sortrows([vertcat(eventsAll{:}); plant], "Start");
save(fullfile(outDir, "events_catalog.mat"), "catalog");
names = ges.anomaly.stateNames();
sc = sum(stateCounts, 1);
logMsg("Gündüz adımlarının v2 sağlık durumu dağılımı (%):");
for i = 1:numel(names)
    logMsg(sprintf("  %-8s %6.2f", names(i), 100 * sc(i) / sum(sc)));
end
g = groupsummary(catalog, "Type", "sum", "LossKwh");
for i = 1:height(g)
    logMsg(sprintf("  olay %-24s %6d adet, kayıp %.1f MWh", g.Type(i), g.GroupCount(i), g.sum_LossKwh(i) / 1000));
end
logMsg("=== v2-I01 bitti " + string(datetime("now")) + sprintf(" (%.0f s)", toc(tStart)));

%% ---------------------------------------------------------------------------

function T = labelPlant(ep, type)
n = height(ep);
T = table(repmat("PLANT", n, 1), zeros(n, 1), repmat(type, n, 1), zeros(n, 1), repmat(2, n, 1), repmat("", n, 1), ...
    ep.Start, ep.End, ep.Steps, ep.DurationDays, ep.LossKwh, ep.Chronic, ...
    VariableNames=["Id" "Cabin" "Type" "PV" "Severity" "Detail" "Start" "End" "Steps" "DurationDays" "LossKwh" "Chronic"]);
end
