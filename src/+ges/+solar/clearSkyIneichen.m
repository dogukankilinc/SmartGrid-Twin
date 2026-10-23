function [ghi, dni, dhi, amAbs, i0, tl] = clearSkyIneichen(zenith, dayOfYear, altitude, linkeTurbidity)
%CLEARSKYINEICHEN Ineichen-Perez açık gökyüzü ışınım modeli (W/m^2).
%   [ghi, dni, dhi, amAbs, i0, tl] = ges.solar.clearSkyIneichen(zenith, doy, altitude, TL)
%   zenith          : güneş zenit açısı, derece
%   dayOfYear       : yılın günü (1..366)
%   altitude        : rakım, m (varsayılan: 155 m, SmartGrid-Twin)
%   linkeTurbidity  : Linke bulanıklık katsayısı (skaler, vektör veya NaN/boş ise
%                     Mevsimsel sinüzoidal Linke bulanıklık profili: TL(DOY) = 3.4 + 0.65*sin(2*pi*(DOY-80)/365))
%
%   Kaynak: Ineichen & Perez (2002), pvlib.clearsky.ineichen uygulaması.
%   Kod üretimine uygundur.

if nargin < 3 || isempty(altitude) || all(isnan(altitude))
    altitude = 155;
end
if nargin < 4 || isempty(linkeTurbidity) || all(isnan(linkeTurbidity)) || all(linkeTurbidity <= 0)
    tl = 3.40 + 0.65 * sin(2 * pi * (dayOfYear - 80) / 365);
else
    tl = linkeTurbidity;
end

cosZ = cosd(zenith);
up = cosZ > 0.01;
i0 = 1361 * (1 + 0.033 * cos(2 * pi * dayOfYear / 365));          % dünya dışı normal ışınım

z = min(zenith, 89.9);
amRel = 1 ./ (cosd(z) + 0.50572 * (96.07995 - z).^(-1.6364));     % Kasten-Young (1989)
amAbs = amRel .* exp(-altitude / 8434.5);                          % basınç düzeltmeli hava kütlesi

fh1 = exp(-altitude / 8000);
fh2 = exp(-altitude / 1250);
cg1 = 5.09e-5 * altitude + 0.868;
cg2 = 3.92e-5 * altitude + 0.0387;

ghi = cg1 .* i0 .* cosZ .* max(exp(-cg2 .* amAbs .* (fh1 + fh2 .* (tl - 1))), 0) ...
    .* exp(0.01 * amAbs.^1.8);

b = 0.664 + 0.163 ./ fh1;
dniBeam = i0 .* max(b .* exp(-0.09 * amAbs .* (tl - 1)), 0);
dniLimit = ghi .* min(max((1 - (0.1 - 0.2 * exp(-tl)) ./ (0.1 + 0.882 ./ fh1)) ./ max(cosZ, 0.01), 0), 1e20);
dni = min(dniBeam, dniLimit);

ghi(~up) = 0;
dni(~up) = 0;
dhi = max(ghi - dni .* cosZ, 0);
end
