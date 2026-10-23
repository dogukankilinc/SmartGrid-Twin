function meta = parseDeviceName(fileNames)
%PARSEDEVICENAME Rapor dosya adlarından cihaz kimliğini çıkarır.
%   meta = ges.io.parseDeviceName(fileNames) her dosya için Device (ham ad),
%   Id (kısa kimlik, ör. "K01-INV01" veya "K02-INV21"), Kind (sma_combined/
%   inverter/meteo/logger/loggerControl/plant/unknown), Cabin, Inv ve
%   StringTag sütunlarından oluşan bir tablo döndürür.
%   Hem SMA Sunny Portal ("Analysis Pro - Week - Data Manager...") hem de
%   Huawei SmartLogger ("Report_Kabin2-INV21...") dosya adlarını destekler.

arguments
    fileNames (:,1) string
end

n = numel(fileNames);
Device = strings(n,1);
Id = strings(n,1);
Kind = strings(n,1);
Cabin = nan(n,1);
Inv = nan(n,1);
StringTag = nan(n,1);

for k = 1:n
    [~, baseName, ext] = fileparts(fileNames(k));
    fn = baseName + ext;

    % 1) SMA Sunny Portal / SmartGridLab birleşik raporları
    if startsWith(fn, "Analysis Pro", "IgnoreCase", true) || contains(fn, "Smart Grid Laboratory", "IgnoreCase", true) || contains(fn, "WR13TL22", "IgnoreCase", true)
        Device(k) = "WR13TL22-8231";
        Id(k) = "K01-INV01";
        Kind(k) = "sma_combined";
        Cabin(k) = 1;
        Inv(k) = 1;
        StringTag(k) = 1;
        continue
    end

    % 2) Huawei SmartLogger raporları (geriye dönük birim test uyumluluğu)
    tok = regexp(fn, "^Report_(.+)_\d{8}_\d+\.csv$", "tokens", "once");
    if isempty(tok)
        Device(k) = erase(fn, ".csv");
    else
        Device(k) = tok(1);
    end
    d = Device(k);

    t = regexp(d, "^Kabin(\d+)-INV(\d+)(-\d+STR)?$", "tokens", "once");
    if ~isempty(t)
        Kind(k) = "inverter";
        Cabin(k) = double(t(1));
        Inv(k) = double(t(2));
        StringTag(k) = double(erase(t(3), ["-" "STR"]));
        Id(k) = sprintf("K%02d-INV%02d", Cabin(k), Inv(k));
        continue
    end

    t = regexp(d, "^Kabin(\d+)-Meteoroloji$", "tokens", "once");
    if ~isempty(t)
        Kind(k) = "meteo";
        Cabin(k) = double(t(1));
        Id(k) = sprintf("K%02d-METEO", Cabin(k));
        continue
    end

    t = regexp(d, "^KABIN-(\d+)_SmartLogger(_ControlData)?$", "tokens", "once");
    if ~isempty(t)
        Cabin(k) = double(t(1));
        if numel(t) == 2 && strlength(t(2)) > 0
            Kind(k) = "loggerControl";
            Id(k) = sprintf("K%02d-LOGGERCTRL", Cabin(k));
        else
            Kind(k) = "logger";
            Id(k) = sprintf("K%02d-LOGGER", Cabin(k));
        end
        continue
    end

    Kind(k) = "unknown";
    Id(k) = matlab.lang.makeValidName(d);
end

meta = table(Device, Id, Kind, Cabin, Inv, StringTag);
end
