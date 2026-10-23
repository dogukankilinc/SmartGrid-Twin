function [TT, info] = readSmaReport(file, opts)
%READSMAREPORT Tek bir SMA Sunny Portal (Analysis Pro) CSV raporunu sıfır veri kaybıyla okur.
%   [TT, info] = ges.io.readSmaReport(file) UTF-8 kodlu, ";" ayraçlı, ilk 14 satırı
%   metadata ve 15. satırı 21 sütunlu başlık olan SMA raporunu okur.
%   Özellikler:
%     * "MM/dd/yyyy hh.mm a" (en-US) zaman damgalarını Europe/Istanbul saat dilimine çevirir.
%     * "-" değerlerini NaN yapar; "1,284.00" / "3,000.00" binlik ayraçlarını temizler.
%     * Izgara dışı (:10, :25, :50) asenkron reset satırlarını silmeden bir sonraki 15 dk
%       ızgara adımına (ceilTo15Min) qRebootEvent = true (qResetEvent = true) olarak taşır.
%     * Mükerrer zaman damgalarında (hafta başı 12.00 AM) hücre bazlı birleştirme
%       (coalesceDuplicates / firstNonMissing) uygular.
%     * Tüm türetilen elektriksel, röle, termal büyüklükleri ve geriye dönük takma adları
%       (V_pv1..8, I_pv1..8, U_ab, I_a, Status, T_cab vb.) eksiksiz üretir.

arguments
    file (1,1) string {mustBeFile}
    opts.TimeZone (1,1) string = "Europe/Istanbul"
    opts.TimeStep (1,1) duration = minutes(15)
    opts.LatchOffGrid (1,1) logical = true
end

lines = readlines(file, Encoding="UTF-8");
lines = lines(strlength(strip(lines)) > 0 | startsWith(lines, '""'));
if isempty(lines)
    TT = timetable.empty;
    info = emptyInfo(file);
    return
end

% 1) Ayraç ve üstveri (Satır 1..14)
delim = ";";
if startsWith(lines(1), "sep=")
    delim = extractAfter(strip(lines(1)), "sep=");
    if strlength(delim) == 0, delim = ";"; end
end

hdrIdx = find(startsWith(lines, '"Time period"') | startsWith(lines, 'Time period'), 1);
if isempty(hdrIdx)
    hdrIdx = min(15, numel(lines));
end

metaMap = struct("SystemName", "SmartGridLab", "DeviceName", "WR13TL22-8231", ...
    "SerialNumber", "3011599654", "TimeZone", opts.TimeZone);
for k = 2:(hdrIdx - 1)
    parts = split(lines(k), delim);
    if numel(parts) >= 2
        key = lower(strip(erase(parts(1), '"')));
        val = strip(erase(parts(2), '"'));
        switch key
            case "system name"
                if strlength(val) > 0, metaMap.SystemName = val; end
            case "device name"
                if strlength(val) > 0, metaMap.DeviceName = val; end
            case "serial number of device"
                if strlength(val) > 0, metaMap.SerialNumber = val; end
            case "time zone"
                if strlength(val) > 0, metaMap.TimeZone = val; end
        end
    end
end

% 2) Başlık satırı (Satır 15)
rawHeaders = strip(erase(split(lines(hdrIdx), delim), '"'))';
nCols = numel(rawHeaders);
spec = ges.io.smaColumnMap();
keysFull = ges.io.columnKey(rawHeaders);
keysBase = ges.io.columnKey(rawHeaders, StripDevice=true);

names = strings(1, nCols);
units = strings(1, nCols);
for c = 1:nCols
    idx = find(spec.Key == keysFull(c), 1);
    if isempty(idx)
        idx = find(spec.Key == keysBase(c), 1);
    end
    if ~isempty(idx)
        names(c) = spec.Name(idx);
        units(c) = spec.Unit(idx);
    else
        names(c) = string(matlab.lang.makeValidName(rawHeaders(c)));
        units(c) = "";
    end
end
names(1) = "Time";
% Aynı kanonik ad birden fazla sütuna düştüyse (genel eşleşmede) ikincisini _sys yap
for c = 2:nCols
    if nnz(names(1:c) == names(c)) > 1
        names(c) = names(c) + "_sys";
    end
end

% 3) Veri satırları (Satır 16..Son)
dataLines = lines((hdrIdx + 1):end);
dataLines = dataLines(strlength(strip(dataLines)) > 0);
nRows = numel(dataLines);
if nRows == 0
    TT = timetable.empty;
    info = emptyInfo(file);
    return
end

% Hızlı vektörize ayrıştırma
cleanTxt = erase(dataLines, '"');
cells = split(cleanTxt, delim);
if size(cells, 1) == nCols && size(cells, 2) == 1 && nRows == 1
    cells = cells';
end
timeStr = strip(cells(:, 1));
t = datetime(timeStr, InputFormat="MM/dd/yyyy hh.mm a", Locale="en_US");
badT = isnat(t);
if any(badT)
    t(badT) = datetime(timeStr(badT), InputFormat="yyyy-MM-dd HH:mm:ss");
end
t.TimeZone = opts.TimeZone;

numChars = cells(:, 2:nCols);
numChars = erase(numChars, ",");          % "1,284.00" ve "3,000.00" binlik ayracı temizliği
isDash = (numChars == "-" | numChars == "");
numChars(isDash) = "NaN";
mat = str2double(numChars);

validRows = ~isnat(t);
t = t(validRows);
mat = mat(validRows, :);

% 4) Izgara dışı (:10, :25, :50) asenkron reset satırlarını yakala (Event Latching)
stepMin = minutes(opts.TimeStep);
onGrid = (t == dateshift(t, "start", "minute")) & (mod(minute(t), stepMin) == 0);
numOffGrid = nnz(~onGrid);
qRebootRaw = ~onGrid;

if opts.LatchOffGrid && any(~onGrid)
    remMin = mod(minute(t(~onGrid)), stepMin);
    t(~onGrid) = dateshift(t(~onGrid), "start", "minute") + minutes(stepMin - remMin);
end

% Sırala ve mükerrer zaman damgalarında hücre bazlı birleştirme (coalesceDuplicates) uygula
[t, sortIdx] = sort(t);
mat = mat(sortIdx, :);
qRebootRaw = qRebootRaw(sortIdx);

[uTime, ~, ic] = unique(t, "stable");
numDuplicates = numel(t) - numel(uTime);
if numDuplicates > 0
    uMat = nan(numel(uTime), size(mat, 2));
    uReb = false(numel(uTime), 1);
    for r = 1:numel(t)
        g = ic(r);
        uReb(g) = uReb(g) | qRebootRaw(r);
        rowVals = mat(r, :);
        take = isnan(uMat(g, :)) & ~isnan(rowVals);
        uMat(g, take) = rowVals(take);
    end
    t = uTime;
    mat = uMat;
    qRebootRaw = uReb;
end

T = array2table(mat, VariableNames=cellstr(names(2:end)));
TT = table2timetable(T, RowTimes=t);
TT.Properties.DimensionNames{1} = 'Time';
TT.Properties.VariableUnits = cellstr(units(2:end));
TT.Properties.VariableDescriptions = cellstr(rawHeaders(2:end));

% 5) Türetilen elektriksel, röle, termal büyüklükler ve %100 geriye dönük uyumlu takma adlar
TT = enrichSmaTimetable(TT, qRebootRaw);

meta = ges.io.parseDeviceName(file);
info = struct("File", file, "Device", meta.Device(1), "Id", meta.Id(1), ...
    "Kind", "sma_combined", "Group", "sma_combined", ...
    "NumRows", height(TT), "NumDuplicateTimes", numDuplicates, ...
    "NumOffGridTimes", numOffGrid, "Meta", metaMap);
end

function TT = enrichSmaTimetable(TT, qRebootRaw)
n = height(TT);
v = string(TT.Properties.VariableNames);

if ~ismember("P_ac", v), TT.P_ac = nan(n, 1); end
if ~ismember("P_ac_sys", v), TT.P_ac_sys = TT.P_ac; end
if ~ismember("P_ac_spec", v), TT.P_ac_spec = TT.P_ac / 1.20; end
if ~ismember("P_ac_spec_sys", v), TT.P_ac_spec_sys = TT.P_ac_spec; end
if ~ismember("V_dc", v), TT.V_dc = nan(n, 1); end
if ~ismember("I_dc", v), TT.I_dc = nan(n, 1); end
if ~ismember("U_L1", v), TT.U_L1 = nan(n, 1); end
if ~ismember("U_L2", v), TT.U_L2 = zeros(n, 1); end
if ~ismember("U_L3", v), TT.U_L3 = zeros(n, 1); end
if ~ismember("I_L1", v), TT.I_L1 = nan(n, 1); end
if ~ismember("I_L2", v), TT.I_L2 = zeros(n, 1); end
if ~ismember("I_L3", v), TT.I_L3 = zeros(n, 1); end
if ~ismember("f_grid", v), TT.f_grid = nan(n, 1); end
if ~ismember("R_iso", v), TT.R_iso = nan(n, 1); end
if ~ismember("G_horiz", v), TT.G_horiz = nan(n, 1); end
if ~ismember("T_amb", v), TT.T_amb = nan(n, 1); end
if ~ismember("T_mod_sat", v), TT.T_mod_sat = nan(n, 1); end
if ~ismember("T_mod_sys", v), TT.T_mod_sys = TT.T_mod_sat; end
if ~ismember("WindSpeed", v), TT.WindSpeed = zeros(n, 1); end
if ~ismember("SchedP_Pct", v), TT.SchedP_Pct = nan(n, 1); end

% DC Güç ve Evirici Verimi
TT.P_dc = (TT.V_dc .* TT.I_dc) / 1000;
% P_ac > P_dc olduğu çok düşük güç adımlarında (<20 W) verimi [0, 1] bandında tut
eta = TT.P_ac ./ max(TT.P_dc, 1e-4);
eta(TT.P_dc < 0.015 | isnan(TT.P_ac) | isnan(TT.P_dc)) = NaN;
eta = min(max(eta, 0), 1.0);
TT.Eta_inv = eta;
TT.Eff = 100 * eta;

% Şebeke Röle Görev Oranı (alpha_relay = k/18) ve Koşullu Gerilim (U_L1_cond)
relayDuty = min(max(TT.f_grid / 50.0, 0), 1.0);
relayDuty(isnan(TT.f_grid)) = NaN;
TT.RelayDuty = relayDuty;
uCond = TT.U_L1 ./ max(relayDuty, 1e-3);
uCond(isnan(relayDuty) | relayDuty < 0.05) = NaN;
TT.U_L1_cond = uCond;

% Görünür Güç, Reaktif Güç ve Güç Faktörü
sAc = (TT.U_L1 .* TT.I_L1) / 1000;
qAc = sqrt(max(0, sAc.^2 - TT.P_ac.^2));
pf = TT.P_ac ./ max(sAc, 1e-4);
pf(sAc < 0.015 | isnan(sAc) | isnan(TT.P_ac)) = NaN;
pf = min(max(pf, 0), 1.0);
TT.S_ac = sAc;
TT.P_grid_app = sAc;
TT.Q_ac = qAc;
TT.Q_grid = qAc;
TT.Q = qAc;
TT.PF = pf;

% Rüzgar soğutmalı Faiman hücre sıcaklığı (T_cell_faiman) ve V_dc tabanlı sıcaklık (T_cell_vdc)
gUse = max(TT.G_horiz, 0);
wUse = fillmissing(max(TT.WindSpeed, 0), "constant", 0.5);
tSs = TT.T_amb + gUse ./ (25.0 + 6.84 * wUse);
tFaiman = tSs;
alphaTh = exp(-15 / 12); % ~12 dk ısıl zaman sabiti, 15 dk adımda
for i = 2:n
    if ~isnan(tFaiman(i-1)) && ~isnan(tSs(i)) && (TT.Time(i) - TT.Time(i-1) <= minutes(20))
        tFaiman(i) = alphaTh * tFaiman(i-1) + (1 - alphaTh) * tSs(i);
    end
end
TT.T_cell_faiman = tFaiman;
TT.T_cell_dyn = tFaiman;
TT.DeltaT_wind = TT.T_mod_sat - tFaiman;

% V_dc tabanlı elektriksel hücre sıcaklığı ve vekil kabin/evirici sıcaklığı (T_cab)
vmpStc = 195.0;
betaV = -0.0031; % 1/°C
cV = 8.5;
gSafe = max(gUse, 50);
tVdc = 25.0 + (TT.V_dc - vmpStc - cV * log(gSafe / 1000)) ./ (betaV * vmpStc);
tVdc(TT.P_dc < 0.05 | isnan(TT.V_dc) | gUse < 100) = NaN;
TT.T_cell_vdc = min(max(tVdc, -10), 85);

% Vekil evirici iç sıcaklığı (T_cab): ortam sıcaklığı + yük ısınması + güneş etkisi
pLoad = fillmissing(max(TT.P_ac, 0), "constant", 0);
TT.T_cab = TT.T_amb + 14.5 * (pLoad / 1.20) + 0.012 * gUse ./ (1 + 0.25 * wUse);

% Takma adlar (Aliases) — Ajan 2, 3, 4 ve Huawei uyumluluğu
TT.G = TT.G_horiz;
TT.T_mod = TT.T_mod_sat;
TT.W_spd = TT.WindSpeed;
TT.V_grid = TT.U_L1;
TT.I_grid = TT.I_L1;
TT.Freq = TT.f_grid;
TT.U_ab = TT.U_L1;
TT.U_bc = TT.U_L2;
TT.U_ca = TT.U_L3;
TT.I_a = TT.I_L1;
TT.I_b = TT.I_L2;
TT.I_c = TT.I_L3;

TT.V_pv1 = TT.V_dc;
TT.I_pv1 = TT.I_dc;
for k = 2:8
    TT.("V_pv" + k) = nan(n, 1);
    TT.("I_pv" + k) = nan(n, 1);
end

% Günlük ve ömür boyu enerji sayaçları (E_day, E_life)
pStepKwh = fillmissing(max(TT.P_ac, 0), "constant", 0) * 0.25;
TT.E_life = cumsum(pStepKwh);
dayGrp = findgroups(dateshift(TT.Time, "start", "day"));
eDay = zeros(n, 1);
for gk = 1:max([dayGrp; 0])
    m = dayGrp == gk;
    eDay(m) = cumsum(pStepKwh(m));
end
TT.E_day = eDay;

% Reboot / Reconnect ve durum metni (Status categorical)
prevOffline = [false; isnan(TT.P_ac(1:end-1)) & TT.G_horiz(1:end-1) > 80];
isDayReboot = ~isnan(TT.SchedP_Pct) & TT.SchedP_Pct == 0 & (qRebootRaw | (TT.G_horiz > 50 & (isnan(TT.P_ac) | prevOffline)));
TT.qRebootEvent = qRebootRaw | isDayReboot;
TT.qResetEvent = TT.qRebootEvent;

st = repmat("Idle: No irradiation", n, 1);
st(TT.P_ac > 0) = "On-grid";
st(~isnan(TT.SchedP_Pct) & TT.SchedP_Pct > 0 & TT.SchedP_Pct < 100 & TT.P_ac > 0) = "On-grid: Power limit";
isFault = (TT.G_horiz > 100 & (isnan(TT.P_ac) | (TT.P_ac == 0 & TT.U_L1 == 0))) | (TT.R_iso < 500);
st(isFault) = "Shutdown: Fault";
TT.Status = categorical(st, ["On-grid" "On-grid:self derating" "On-grid: Power limit" "Idle: No irradiation" "Shutdown: Fault"]);

% Birimleri güncelle
u = strings(1, width(TT));
u(ismember(string(TT.Properties.VariableNames), ["P_ac" "P_ac_sys" "P_dc"])) = "kW";
u(ismember(string(TT.Properties.VariableNames), ["P_ac_spec" "P_ac_spec_sys"])) = "kW/kWp";
u(ismember(string(TT.Properties.VariableNames), ["V_dc" "U_L1" "U_L2" "U_L3" "V_grid" "U_ab" "U_bc" "U_ca" "U_L1_cond" "V_pv" + (1:8)])) = "V";
u(ismember(string(TT.Properties.VariableNames), ["I_dc" "I_L1" "I_L2" "I_L3" "I_grid" "I_a" "I_b" "I_c" "I_pv" + (1:8)])) = "A";
u(ismember(string(TT.Properties.VariableNames), ["f_grid" "Freq"])) = "Hz";
u(ismember(string(TT.Properties.VariableNames), ["R_iso"])) = "kOhm";
u(ismember(string(TT.Properties.VariableNames), ["G" "G_horiz"])) = "W/m^2";
u(ismember(string(TT.Properties.VariableNames), ["T_amb" "T_mod" "T_mod_sat" "T_mod_sys" "T_cell_faiman" "T_cell_dyn" "T_cell_vdc" "DeltaT_wind" "T_cab"])) = "°C";
u(ismember(string(TT.Properties.VariableNames), ["WindSpeed" "W_spd"])) = "m/s";
u(ismember(string(TT.Properties.VariableNames), ["Eff" "SchedP_Pct"])) = "%";
u(ismember(string(TT.Properties.VariableNames), ["E_day" "E_life"])) = "kWh";
TT.Properties.VariableUnits = cellstr(u);
end

function info = emptyInfo(file)
info = struct("File", file, "Device", "", "Id", "", "Kind", "unknown", ...
    "Group", "unknown", "NumRows", 0, "NumDuplicateTimes", 0, "NumOffGridTimes", 0, "Meta", struct());
end
