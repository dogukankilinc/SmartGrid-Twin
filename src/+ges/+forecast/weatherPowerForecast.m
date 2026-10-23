function fc = weatherPowerForecast(ctx, wx, devices)
%WEATHERPOWERFORECAST Hava tahmininden tesis DC ve AC güç tahmini (M1 + Dinamik Faiman + Sandia Verim).
%   fc = ges.forecast.weatherPowerForecast(ctx, wx)          — cihaz bilgisi diskten okunur
%   fc = ges.forecast.weatherPowerForecast(ctx, wx, devices) — devices: struct dizisi (Id, info, DeadMask)
%   wx: ges.forecast.fetchOpenMeteo çıktısı.
%   v3 Geliştirmeleri:
%     1) HDKR anizotropik + IAM modeliyle dizi düzlemi ışınımı (G_poa, G_poa_eff) hesaplanır.
%     2) Rüzgar hızı (wx.WindSpeed) varsa Dinamik Faiman modeliyle gerçek hücre sıcaklığı (T_cell_dyn)
%        ve rüzgar soğutma kazancı (DeltaT_wind = T_mod_sat - T_cell_dyn) hesaplanır.
%     3) Hem DC güç (PlantKw, PlantKwAllStrings) hem de AC güç (PlantAcKw) ve spesifik güç (PlantSpecAc) döner.
arguments
    ctx (1,1) struct
    wx timetable
    devices struct = struct("Id", {}, "info", {}, "DeadMask", {})
end

cfg = ctx.Cfg;
meteoRefFile = fullfile(cfg.paths.processed, "shared", "meteo_ref.mat");
if isfile(meteoRefFile)
    ud = load(meteoRefFile).meteoRef.Properties.UserData;
    if isfield(ud, "SensorK02")
        sensor = ud.SensorK02;
    elseif isfield(ud, "Sensor")
        sensor = ud.Sensor;
    else
        sensor = struct("Tilt", 32, "Azimuth", 178);
    end
else
    sensor = struct("Tilt", 32, "Azimuth", 178);
end
if sensor.Tilt == 0 && isfield(cfg, "site") && isfield(cfg.site, "arrayTilt")
    sensor.Tilt = cfg.site.arrayTilt;
    sensor.Azimuth = cfg.site.arrayAzimuth;
elseif sensor.Tilt == 0
    sensor.Tilt = 32;
    sensor.Azimuth = 178;
end

geo = ges.solar.solarGeometry(wx.Time, cfg.site);
[poa, poaDetails] = ges.solar.poaIrradiance(wx.GHI, wx.DNI, wx.DHI, geo.Zenith, geo.Azimuth, ...
    sensor.Tilt, sensor.Azimuth, 0.2, Model="hdkr", Extraterrestrial=geo.Extraterrestrial);
poaCs = ges.solar.poaIrradiance(geo.GhiCs, geo.DniCs, geo.DhiCs, geo.Zenith, geo.Azimuth, ...
    sensor.Tilt, sensor.Azimuth);
n = height(wx);

if ismember("WindSpeed", wx.Properties.VariableNames)
    wSpeed = wx.WindSpeed;
else
    wSpeed = repmat(0.7, n, 1);
end
tModSat = wx.Tamb + 0.028 * poa;
[tCellDyn, ~, faimanOut] = ges.solar.cellTemperatureFaiman(wx.Tamb, poa, wSpeed, TmodSat=tModSat);

base = timetable(wx.Time, poa, poa, poaDetails.PoaEffective, poaCs, geo.Elevation, geo.Azimuth, ...
    tCellDyn, tModSat, tCellDyn, wx.Tamb, wSpeed, faimanOut.DeltaTWind, poaDetails.Iam, ...
    VariableNames=["G_ref" "G_poa" "G_poa_eff" "PoaCsRef" "Elevation" "SunAzimuth" ...
    "T_mod" "T_mod_sat" "T_cell_faiman" "T_amb" "WindSpeed" "DeltaT_wind" "IAM"]);
base.Properties.DimensionNames{1} = 'Time';
base.MeteoSource = repmat(categorical("K02"), n, 1);
base.P_dc = nan(n, 1);
base.R_iso = repmat(3000, n, 1);
[base.qOnGrid, base.qFault, base.qDerate, base.qPowerLimit, base.qClip, base.qCabinEvent, base.qMissing, base.qMeteoFallback] = ...
    deal(true(n, 1), false(n, 1), false(n, 1), false(n, 1), false(n, 1), false(n, 1), false(n, 1), false(n, 1));
base.NumWeak = zeros(n, 1);

if isempty(devices)
    devices = devicesFromDisk(ctx);
end

fps = ctx.Bundle.Fingerprints;
nDev = numel(devices);
Ts = cell(nDev, 1);
Xs = cell(nDev, 1);
fpList = cell(nDev, 1);
totalCap = 0;
for k = 1:nDev
    f = fps(fps.Id == devices(k).Id, :);
    if isempty(f)
        f = fps(1, :);
    end
    T = base;
    T.DeadMask = repmat(uint8(devices(k).DeadMask), n, 1);
    fpList{k} = struct("AmPm", f.AmPm, "Vmean", f.Vmean, "Cabin", f.Cabin);
    Ts{k} = T;
    Xs{k} = ges.model.m1Features(T, devices(k).info, fpList{k});
    totalCap = totalCap + devices(k).info.Capacity;
end
use = find(~cellfun(@isempty, Xs));
plant = zeros(n, 1);
plantAll = zeros(n, 1);
plantAc = zeros(n, 1);
if ~isempty(use)
    yAll = predict(ctx.Bundle.Gbt, vertcat(Xs{use}));
    for j = 1:numel(use)
        k = use(j);
        ex = ges.anomaly.expectedPower(ctx.Bundle, Ts{k}, devices(k).info, fpList{k}, ...
            Yhat=yAll((j - 1) * n + (1:n)));
        plant = plant + ex.PdcWork;
        plantAll = plantAll + ex.Pdc;
        plantAc = plantAc + ex.Pac;
    end
end
plantSpecAc = plantAc / max(totalCap, 1.20);
fc = timetable(wx.Time, poa, plant, plantAll, plantAc, plantSpecAc, tCellDyn, wSpeed, wx.Cloud, ...
    VariableNames=["G_poa" "PlantKw" "PlantKwAllStrings" "PlantAcKw" "PlantSpecAc" "T_cell_dyn" "WindSpeed" "Cloud"]);
fc.Properties.DimensionNames{1} = 'Time';
end

function devices = devicesFromDisk(ctx)
devices = struct("Id", {}, "info", {}, "DeadMask", {});
for id = ctx.Inverters'
    d = ges.agents.deviceData(ctx, id);
    if isempty(d.TT)
        continue
    end
    last = d.TT.DeadMask(find(d.TT.Elevation > 20 & ~d.TT.qMissing, 1, "last"));
    if isempty(last)
        last = uint8(0);
    end
    devices(end+1) = struct("Id", id, "info", d.info, "DeadMask", last); %#ok<AGROW>
end
end
