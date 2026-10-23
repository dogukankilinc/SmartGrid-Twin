function [t0, t1] = fileSpan(file)
%FILESPAN Ham raporun ilk ve son zaman damgası (dosyayı tümüyle okumadan; önizleme için).
%   [t0, t1] = ges.ingest.fileSpan(file) — Hem UTF-8 SMA Sunny Portal ("MM/dd/yyyy hh.mm AM/PM")
%   hem de UTF-16LE Huawei ("yyyy-MM-dd HH:mm:ss") raporlarını destekler.

t0 = NaT;
t1 = NaT;
fid = fopen(file, "r");
if fid < 0
    return
end
c = onCleanup(@() fclose(fid));
headBytes = fread(fid, 8192, "*uint8")';
isUtf16 = numel(headBytes) >= 2 && headBytes(1) == 255 && headBytes(2) == 254;
head = decodeBytes(headBytes, isUtf16);

fseek(fid, 0, "eof");
n = ftell(fid);
offset = max(0, n - 8192);
if isUtf16
    offset = max(2, 2 * floor(offset / 2));
end
fseek(fid, offset, "bof");
tail = decodeBytes(fread(fid, 8192, "*uint8")', isUtf16);

t0 = parseEdgeTime(splitlines(head), "first");
t1 = parseEdgeTime(splitlines(tail), "last");
end

function s = decodeBytes(b, isUtf16)
if isUtf16
    if numel(b) >= 2 && b(1) == 255 && b(2) == 254
        b = b(3:end);
    end
    b = b(1:2 * floor(numel(b) / 2));
    s = string(char(typecast(b, "uint16")));
else
    if numel(b) >= 3 && b(1) == 239 && b(2) == 187 && b(3) == 191
        b = b(4:end);
    end
    s = string(native2unicode(b, "UTF-8"));
end
end

function t = parseEdgeTime(lines, which)
t = NaT;
% 1) SMA Sunny Portal biçimi: "07/27/2026 12.00 AM"
vSma = regexp(lines, '^\s*"?(\d{2}/\d{2}/\d{4}\s+\d{2}\.\d{2}\s+[AP]M)"?', "tokens", "once");
vSma = vSma(~cellfun(@isempty, vSma));
if ~isempty(vSma)
    if which == "first", s = vSma{1}{1}; else, s = vSma{end}{1}; end
    t = datetime(s, InputFormat="MM/dd/yyyy hh.mm a", Locale="en_US");
    return
end

% 2) Huawei biçimi: "2025-06-01 04:30:00"
vHua = regexp(lines, '^\s*"?\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', "tokens", "once");
vHua = vHua(~cellfun(@isempty, vHua));
if ~isempty(vHua)
    if which == "first", s = vHua{1}{1}; else, s = vHua{end}{1}; end
    t = datetime(s, InputFormat="yyyy-MM-dd HH:mm:ss");
end
end
