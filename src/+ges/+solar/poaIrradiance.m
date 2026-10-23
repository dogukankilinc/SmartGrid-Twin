function [poa, details] = poaIrradiance(ghi, dni, dhi, zenith, sunAzimuth, tilt, surfaceAzimuth, albedo, opts)
%POAIRRADIANCE Eğimli yüzeye düşen ışınım (izotropik veya HDKR anizotropik + ASHRAE IAM modeli, W/m^2).
%   poa = ges.solar.poaIrradiance(ghi, dni, dhi, zenith, sunAz, tilt, surfAz, albedo)
%   [poa, details] = ges.solar.poaIrradiance(..., Model="hdkr", ApplyIam=true, IamB0=0.05)
%
%   Açılar derece; surfaceAzimuth kuzeyden saat yönünde (180 = güney).
%   Zaman serileri N×1, tilt/surfaceAzimuth 1×K verilirse N×K matris
%   döner (ızgara araması için örtük genişletme). Kod üretimine uygundur.
%   Varsayılan Model="isotropic" ve ApplyIam=false mevcut tüm çağrılarla %100 geriye dönük uyumludur.
arguments
    ghi double
    dni double
    dhi double
    zenith double
    sunAzimuth double
    tilt double
    surfaceAzimuth double
    albedo (1,1) double = 0.2
    opts.Model (1,1) string {mustBeMember(opts.Model, ["isotropic" "hdkr"])} = "isotropic"
    opts.ApplyIam (1,1) logical = false
    opts.IamB0 (1,1) double = 0.05
    opts.Extraterrestrial double = 1361
end

cosAoi = cosd(zenith) .* cosd(tilt) + sind(zenith) .* sind(tilt) .* cosd(sunAzimuth - surfaceAzimuth);
cosAoiPos = max(cosAoi, 0);

if opts.Model == "hdkr"
    cosZ = max(cosd(zenith), 0.05);
    ai = min(max(dni ./ max(opts.Extraterrestrial, 100), 0), 0.95);
    f = sqrt(max(ghi - dhi, 0) ./ max(ghi, 1));
    beam = (dni + dhi .* (ai ./ cosZ)) .* cosAoiPos;
    sky = dhi .* (1 - ai) .* ((1 + cosd(tilt)) / 2) .* (1 + f .* (sind(tilt / 2).^3));
else
    beam = dni .* cosAoiPos;
    sky = dhi .* (1 + cosd(tilt)) / 2;
end
ground = ghi .* albedo .* (1 - cosd(tilt)) / 2;
poa = max(beam + sky + ground, 0);

iam = 1 - opts.IamB0 .* (1 ./ max(cosAoi, 0.1) - 1);
iam(cosAoi <= 0.05) = 0;
iam = min(max(iam, 0), 1);

poaEff = max(beam .* iam + sky * (1 - 0.5 * opts.IamB0) + ground * (1 - 0.5 * opts.IamB0), 0);
if opts.ApplyIam
    poa = poaEff;
end

if nargout > 1
    details = struct("PoaTotal", beam + sky + ground, "PoaEffective", poaEff, ...
        "Beam", beam, "SkyDiffuse", sky, "GroundReflected", ground, ...
        "CosAoi", cosAoi, "AoiDeg", acosd(min(max(cosAoi, -1), 1)), "Iam", iam);
end
end
