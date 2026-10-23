function kind = classifyByHeader(file)
%CLASSIFYBYHEADER Adından tanınamayan raporun türünü sütun başlıklarından çıkarır.
%   kind = ges.io.classifyByHeader(file) — "sma_combined" | "plant" | "meteo" | "inverter" | "unknown".
%   Hem UTF-8 (SMA Sunny Portal: sep=;, 14 satır metadata, 15. satır başlık) hem de
%   UTF-16LE (Huawei SmartLogger: TAB ayraçlı, 1. satır başlık) dosyaları destekler.

arguments
    file (1,1) string {mustBeFile}
end
kind = "unknown";
fid = fopen(file, "r");
if fid < 0
    return
end
bytes = fread(fid, 8192, "*uint8")';
fclose(fid);
if isempty(bytes)
    return
end

% 1) UTF-16LE BOM kontrolü (Huawei SmartLogger)
if numel(bytes) >= 2 && bytes(1) == 255 && bytes(2) == 254
    bytes = bytes(3:end);
    bytes = bytes(1:2 * floor(numel(bytes) / 2));
    txt = char(typecast(bytes, "uint16"));
    line = string(strtok(txt, sprintf("\r\n")));
    if strlength(line) == 0
        return
    end
    cols = lower(strip(erase(split(line, sprintf("\t")), """")));
    has = @(p) any(contains(cols, p));
    if has("input power") || has("pv1 ") || has("pv1(") || any(startsWith(cols, "pv1"))
        kind = "inverter";
    elseif has("daily energy") && has("active power")
        kind = "plant";
    elseif has("irradiance") && ~has("active power")
        kind = "meteo";
    end
    return
end

% 2) UTF-8 / ASCII (SMA Sunny Portal / Data Manager M veya standart CSV)
if numel(bytes) >= 3 && bytes(1) == 239 && bytes(2) == 187 && bytes(3) == 191
    bytes = bytes(4:end); % UTF-8 BOM
end
txt = string(native2unicode(bytes, "UTF-8"));
lines = splitlines(txt);
lines = lines(strlength(strip(lines)) > 0);
if isempty(lines)
    return
end

lowAll = lower(txt);
if startsWith(lower(strip(lines(1))), "sep=") || ...
        (contains(lowAll, "time period") && (contains(lowAll, "sma-data") || contains(lowAll, "smartgridlab") || contains(lowAll, "insolation")))
    kind = "sma_combined";
    return
end

% Standart tek-başlıklı UTF-8 CSV kontrolü
hdrLine = lines(1);
delim = ",";
if contains(hdrLine, ";"), delim = ";"; elseif contains(hdrLine, sprintf("\t")), delim = sprintf("\t"); end
cols = lower(strip(erase(split(hdrLine, delim), """")));
has = @(p) any(contains(cols, p));
if has("dc voltage") || has("input power") || any(startsWith(cols, "pv1"))
    kind = "inverter";
elseif has("daily energy") && has("active power")
    kind = "plant";
elseif (has("irradiance") || has("insolation")) && ~has("active power")
    kind = "meteo";
end
end
