function geo = solarGeometry(t, site, opts)
%SOLARGEOMETRY Zaman damgaları için güneş konumu ve açık gökyüzü bileşenleri.
%   geo = ges.solar.solarGeometry(t, site) — t zaman dilimli datetime.
%   site: latitude, longitude (ve isteğe bağlı altitude, timeAlignment, seasonalTurbidity) alanları.
%   opts.TimeAlignment:
%     "start"  — zaman damgası aralık başlangıcıdır -> t + Step/2 (varsayılan, Huawei uyumlu)
%     "middle" — zaman damgası aralık ortasıdır -> t
%     "end"    — zaman damgası aralık sonudur -> t - Step/2 (SMA Sunny Portal periyot sonu)
%   geo alanları: Zenith, Azimuth, Elevation, GhiCs, DniCs, DhiCs, AirMass, Extraterrestrial, LinkeTurbidity, Declination, EqTime (N×1).
arguments
    t datetime
    site (1,1) struct
    opts.Step (1,1) duration = minutes(15)
    opts.Altitude (1,1) double = NaN
    opts.LinkeTurbidity double = NaN
    opts.TimeAlignment (1,1) string {mustBeMember(opts.TimeAlignment, ["start" "middle" "end"])} = "start"
    opts.SeasonalTurbidity (1,1) logical = false
end

t = t(:);
align = opts.TimeAlignment;
if isfield(site, "timeAlignment") && align == "start"
    align = string(site.timeAlignment);
end
switch align
    case "middle"
        mid = t;
    case "end"
        mid = t - opts.Step / 2;
    otherwise
        mid = t + opts.Step / 2;
end

alt = opts.Altitude;
if isnan(alt)
    if isfield(site, "altitude") && ~isempty(site.altitude) && ~isnan(site.altitude)
        alt = double(site.altitude);
    else
        alt = 100;
    end
end

doy = day(mid, "dayofyear");
tl = opts.LinkeTurbidity;
if all(isnan(tl))
    if opts.SeasonalTurbidity || (isfield(site, "seasonalTurbidity") && logical(site.seasonalTurbidity))
        tl = 3.40 + 0.65 * sin(2 * pi * (doy - 80) / 365);
    elseif isfield(site, "linkeTurbidity") && ~isempty(site.linkeTurbidity)
        tl = site.linkeTurbidity;
    else
        tl = 3.5;
    end
end

[geo.Zenith, geo.Azimuth, geo.Declination, geo.EqTime] = ges.solar.sunPosition(juliandate(mid), site.latitude, site.longitude);
geo.Elevation = 90 - geo.Zenith;
[geo.GhiCs, geo.DniCs, geo.DhiCs, geo.AirMass, geo.Extraterrestrial, tlOut] = ...
    ges.solar.clearSkyIneichen(geo.Zenith, doy, alt, tl);
if isscalar(tlOut)
    geo.LinkeTurbidity = repmat(tlOut, numel(t), 1);
else
    geo.LinkeTurbidity = tlOut(:);
end
end
