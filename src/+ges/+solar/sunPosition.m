function [zenith, azimuth, decl, eqTime] = sunPosition(jdUtc, latitude, longitude)
%SUNPOSITION Güneşin zenit ve azimut açısı (NOAA algoritması, ~0.01° doğruluk).
%   [zenith, azimuth, decl, eqTime] = ges.solar.sunPosition(jdUtc, lat, lon)
%   jdUtc     : UTC Jülyen günü (ör. juliandate(t) — t zaman dilimli ise UTC'ye çevrilir)
%   latitude  : derece, kuzey pozitif (SmartGrid-Twin: 40.1878)
%   longitude : derece, doğu pozitif (SmartGrid-Twin: 29.1289)
%   zenith    : derece (90'dan büyükse güneş ufkun altında)
%   azimuth   : derece, kuzeyden saat yönünde (180 = güney)
%   decl      : güneş deklinasyon açısı, derece
%   eqTime    : zaman denklemi düzeltmesi, dakika
%
%   Kod üretimine uygundur (yalnızca sayısal eleman bazlı işlemler).

jc = (jdUtc - 2451545) / 36525;                      % Jülyen yüzyılı
l0 = mod(280.46646 + jc .* (36000.76983 + jc * 0.0003032), 360);
m = 357.52911 + jc .* (35999.05029 - 0.0001537 * jc);
e = 0.016708634 - jc .* (0.000042037 + 0.0000001267 * jc);
c = sind(m) .* (1.914602 - jc .* (0.004817 + 0.000014 * jc)) ...
    + sind(2 * m) .* (0.019993 - 0.000101 * jc) + sind(3 * m) * 0.000289;
omega = 125.04 - 1934.136 * jc;
appLong = l0 + c - 0.00569 - 0.00478 * sind(omega);
meanObliq = 23 + (26 + (21.448 - jc .* (46.815 + jc .* (0.00059 - jc * 0.001813))) / 60) / 60;
obliq = meanObliq + 0.00256 * cosd(omega);
decl = asind(sind(obliq) .* sind(appLong));

y = tand(obliq / 2).^2;
eqTime = 4 * rad2deg(y .* sind(2 * l0) - 2 * e .* sind(m) ...
    + 4 * e .* y .* sind(m) .* cosd(2 * l0) - 0.5 * y.^2 .* sind(4 * l0) ...
    - 1.25 * e.^2 .* sind(2 * m));                    % dakika

minutesUtc = mod((jdUtc + 0.5) * 1440, 1440);
trueSolarTime = mod(minutesUtc + eqTime + 4 * longitude, 1440);
hourAngle = trueSolarTime / 4 - 180;

cosZenith = sind(latitude) .* sind(decl) + cosd(latitude) .* cosd(decl) .* cosd(hourAngle);
zenith = acosd(min(max(cosZenith, -1), 1));
azimuth = mod(atan2d(sind(hourAngle), ...
    cosd(hourAngle) .* sind(latitude) - tand(decl) .* cosd(latitude)) + 180, 360);
end
