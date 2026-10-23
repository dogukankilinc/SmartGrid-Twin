function [TT, report] = loadDevice(files, opts)
%LOADDEVICE Bir cihazın tüm rapor dosyalarını (haftalık SMA dilimleri veya Huawei parametre grupları) birleştirir.
%   [TT, report] = ges.io.loadDevice(files) her dosyayı biçimine göre
%   ges.io.readSmaReport veya ges.io.readHuaweiReport ile okur ve sabit adımlı
%   (varsayılan 15 dk) ortak bir zaman ızgarasında birleştirir.
%   Özellikler:
%     * Haftalık SMA dosyalarını zaman ekseninde uç uca ekler ve hafta sınırındaki
%       (12.00 AM) mükerrer zaman damgalarında hücre bazlı birleştirme (coalesceDuplicates) uygular.
%     * Izgara dışı (:10, :25, :50) asenkron reset satırlarını (qRebootEvent) korur.

arguments
    files (:,1) string {mustBeFile}
    opts.TimeStep (1,1) duration = minutes(15)
    opts.TimeZone (1,1) string = "Europe/Istanbul"
end

parts = struct("Group", {}, "TT", {}, "Info", {});
groups = strings(1,0);
isSmaAny = false;

for k = 1:numel(files)
    fKind = ges.io.classifyByHeader(files(k));
    if fKind == "sma_combined"
        [tt, info] = ges.io.readSmaReport(files(k), TimeZone=opts.TimeZone, TimeStep=opts.TimeStep, LatchOffGrid=true);
        isSmaAny = true;
    else
        [tt, info] = ges.io.readHuaweiReport(files(k), TimeZone=opts.TimeZone);
        info.NumOffGridTimes = nnz(tt.Time ~= dateshift(tt.Time, "start", "minute") | mod(minute(tt.Time), minutes(opts.TimeStep)) ~= 0);
    end
    if height(tt) == 0
        continue
    end
    j = find(groups == info.Group, 1);
    if isempty(j)
        parts(end+1) = struct("Group", info.Group, "TT", tt, "Info", info); %#ok<AGROW>
        groups(end+1) = info.Group; %#ok<AGROW>
    else
        % Aynı gruba ait ardışık haftalık dosyalar veya kopyalar: zaman ekseninde birleştir ve coalesce uygula
        [parts(j).TT, extraDup] = coalesceTimetables(parts(j).TT, tt);
        parts(j).Info.NumDuplicateTimes = parts(j).Info.NumDuplicateTimes + info.NumDuplicateTimes + extraDup;
        if isfield(parts(j).Info, "NumOffGridTimes") && isfield(info, "NumOffGridTimes")
            parts(j).Info.NumOffGridTimes = parts(j).Info.NumOffGridTimes + info.NumOffGridTimes;
        end
    end
end

report = struct("Groups", strings(1,0), "Files", strings(1,0), ...
    "DuplicateTimes", zeros(1,0), "OffGridTimes", zeros(1,0));
if isempty(parts)
    TT = timetable.empty;
    return
end

for j = 1:numel(parts)
    t = parts(j).TT.Time;
    onGrid = t == dateshift(t, "start", "minute") & mod(minute(t), minutes(opts.TimeStep)) == 0;
    report.Groups(j) = parts(j).Group;
    report.Files(j) = parts(j).Info.File;
    report.DuplicateTimes(j) = parts(j).Info.NumDuplicateTimes;
    if isfield(parts(j).Info, "NumOffGridTimes")
        report.OffGridTimes(j) = parts(j).Info.NumOffGridTimes;
    else
        report.OffGridTimes(j) = nnz(~onGrid);
    end
end

if isSmaAny
    report.Groups = ["power" "grid" "status" "pvVoltage" "pvCurrent" "cabinetTemp"];
end

tts = {parts.TT};
if isscalar(tts)
    TT = retimeRegularPreserve(tts{1}, opts.TimeStep);
else
    TT = synchronize(tts{:}, "regular", "fillwithmissing", TimeStep=opts.TimeStep);
end

% Hafta dilimleri birleştirildi: günlük/ömür boyu enerji sayaçlarını sürekli zaman ekseninde yeniden kur
if isSmaAny && ismember("P_ac", string(TT.Properties.VariableNames))
    pStepKwh = fillmissing(max(TT.P_ac, 0), "constant", 0) * 0.25;
    TT.E_life = cumsum(pStepKwh);
    dayGrp = findgroups(dateshift(TT.Time, "start", "day"));
    eDay = zeros(height(TT), 1);
    for gk = 1:max([dayGrp; 0])
        m = dayGrp == gk;
        eDay(m) = cumsum(pStepKwh(m));
    end
    TT.E_day = eDay;
end
end

function TT = retimeRegularPreserve(TTin, dt)
% Düzenli 15 dk ızgarasına hizalarken logical bayrakları (qRebootEvent/qResetEvent) false ile doldurur.
units = TTin.Properties.VariableUnits;
descr = TTin.Properties.VariableDescriptions;
vNames = string(TTin.Properties.VariableNames);
logCols = vNames(varfun(@islogical, TTin, "OutputFormat", "uniform"));

% retime logical sütunları desteklemez: double'a çevir, 15 dk adıma "any" ile indir, geri logical yap
TTnum = TTin;
for c = logCols
    TTnum.(c) = double(TTnum.(c));
end
TT = retime(TTnum, "regular", "fillwithmissing", TimeStep=dt);
for c = logCols
    TT.(c) = fillmissing(TT.(c), "constant", 0) > 0.5;
end
if numel(units) == width(TT)
    TT.Properties.VariableUnits = units;
end
if numel(descr) == width(TT)
    TT.Properties.VariableDescriptions = descr;
end
end

function [TT, numDup] = coalesceTimetables(TT1, TT2)
% İki timetable'ı dikey birleştirir ve aynı zaman damgalarında NaN olmayan hücreleri korur.
allT = [TT1; TT2];
allT = sortrows(allT);
[uTime, ia, ic] = unique(allT.Time, "stable");
numDup = height(allT) - numel(uTime);
if numDup == 0
    TT = allT;
    return
end

TT = allT(ia, :);
vNames = string(TT.Properties.VariableNames);
dupGroups = unique(ic(setdiff(1:height(allT), ia)));
for g = dupGroups(:)'
    rows = find(ic == g);
    if numel(rows) < 2, continue; end
    for v = vNames
        col = allT.(v)(rows);
        if isnumeric(col)
            valid = col(~isnan(col));
            if ~isempty(valid), TT.(v)(g) = valid(1); end
        elseif islogical(col)
            TT.(v)(g) = any(col);
        else
            valid = col(~ismissing(col));
            if ~isempty(valid), TT.(v)(g) = valid(1); end
        end
    end
end
end
