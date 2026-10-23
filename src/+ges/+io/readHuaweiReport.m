function [TT, info] = readHuaweiReport(file, opts)
%READHUAWEIREPORT Tek bir Huawei SmartLogger CSV raporunu timetable olarak okur.
%   [TT, info] = ges.io.readHuaweiReport(file) UTF-16LE kodlu, TAB ayraçlı
%   raporu okur. Sütunlar kanonik adlara çevrilir (ges.io.huaweiColumnMap);
%   orijinal adlar VariableDescriptions'a, birimler VariableUnits'e yazılır.
%   Durum metinleri categorical olur. Yinelenen zaman damgalarından ilki
%   tutulur; satırlar zamana göre sıralanır.
%
%   info alanları: File, Device, Id, Kind, Group, NumRows, NumDuplicateTimes.
arguments
    file (1,1) string {mustBeFile}
    opts.TimeZone (1,1) string = "Europe/Istanbul"
end

io = detectImportOptions(file, FileType="text", Delimiter="\t", ...
    Encoding="UTF-16LE", VariableNamingRule="preserve", TextType="string");
original = string(io.VariableNames);
original = original(~matches(original, regexpPattern("^(Extra)?Var\d+$")));
io.SelectedVariableNames = cellstr(original);

timeName = original(1);
if timeName ~= "Generated On"
    error("ges:io:unexpectedHeader", "Beklenmeyen ilk sütun '%s' (%s)", timeName, file);
end
io = setvartype(io, timeName, "datetime");
io = setvaropts(io, timeName, InputFormat="yyyy-MM-dd HH:mm:ss");

spec = ges.io.huaweiColumnMap();
[found, loc] = ismember(ges.io.columnKey(original), spec.Key);
names = string(matlab.lang.makeValidName(original));
names(found) = spec.Name(loc(found));
units = strings(size(names));
units(found) = spec.Unit(loc(found));
names(1) = "Time";
unknown = ~found;
unknown(1) = false;
if any(unknown)
    warning("ges:io:unknownColumn", "Tanınmayan sütun(lar) %s: %s", file, strjoin(original(unknown), ", "));
end

isText = ismember(names, ["Status" "WindDir" "SchedP_Mode" "SchedQ_Mode" "SchedQ_Profile"]);
if any(isText)
    io = setvartype(io, original(isText), "string");
end

T = readtable(file, io);
T.Properties.VariableNames = cellstr(names);
T(isnat(T.Time),:) = [];

TT = table2timetable(T, RowTimes="Time");
TT.Properties.VariableUnits = cellstr(units(2:end));
TT.Properties.VariableDescriptions = cellstr(original(2:end));
for v = names(isText)
    TT.(v) = categorical(strip(TT.(v)));
end

rt = TT.Time;
rt.TimeZone = opts.TimeZone;
TT.Time = rt;
TT = sortrows(TT);
[~, keep] = unique(TT.Time, "stable");
numDuplicates = height(TT) - numel(keep);
TT = TT(keep,:);

meta = ges.io.parseDeviceName(file);
info = struct("File", file, "Device", meta.Device, "Id", meta.Id, "Kind", meta.Kind, ...
    "Group", detectGroup(string(TT.Properties.VariableNames)), ...
    "NumRows", height(TT), "NumDuplicateTimes", numDuplicates);
end

function group = detectGroup(v)
% Parametre grubunu sütun içeriğinden belirler.
if any(v == "P_dc")
    group = "power";
elseif any(v == "I_a")
    group = "grid";
elseif any(v == "Eff")
    group = "status";
elseif any(v == "V_pv1")
    group = "pvVoltage";
elseif any(v == "I_pv1")
    group = "pvCurrent";
elseif any(v == "T_cab")
    group = "cabinetTemp";
elseif any(v == "G") && any(v == "P_ac")
    group = "plant";
elseif any(v == "G")
    group = "meteo";
elseif any(v == "SchedP_Mode")
    group = "loggerControl";
elseif any(v == "P_ac")
    group = "logger";
else
    group = "unknown";
end
end
