function [X, y, aux] = m1Features(TT, info, fingerprint)
%M1FEATURES Beklenen güç modeli (M1) için öznitelik matrisi, hedef ve yardımcı vektörler.
%   [X, y, aux] = ges.model.m1Features(TT, info, fingerprint)
%   TT          : s03_build_features çıktısı (işlenmiş 15 dk timetable)
%   info        : cihaz künyesi (Installed 1×8, Vmppt 1×4, Rated, Capacity)
%   fingerprint : struct — AmPm, Vmean, Cabin (invertörün kalıcı özellikleri)
%
%   Hedef y = 1000 * P_dc / V_work  [A]  — "efektif string akımı".
%   SmartGridLab entegrasyonu:
%     - Eğim düzeltmeli G_poa varsa doğrudan G özniteliğine bağlanır (yoksa G_ref).
%     - Rüzgar soğutmalı dinamik Faiman hücre sıcaklığı (T_cell_dyn = f(T_amb, G_poa, WindSpeed))
%       T_mod özniteliğine bağlanır; böylece sentetik T_mod_sat doğrusal bağımlılığı aşılır.
%     - Tek stringli (Vmppt(2:4) = NaN) sistemlerde 0*NaN = NaN hatası önlenir.

mpptOf = [1 1 2 2 3 3 4 4];
vmppt = double(info.Vmppt(:)');
if numel(vmppt) < 4
    vmppt = [vmppt, nan(1, 4 - numel(vmppt))];
end
vMeanValid = mean(vmppt, "omitnan");
if isnan(vMeanValid) || vMeanValid <= 0
    vMeanValid = 200;
end
vmppt(isnan(vmppt) | vmppt <= 0) = vMeanValid;
vString = vmppt(mpptOf);                            % 1×8, NaN içermez

installed = logical(info.Installed(:)');
if numel(installed) < 8
    installed = [installed, false(1, 8 - numel(installed))];
end
vString(~installed) = 0;

n = height(TT);
vars = TT.Properties.VariableNames;
dead = false(n, 8);
if ismember("DeadMask", vars)
    dm = uint8(fillmissing(TT.DeadMask, "constant", 0));
    for s = 1:8
        dead(:, s) = bitget(dm, s) == 1;
    end
end
aux.VInst = sum(installed .* vString);
aux.VWork = double(installed & ~dead) * vString';

% Eğim düzeltmeli ışınım (G_poa) ve açık-gök referansı
if ismember("G_poa", vars) && any(~isnan(TT.G_poa))
    g = double(TT.G_poa);
else
    g = double(TT.G_ref);
end
poaCs = double(TT.PoaCsRef);
kc = min(max(g ./ max(poaCs, 50), 0), 1.5);         % NaN'sız clear-sky indeksi (MLP için)
kcVar = movstd(kc, [3 0], "omitmissing");
doy = day(TT.Time, "dayofyear");

% Rüzgar hızı ve dinamik Faiman hücre sıcaklığı (T_cell_dyn)
vWind = zeros(n, 1);
for wn = ["WindSpeed" "W_spd" "Wind"]
    if ismember(wn, vars)
        vWind = fillmissing(double(TT.(wn)), "constant", 0);
        break
    end
end
tAmb = double(TT.T_amb);
if ismember("T_cell_dyn", vars) && any(~isnan(TT.T_cell_dyn))
    tModEff = double(TT.T_cell_dyn);
elseif any(vWind > 0) && any(~isnan(tAmb))
    u0 = 25.0;
    u1 = 6.84;
    tSs = tAmb + g ./ max(u0 + u1 * max(vWind, 0), 10);
    tModEff = tSs;
    alpha = 0.25;
    for k = 2:n
        if ~isnan(tModEff(k-1)) && ~isnan(tSs(k))
            tModEff(k) = alpha * tModEff(k-1) + (1 - alpha) * tSs(k);
        end
    end
else
    tModEff = double(TT.T_mod);
end

vMeanFp = fingerprint.Vmean;
if isnan(vMeanFp) || vMeanFp <= 0
    vMeanFp = vMeanValid;
end
amPmFp = fingerprint.AmPm;
if isnan(amPmFp) || amPmFp <= 0
    amPmFp = 1.0;
end

X = table(g, [NaN; g(1:end-1)], kc, kcVar, TT.Elevation, sind(TT.SunAzimuth), cosd(TT.SunAzimuth), ...
    poaCs, tModEff, tAmb, sin(2 * pi * doy / 365.25), cos(2 * pi * doy / 365.25), ...
    repmat(amPmFp, n, 1), repmat(vMeanFp, n, 1), repmat(fingerprint.Cabin, n, 1), ...
    VariableNames=["G" "G_lag1" "Kc" "KcVar" "Elevation" "SinSunAz" "CosSunAz" "PoaCs" ...
    "T_mod" "T_amb" "SinDoy" "CosDoy" "AmPm" "Vmean" "Cabin"]);
X.G_lag1(isnan(X.G_lag1)) = X.G(isnan(X.G_lag1));

y = 1000 * double(TT.P_dc) ./ max(aux.VWork, eps);
vMinWork = min(100, 0.5 * aux.VInst);
y(aux.VWork < vMinWork) = NaN;

aux.Lit = TT.Elevation > 3 & g > 20 & ~isnan(g);
aux.WindSpeed = vWind;
if ismember("R_iso", vars)
    aux.R_iso = double(TT.R_iso);
else
    aux.R_iso = repmat(3000, n, 1);
end

cap = 1.20;
if isfield(info, "Capacity") && ~isempty(info.Capacity) && ~isnan(info.Capacity)
    cap = info.Capacity;
end
pMinHealthy = min(0.2, 0.04 * cap);

meteoOk = true(n, 1);
if ismember("MeteoSource", vars)
    ms = string(TT.MeteoSource);
    if any(ms == "K02")
        meteoOk = ms == "K02";
    else
        meteoOk = ~ismissing(ms) & ms ~= "" & ms ~= "none";
    end
end

aux.Healthy = aux.Lit & meteoOk & TT.qOnGrid & ~TT.qFault & ~TT.qDerate ...
    & ~TT.qPowerLimit & ~TT.qClip & ~TT.qCabinEvent & ~TT.qMissing & TT.NumWeak == 0 ...
    & ~isnan(y) & TT.P_dc > pMinHealthy & all(~ismissing(X(:, ["T_mod" "T_amb"])), 2);

if ismember("qThrottle", vars)
    aux.Healthy = aux.Healthy & ~TT.qThrottle;
end
if ismember("qRelayCycle", vars)
    aux.Healthy = aux.Healthy & ~TT.qRelayCycle;
end
end
