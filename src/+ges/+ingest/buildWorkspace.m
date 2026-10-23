function manifest = buildWorkspace(cfg, catalog, name, opts)
%BUILDWORKSPACE Yüklenen ham rapor dosyalarını (SMA Sunny Portal veya Huawei) uçtan uca işler -> workspace/<ad>.
%   manifest = ges.ingest.buildWorkspace(cfg, catalog, name)
%   Adımlar:
%     1) Cihaz dosyalarını oku ve birleştir (ges.io.loadDevice)
%     2) Ortak 15 dk zaman ızgarası ve güneş geometrisi
%     3) Meteoroloji referansı: yatay G_horiz -> dizi düzlemi G_poa (32°/180°) transpozisyonu,
%        rüzgar hızı (WindSpeed) ve dinamik Faiman hücre sıcaklığı (T_cell_faiman)
%     4) Evirici künyesi (P_ac / P_ac_spec = 1.20 kWp analitik kapasite doğrulaması)
%     5) Öznitelikler (ges.prep.assembleInverter) ve günlük özet (ges.prep.dailySummary)
%     6) M1-v2 beklenen güç
%     7) Isıl kısma imzası (V/I zarfı veya güç+sıcaklık imzası)
%     8) Adım dedektörleri, sağlık durumu, olay kataloğu

arguments
    cfg (1,1) struct
    catalog table
    name (1,1) string
    opts.Progress = @(msg) []
    opts.SiteName (1,1) string = ""
end
say = opts.Progress;
tStart = tic;
name = string(regexprep(char(name), "[^\w\-]", "_"));
ws = fullfile(cfg.paths.root, "workspace", name);
if isfolder(ws)
    rmdir(ws, "s");
end
dirs = ["processed/train/inverter" "processed/shared" "anomaly" "throttle" "throttle_p" "interim/train" "runtime"];
for d = dirs
    mkdir(fullfile(ws, d));
end
S = ges.ingest.plantState(cfg);
m1Path = fullfile(cfg.paths.models, cfg.files.m1);
if isfile(m1Path)
    bundle = load(m1Path).bundle;
else
    bundle = struct();
end
b02Path = fullfile(cfg.paths.root, "artifacts", "v2", "b02_summary.mat");
if isfile(b02Path)
    b02 = load(b02Path).summary;
else
    b02 = struct("TTH", 58, "DELTA", 0.08);
end

% Eğer katalogda "sma_combined" varsa 3 mantıksal türe genişlet
if any(catalog.Kind == "sma_combined")
    catalog = ges.ingest.catalogFiles(unique(catalog.File, "stable"));
end
cl = catalog(catalog.Kind ~= "unknown", :);
if ~any(cl.Kind == "meteo")
    error("ges:ingest:noMeteo", "En az bir meteoroloji dosyası gerekli (ışınım ve sıcaklık).");
end
if ~any(cl.Kind == "inverter")
    error("ges:ingest:noInverter", "En az bir invertör dosyası gerekli.");
end

%% 1) Cihazları oku
ids = unique(cl.Id, "stable");
raw = containers.Map("KeyType", "char", "ValueType", "any");
kind = strings(numel(ids), 1);
cabinOf = nan(numel(ids), 1);
for k = 1:numel(ids)
    rows = cl.Id == ids(k);
    kind(k) = cl.Kind(find(rows, 1));
    cabinOf(k) = cl.Cabin(find(rows, 1));
    TT = ges.io.loadDevice(cl.File(rows), TimeStep=cfg.data.timeStep, TimeZone=cfg.data.timeZone);
    raw(char(ids(k))) = TT;
    if mod(k, 10) == 0 || k == numel(ids)
        say(sprintf("1/5 Dosyalar okunuyor: %d/%d cihaz (%.0f s)", k, numel(ids), toc(tStart)));
    end
end
invIds = ids(kind == "inverter");
meteoIds = ids(kind == "meteo");
invCabin = cabinOf(kind == "inverter");
invCabin(isnan(invCabin)) = 1;

%% 2) Zaman ızgarası
starts = NaT(0, 1, TimeZone=cfg.data.timeZone);
ends = starts;
for id = [meteoIds; invIds]'
    TT = raw(char(id));
    if height(TT) > 0
        starts(end+1, 1) = TT.Time(1); %#ok<AGROW>
        ends(end+1, 1) = TT.Time(end); %#ok<AGROW>
    end
end
t = (min(starts):cfg.data.timeStep:max(ends))';
geo = ges.solar.solarGeometry(t, cfg.site);
night = geo.Elevation < -2;
say(sprintf("2/5 Zaman ızgarası: %s – %s (%d adım)", string(t(1), "dd.MM.yyyy HH:mm"), string(t(end), "dd.MM.yyyy HH:mm"), numel(t)));

%% 3) Meteoroloji istasyonları ve Dizi Düzlemi (POA) Transpozisyonu
nm = numel(meteoIds);
G = nan(numel(t), nm);
Gpoa = nan(numel(t), nm);
valid = false(numel(t), nm);
poaSen = nan(numel(t), nm);
poaArr = ges.solar.poaIrradiance(geo.GhiCs, geo.DniCs, geo.DhiCs, geo.Zenith, geo.Azimuth, ...
    cfg.panelTiltDeg, cfg.panelAzimuthDeg);
Tmod = nan(numel(t), nm);
TmodSys = nan(numel(t), nm);
Tamb = nan(numel(t), nm);
Wind = zeros(numel(t), nm);
short = strings(1, nm);
tilts = nan(1, nm);
azs = nan(1, nm);
notes = strings(0, 1);

for j = 1:nm
    M = retime(raw(char(meteoIds(j))), t);
    short(j) = erase(meteoIds(j), "-METEO");
    sr = S.Sensors(S.Sensors.Id == meteoIds(j), :);
    if isempty(sr)
        if short(j) == "K01"
            tilt = cfg.site.sensorTiltDeg;
            az = cfg.site.sensorAzimuthDeg;
        else
            day = geo.Elevation > 5;
            fit = ges.solar.fitOrientation(M.Time(day), M.G(day), cfg.site);
            tilt = fit.Tilt;
            az = fit.Azimuth;
            notes(end+1) = sprintf("%s: yeni ışınım sensörü, eğim/azimut veriden kestirildi (%.0f°/%.0f°)", meteoIds(j), tilt, az); %#ok<AGROW>
        end
    else
        tilt = sr.Tilt(1);
        az = sr.Azimuth(1);
    end
    tilts(j) = tilt;
    azs(j) = az;
    poaSen(:, j) = ges.solar.poaIrradiance(geo.GhiCs, geo.DniCs, geo.DhiCs, geo.Zenith, geo.Azimuth, tilt, az);
    G(:, j) = M.G;
    valid(:, j) = ges.prep.meteoQuality(M.G, poaSen(:, j), geo.Elevation);
    % Sensör yatay (tilt ~ 0°) ve dizi eğimli (32°) ise açık-gök oranıyla dizi düzlemine taşı
    if abs(tilt - cfg.panelTiltDeg) > 5
        transFactor = poaArr ./ max(poaSen(:, j), 15);
        transFactor(geo.Elevation < 3 | poaSen(:, j) < 15) = 1.0;
        transFactor = min(max(transFactor, 0.5), 2.2);
        Gpoa(:, j) = M.G .* transFactor;
    else
        Gpoa(:, j) = M.G;
    end
    mVars = string(M.Properties.VariableNames);
    if ismember("T_mod", mVars), Tmod(:, j) = M.T_mod; end
    if ismember("T_mod_sys", mVars), TmodSys(:, j) = M.T_mod_sys; else, TmodSys(:, j) = Tmod(:, j); end
    if ismember("T_amb", mVars), Tamb(:, j) = M.T_amb; end
    if ismember("WindSpeed", mVars), Wind(:, j) = fillmissing(M.WindSpeed, "constant", 0); end
end

p = find(short == "K01" | short == "K02", 1);
if isempty(p)
    [~, p] = max(sum(valid & geo.Elevation > 5, 1));
end
pName = short(p);
poaP = poaArr;
kcP = Gpoa(:, p) ./ max(poaP, 1);

%% 4) İnvertör künyesi
n = numel(invIds);
data = cell(n, 1);
flags = cell(n, 1);
inv = table(invIds, invCabin, zeros(n, 1), zeros(n, 1), false(n, 8), nan(n, 4), nan(n, 1), strings(n, 1), ...
    VariableNames=["Id" "Cabin" "Rated" "Capacity" "Installed" "Vmppt" "AmPm" "Method"]);
peersKnown = cell(n, 1);
isClearDay = clearDays(t, Gpoa(:, p), poaP, geo);

for k = 1:n
    TT = retime(raw(char(invIds(k))), t);
    data{k} = TT;
    flags{k} = ges.prep.statusFlags(TT);
    r = S.Inv(S.Inv.Id == invIds(k), :);
    if ~isempty(r)
        inv.Rated(k) = r.Rated(1);
        inv.Capacity(k) = r.Capacity(1);
        inv.Installed(k, :) = r.Installed(1, :);
        inv.Vmppt(k, :) = r.Vmppt(1, :);
        inv.AmPm(k) = r.AmPm(1);
        inv.Method(k) = "eğitim künyesi";
        peersKnown{k} = r.Peers{1};
        continue
    end
    c = inv.Cabin(k);
    ttVars = string(TT.Properties.VariableNames);
    if ismember("P_ac_spec", ttVars) && any(TT.P_ac_spec > 0.1)
        capAnalytic = median(TT.P_ac(TT.P_ac_spec > 0.1) ./ TT.P_ac_spec(TT.P_ac_spec > 0.1), "omitmissing");
        inv.Capacity(k) = round(capAnalytic, 2);
        inv.Rated(k) = inv.Capacity(k);
    else
        inv.Rated(k) = max(cfg.data.ratedAcPower, round(prctile(TT.P_ac, 99.9), 2));
        inv.Capacity(k) = inv.Rated(k);
    end
    nDays = numel(unique(dateshift(TT.Time(~isnan(TT.P_dc)), "start", "day")));
    inv.Installed(k, :) = ges.prep.installedStrings(TT, min(20, max(2, round(0.2 * nDays))));
    capMask = valid(:, p) & kcP > 0.75 & geo.Elevation > 25 & Gpoa(:, p) > 400 & flags{k}.OnGrid ...
        & TT.P_ac < 0.97 * inv.Rated(k) & TT.P_dc > 0.1 * inv.Rated(k);
    v = ges.prep.mpptVoltages(TT, capMask);
    inv.Vmppt(k, :) = v;
    inv.Method(k) = "analitik / kendi verisinden";
    morning = geo.Azimuth < 180;
    am = sum(TT.P_dc(isClearDay & morning), "omitnan");
    pm = sum(TT.P_dc(isClearDay & ~morning), "omitnan");
    inv.AmPm(k) = am / max(pm, eps);
    if ~(inv.AmPm(k) > 0) || isinf(inv.AmPm(k))
        inv.AmPm(k) = 1;
    end
end

Pn = nan(numel(t), n);
for k = 1:n
    usable = flags{k}.OnGrid & data{k}.P_ac < 0.97 * inv.Rated(k);
    Pn(usable, k) = data{k}.P_dc(usable) / inv.Capacity(k);
end

%% 3b) Referans ışınım ve Faiman sıcaklığı
cP = Gpoa(:, p);
cP(~valid(:, p)) = NaN;
gHorizRef = G(:, p);
gHorizRef(night & isnan(gHorizRef)) = 0;

fb = zeros(numel(t), 0);
fbNames = strings(1, 0);
cal = valid(:, p) & geo.Elevation > 15 & Gpoa(:, p) > 50;
for j = setdiff(1:nm, p)
    kc = Gpoa(:, j) ./ max(poaP, 1);
    kc(poaP < 30) = NaN;
    g = kc .* poaP;
    ok = cal & valid(:, j) & ~isnan(g);
    scale = median(Gpoa(ok, p) ./ g(ok), "omitmissing");
    if isnan(scale) || scale <= 0, scale = 1.0; end
    g = scale * g;
    g(~valid(:, j)) = NaN;
    fb(:, end+1) = g; %#ok<AGROW>
    fbNames(end+1) = short(j); %#ok<AGROW>
end
gPeer = 1000 * median(Pn, 2, "omitmissing");
if n >= 3
    gPeer(sum(~isnan(Pn), 2) < min(10, max(3, round(n / 3)))) = NaN;
end
ok = cal & ~isnan(gPeer);
scalePeer = median(Gpoa(ok, p) ./ gPeer(ok), "omitmissing");
if isnan(scalePeer) || scalePeer <= 0, scalePeer = 1.0; end
fb(:, end+1) = scalePeer * gPeer;
fbNames(end+1) = "PEER";
order = [fbNames(fbNames ~= "PEER") "PEER"];
[~, loc] = ismember(order, fbNames);
[gRef, meteoSource] = ges.prep.resolveMeteo([cP fb(:, loc)], [pName order]);
gRef(night & isnan(gRef)) = 0;

tMod = Tmod(:, p);
tModSys = TmodSys(:, p);
tAmb = Tamb(:, p);
windSpd = Wind(:, p);
tMod(isnan(tMod)) = tModSys(isnan(tMod));

% Faiman hücre sıcaklığı
gSafe = max(fillmissing(gRef, "constant", 0), 0);
wSafe = fillmissing(max(windSpd, 0), "constant", 0.5);
tSs = tAmb + gSafe ./ (25.0 + 6.84 * wSafe);
tCellFaiman = tSs;
alphaTh = exp(-15 / 12);
for i = 2:numel(t)
    if ~isnan(tCellFaiman(i-1)) && ~isnan(tSs(i))
        tCellFaiman(i) = alphaTh * tCellFaiman(i-1) + (1 - alphaTh) * tSs(i);
    end
end

kc = gRef ./ max(poaP, 1);
kc(poaP < 50 | geo.Elevation < 5) = NaN;
kcVar = movstd(kc, [3 0], "omitmissing");
sky = repmat("partly", numel(t), 1);
sky(kc >= 0.8 & kcVar < 0.05) = "clear";
sky(kc < 0.35) = "overcast";
sky(isnan(kc)) = "night";
skyStep = categorical(sky, ["clear" "partly" "overcast" "night"]);

meteoRef = timetable(t, gRef, gRef, gHorizRef, meteoSource, tMod, tMod, tModSys, tAmb, windSpd, tCellFaiman, ...
    geo.Zenith, geo.Azimuth, geo.Elevation, poaP, geo.GhiCs, kc, kcVar, skyStep, ...
    VariableNames=["G_ref" "G_poa" "G_horiz" "MeteoSource" "T_mod" "T_mod_sat" "T_mod_sys" "T_amb" ...
    "WindSpeed" "T_cell_faiman" "Zenith" "SunAzimuth" "Elevation" "PoaCsRef" "GhiCs" "Kc" "KcVar" "SkyStep"]);
meteoRef.Properties.DimensionNames{1} = 'Time';
meteoRef.Properties.UserData = struct("Primary", pName, "FallbackOrder", order, "Scale12", 1.0, "ScalePeer", scalePeer, ...
    "Sensor", struct("Tilt", tilts(p), "Azimuth", azs(p)), ...
    "Array", struct("Tilt", cfg.panelTiltDeg, "Azimuth", cfg.panelAzimuthDeg));
save(fullfile(ws, "processed", "shared", "meteo_ref.mat"), "meteoRef");
say(sprintf("3/5 Meteoroloji: birincil %s, yedekler %s", pName, strjoin(order, " > ")));

%% 5-8) İnvertör başına: öznitelik -> M1 -> kısma -> dedektörler -> durum / olaylar
cabinEvt = containers.Map("KeyType", "double", "ValueType", "any");
for c = unique(inv.Cabin)'
    idx = find(inv.Cabin == c);
    cabinEvt(c) = ges.prep.cabinEventMask(data(idx), flags(idx), geo.Elevation, gRef);
end
evAll = cell(n, 1);
nCold = 0;
for k = 1:n
    id = invIds(k);
    c = inv.Cabin(k);
    idx = find(inv.Cabin == c);
    j = find(idx == k);
    pk = idx(ismember(invIds(idx), peersKnown{k}));
    if numel(pk) < min(3, numel(idx))
        pk = idx(ges.prep.pickPeers(inv.AmPm(idx), j, 4));
    end
    row = struct("Rated", inv.Rated(k), "Installed", inv.Installed(k, :));
    P = ges.prep.assembleInverter(data{k}, flags{k}, Pn(:, k), Pn(:, pk), row, meteoRef, cabinEvt(c), 0.97, pName);
    D = ges.prep.dailySummary(P);
    known = inv.Method(k) == "eğitim künyesi";
    info = struct("Id", id, "Device", "WR13TL22-8231", "DisplayName", "WR13TL22-8231 (1.20 kWp)", ...
        "Cabin", c, "Inv", k, "Rated", inv.Rated(k), "Capacity", inv.Capacity(k), ...
        "Installed", inv.Installed(k, :), "Vmppt", inv.Vmppt(k, :), ...
        "Tilt", cfg.panelTiltDeg, "Azimuth", cfg.panelAzimuthDeg, ...
        "Peers", invIds(pk)', "Split", "workspace", "Method", inv.Method(k));
    fpRow = S.Fingerprints(S.Fingerprints.Id == id, :);
    if known && ~isempty(fpRow)
        fp = struct("AmPm", fpRow.AmPm(1), "Vmean", fpRow.Vmean(1), "Cabin", fpRow.Cabin(1));
    else
        nCold = nCold + 1;
        fp = struct("AmPm", inv.AmPm(k), "Vmean", mean(inv.Vmppt(k, :), "omitmissing"), "Cabin", c);
    end

    if ~isempty(fieldnames(bundle))
        ex = ges.anomaly.expectedPower(bundle, P, info, fp, UseCalibration=known);
    else
        % Fiziksel yedek beklenen güç (M1 modeli henüz eğitilmemişse)
        pExp = inv.Capacity(k) * (P.G_poa / 1000) .* (1 - 0.0037 * (P.T_cell_faiman - 25));
        pExp(P.Elevation < 0 | isnan(pExp)) = 0;
        pExp = max(pExp, 0);
        ex = struct("Pdc", pExp, "PdcWork", pExp, "Pac", min(0.935 * pExp, inv.Rated(k)));
    end

    % Isıl kısma imzası
    P.qThrottle = false(height(P), 1);
    P.ThrottleLossKw = zeros(height(P), 1);
    hasV = ismember("V_pv1", P.Properties.VariableNames) && any(~isnan(P.V_pv1));
    if hasV
        cols = intersect(["P_dc" "P_ac" "T_mod" "G_ref" "Elevation" "qOnGrid" "DeadMask" "V_pv" + (1:8) "I_pv" + (1:8)], ...
            string(P.Properties.VariableNames), "stable");
        X = P(:, cols);
        hf = fullfile(cfg.paths.root, "artifacts", "processed", "train", "inverter", id + ".mat");
        if known && isfile(hf)
            H = load(hf, "TT").TT;
            H = H(H.Time >= t(1) - days(150) & H.Time < min(t(1), S.HistoryEnd), intersect(cols, string(H.Properties.VariableNames), "stable"));
            if width(H) == width(X)
                X = [H; X];
            end
        end
        sig = ges.anomaly.throttleSignatureRolling(X, info);
        keep = ismember(X.Time, P.Time);
        Time = X.Time(keep);
        Throttled = sig.Throttled(keep);
        LossKw = single(sig.LossKw(keep));
        Ppot = single(sig.Ppot(keep));
        Valid = sig.Valid(keep);
        save(fullfile(ws, "throttle", id + ".mat"), "Time", "Throttled", "LossKw", "Ppot", "Valid");
        sigName = "V/I imzası";
    else
        base = P.Elevation > 15 & P.G_ref > 250 & P.qOnGrid & ~P.qFault & ~P.qCabinEvent & ~P.qClip ...
            & ~P.qMissing & ~isnan(P.P_dc) & P.SkyStep == "clear" & ~isnan(P.T_cab) & ex.PdcWork > 0.1 * inv.Rated(k);
        Throttled = base & P.T_cab >= b02.TTH & P.P_dc ./ ex.PdcWork < 1 - b02.DELTA;
        LossKw = single(max(ex.PdcWork - P.P_dc, 0) .* Throttled);
        Ppot = single(ex.PdcWork);
        Ppot(~base) = NaN;
        Valid = base;
        Time = P.Time;
        Source = "P";
        save(fullfile(ws, "throttle_p", id + ".mat"), "Time", "Throttled", "LossKw", "Ppot", "Valid", "Source");
        sigName = "güç+sıcaklık imzası";
    end
    [tf, loc] = ismember(P.Time, Time);
    P.qThrottle(tf) = Throttled(loc(tf));
    P.ThrottleLossKw(tf) = double(LossKw(loc(tf)));

    s = ges.anomaly.detectSteps(P, ex);
    events = ges.anomaly.inverterEvents(P, ex, s, id, c, sigName);
    state = ges.anomaly.healthState(P, s, events);
    Steps = timetable(P.Time, ex.Pdc, ex.PdcWork, ex.Pac, s.Deficit, s.ResidualDeficit, s.DeficitLevel, ...
        sum(s.StringDead, 2), state, s.Throttle, s.ThrottleDuty, P.ThrottleLossKw, ...
        VariableNames=["Pdc_exp" "PdcWork_exp" "Pac_exp" "Deficit" "ResidualDeficit" "DeficitLevel" ...
        "NumDeadSustained" "HealthState" "Throttle" "ThrottleDuty" "ThrottleLossKw"]);
    Steps.Properties.DimensionNames{1} = 'Time';
    Events = events;
    save(fullfile(ws, "anomaly", id + ".mat"), "Steps", "Events");
    TT = removevars(P, intersect(["qThrottle" "ThrottleLossKw"], string(P.Properties.VariableNames)));
    save(fullfile(ws, "processed", "train", "inverter", id + ".mat"), "TT", "D", "info");
    evAll{k} = events;
    if mod(k, 5) == 0 || k == n
        say(sprintf("4/5 İnvertörler işleniyor: %d/%d (%.0f s)", k, n, toc(tStart)));
    end
end
catalogEv = sortrows(vertcat(evAll{:}), "Start");
catalog = catalogEv; %#ok<NASGU>
save(fullfile(ws, "anomaly", "events_catalog.mat"), "catalog");
registry = table(ids, kind, cabinOf, VariableNames=["Id" "Kind" "Cabin"]); %#ok<NASGU>
save(fullfile(ws, "interim", "train", "registry.mat"), "registry");

%% Bildirim / manifest
siteName = opts.SiteName;
if strlength(siteName) == 0
    siteName = cfg.site.name;
end
manifest = struct("Name", name, "Created", datetime("now"), "SiteName", siteName, "Start", t(1), "End", t(end), ...
    "Files", cl, "Inverters", invIds, "Cabins", unique(invCabin)', "Meteo", meteoIds, "PrimaryMeteo", pName, ...
    "HasPlantMeter", any(kind == "plant"), "Inventory", inv(:, ["Id" "Cabin" "Rated" "Capacity" "Method"]), ...
    "ColdStartInverters", nCold, "Notes", notes, "Seconds", toc(tStart));
save(fullfile(ws, "manifest.mat"), "manifest");
say(sprintf("5/5 Tamamlandı: %d invertör, %d kabin, %s – %s (%.0f s).", n, ...
    numel(unique(invCabin)), string(t(1), "dd.MM.yyyy"), string(t(end), "dd.MM.yyyy"), toc(tStart)));
end

function isClear = clearDays(t, g, poa, geo)
day = dateshift(t, "start", "day");
up = geo.Zenith < 80;
isClear = false(numel(t), 1);
if ~any(up)
    return
end
[gi, dd] = findgroups(day(up));
err = splitapply(@(a, b) sqrt(mean((a - b * (a' * b) / max(b' * b, eps)).^2, "omitmissing")) / max(mean(a, "omitmissing"), eps), ...
    fillmissing(g(up), "constant", 0), poa(up), gi);
cov = splitapply(@(a) mean(~isnan(a)), g(up), gi);
isClear = ismember(day, dd(err < 0.08 & cov > 0.85)) & up;
if ~any(isClear)
    isClear = up & g > 300;
end
end
