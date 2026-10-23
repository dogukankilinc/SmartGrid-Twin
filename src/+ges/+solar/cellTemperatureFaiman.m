function [tCellDyn, tCellVdc, out] = cellTemperatureFaiman(tAmb, gPoa, windSpeed, opts)
%CELLTEMPERATUREFAIMAN Rüzgar soğutmalı dinamik Faiman hücre sıcaklığı ve V_dc sanal hücre termometresi.
%   [tCellDyn, tCellVdc, out] = ges.solar.cellTemperatureFaiman(tAmb, gPoa, windSpeed, ...)
%
%   SmartGridLab keşfi:
%     - CSV'deki "Module temperature [°C] / Satellite Sensor" gerçek bir sensör olmayıp
%       T_mod_sat = T_amb + 0.028 * G statik Ross formülüdür (RMSE = 0.036 °C) ve rüzgar hızını yok sayar.
%     - Bu fonksiyon Faiman (2008) / IEC 61853-2 konvektif ısı kaybı modelini 1. derece ısıl atalet
%       filtresiyle birleştirir ve V_dc gerilimi verilirse parametreleri (U0, U1, Vmp_STC, betaV)
%       doğrudan MPP geriliminden öz-kalibre ederek sanal hücre termometresi (tCellVdc) üretir.
arguments
    tAmb (:,1) double
    gPoa (:,1) double
    windSpeed (:,1) double = zeros(size(tAmb))
    opts.U0 (1,1) double = 25.0                 % doğal konveksiyon + radyasyon, W/(m^2·K)
    opts.U1 (1,1) double = 6.84                 % rüzgar konveksiyon katsayısı, W·s/(m^3·K)
    opts.EtaPv (1,1) double = 0.18              % modül optik/elektriksel dönüşüm payı
    opts.TauMinutes (1,1) double = 10.0         % 1. derece ısıl zaman sabiti, dk
    opts.StepMinutes (1,1) double = 15.0        % zaman adımı, dk
    opts.TmodSat (:,1) double = nan(size(tAmb)) % karşılaştırma için sentetik Ross sıcaklığı
    opts.Vdc (:,1) double = nan(size(tAmb))     % V_dc gerilim termometresi için ölçülen DC gerilim (V)
    opts.Idc (:,1) double = nan(size(tAmb))     % aktif MPPT kontrolü için DC akım (A)
    opts.CalibrateFromVdc (1,1) logical = true
end

n = numel(tAmb);
w = windSpeed(:);
w(isnan(w) | w < 0) = median(w(~isnan(w) & w >= 0), "omitnan");
if all(isnan(w))
    w = zeros(n, 1);
end
g = max(gPoa(:), 0);
g(isnan(gPoa)) = NaN;

% Yarı-kararlı (steady-state) Faiman hücre sıcaklığı
uEff = max(opts.U0 + opts.U1 * w, 8.0);
tCellSs = tAmb(:) + (g .* (1 - opts.EtaPv)) ./ uEff;

% 1. derece ısıl kapasitans (thermal inertia) dinamik filtresi
alphaTh = exp(-opts.StepMinutes / max(opts.TauMinutes, 1e-3));
tCellDyn = tCellSs;
for k = 2:n
    if ~isnan(tCellDyn(k - 1)) && ~isnan(tCellSs(k))
        tCellDyn(k) = alphaTh * tCellDyn(k - 1) + (1 - alphaTh) * tCellSs(k);
    end
end

% Sentetik Ross sıcaklığı (verilmemişse T_amb + 0.028 * G)
tSat = opts.TmodSat(:);
if all(isnan(tSat))
    tSat = tAmb(:) + 0.028 * g;
end
deltaTWind = tSat - tCellDyn;               % pozitif = rüzgar soğutması kazancı (°C)

% V_dc Sanal Hücre Termometresi: V_dc(t) = Vmp_STC + betaV*(T_cell - 25) + cV*ln(G/1000)
vdc = opts.Vdc(:);
idc = opts.Idc(:);
tCellVdc = nan(n, 1);
vmpStc = 198.0;
betaV = -0.68;                              % V/°C (~ -0.34 %/°C)
cV = 4.5;                                   % V / ln(G/1000)

validV = ~isnan(vdc) & vdc > 140 & vdc < 235 & ~isnan(g) & g > 350 & ~isnan(tCellDyn);
if any(~isnan(idc))
    validV = validV & idc > 0.5;
end
if opts.CalibrateFromVdc && nnz(validV) >= 40
    X = [ones(nnz(validV), 1), tCellDyn(validV) - 25, log(g(validV) / 1000)];
    y = vdc(validV);
    b = X \ y;
    r = y - X * b;
    keep = abs(r - median(r)) < 2.5 * 1.4826 * mad(r, 1);
    if nnz(keep) >= 30
        b = X(keep, :) \ y(keep);
    end
    if b(2) < -0.15 && b(2) > -2.0
        vmpStc = b(1);
        betaV = b(2);
        cV = min(max(b(3), 0.5), 15.0);
    end
end

okV = ~isnan(vdc) & vdc > 120 & ~isnan(g) & g > 150;
tCellVdc(okV) = 25 + (vdc(okV) - vmpStc - cV * log(max(g(okV) / 1000, 0.05))) ./ betaV;
tCellVdc = min(max(tCellVdc, tAmb(:) - 5), 95);
tCellVdc(~okV) = NaN;

out = struct("TcellSs", tCellSs, "TcellDyn", tCellDyn, "TcellVdc", tCellVdc, ...
    "TmodSat", tSat, "DeltaTWind", deltaTWind, "DeltaTAnom", tCellVdc - tCellDyn, ...
    "AlphaTh", alphaTh, "U0", opts.U0, "U1", opts.U1, ...
    "VmpStc", vmpStc, "BetaV", betaV, "CvLogG", cV);
end
