function wx = fetchOpenMeteo(latitude, longitude, opts)
%FETCHOPENMETEO Open-Meteo'dan saatlik ışınım/sıcaklık/rüzgar/yağış tahmini (15 dk enterpolasyonlu).
%   wx = ges.forecast.fetchOpenMeteo(lat, lon) — timetable (yerel saat, 15 dk'ya enterpolasyon):
%   GHI, DNI, DHI (W/m^2), Tamb (°C), Cloud (%), WindSpeed (m/s), Precip (mm).
%   Open-Meteo ışınım değerleri ÖNCEKİ saatin ortalamasıdır; zaman damgaları aralık ortasına (−30 dk) kaydırılır.
%   opts.AllowOfflineFallback = true ise bağlantı olmadığında Bölgesel açık/parçalı gök sentetik profili üretir.
arguments
    latitude (1,1) double
    longitude (1,1) double
    opts.Days (1,1) double {mustBeInRange(opts.Days, 1, 7)} = 2
    opts.Timeout (1,1) double = 15
    opts.TimeZone (1,1) string = "Europe/Istanbul"
    opts.AllowOfflineFallback (1,1) logical = false
    opts.StartDate (1,1) datetime = NaT
end

url = "https://api.open-meteo.com/v1/forecast";
try
    raw = webread(url, "latitude", latitude, "longitude", longitude, ...
        "hourly", "shortwave_radiation,direct_normal_irradiance,diffuse_radiation,temperature_2m,cloud_cover,wind_speed_10m,precipitation", ...
        "wind_speed_unit", "ms", ...
        "forecast_days", opts.Days, "timezone", opts.TimeZone, weboptions(Timeout=opts.Timeout));
    h = raw.hourly;
    t = datetime(string(h.time), InputFormat="yyyy-MM-dd'T'HH:mm", TimeZone=opts.TimeZone) - minutes(30);
    if isfield(h, "wind_speed_10m")
        w10 = double(h.wind_speed_10m(:)) * 0.75; % 10 m -> çatı/modül düzlemi rüzgar hızı indirgemesi
    else
        w10 = repmat(0.75, numel(t), 1);
    end
    if isfield(h, "precipitation")
        pr = double(h.precipitation(:));
    else
        pr = zeros(numel(t), 1);
    end
    hourly = timetable(t, double(h.shortwave_radiation(:)), double(h.direct_normal_irradiance(:)), ...
        double(h.diffuse_radiation(:)), double(h.temperature_2m(:)), double(h.cloud_cover(:)), w10, pr, ...
        VariableNames=["GHI" "DNI" "DHI" "Tamb" "Cloud" "WindSpeed" "Precip"]);
    tGrid = (t(1):minutes(15):t(end))';
    wx = retime(hourly, tGrid, "pchip");
    wx.Properties.DimensionNames{1} = 'Time';
    wx.GHI = max(wx.GHI, 0);
    wx.DNI = max(wx.DNI, 0);
    wx.DHI = max(wx.DHI, 0);
    wx.WindSpeed = max(wx.WindSpeed, 0);
    wx.Precip = max(wx.Precip, 0);
    wx.Properties.UserData = struct("Source", "Open-Meteo", "Retrieved", datetime("now"), ...
        "Latitude", latitude, "Longitude", longitude);
catch ME
    if ~opts.AllowOfflineFallback
        rethrow(ME);
    end
    if isnat(opts.StartDate)
        t0 = dateshift(datetime("now", TimeZone=opts.TimeZone), "start", "day");
    else
        t0 = dateshift(opts.StartDate, "start", "day");
        t0.TimeZone = opts.TimeZone;
    end
    tGrid = (t0:minutes(15):(t0 + days(opts.Days) - minutes(15)))';
    site = struct("latitude", latitude, "longitude", longitude, "altitude", 155, "seasonalTurbidity", true);
    geo = ges.solar.solarGeometry(tGrid, site);
    hr = hour(tGrid) + minute(tGrid) / 60;
    tamb = 20 + 6 * sin(2 * pi * (hr - 9) / 24);
    wSpeed = max(0.3, 0.7 + 0.5 * sin(2 * pi * (hr - 10) / 24));
    cloud = repmat(15, numel(tGrid), 1);
    precip = zeros(numel(tGrid), 1);
    wx = timetable(tGrid, geo.GhiCs * 0.92, geo.DniCs * 0.88, geo.DhiCs * 1.05, tamb, cloud, wSpeed, precip, ...
        VariableNames=["GHI" "DNI" "DHI" "Tamb" "Cloud" "WindSpeed" "Precip"]);
    wx.Properties.DimensionNames{1} = 'Time';
    wx.Properties.UserData = struct("Source", "Offline-Synthetic", "Retrieved", datetime("now"), ...
        "Latitude", latitude, "Longitude", longitude);
end
end
