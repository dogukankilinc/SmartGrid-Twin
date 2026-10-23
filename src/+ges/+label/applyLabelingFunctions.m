function F = applyLabelingFunctions(F, opts)
%APPLYLABELINGFUNCTIONS Zayıf denetim: etiketleme fonksiyonlarıyla invertör-günü etiketi.
%   F = ges.label.applyLabelingFunctions(F) — F, TEK bir invertörün
%   ges.label.dayFeatures tablosu (günlere göre sıralı). Eklenen sütunlar:
%     Votes       — oy veren tüm fonksiyonlar ("grid|dead" gibi)
%     Label       — öncelik sırasına göre tek etiket (Seviye-2):
%                   grid_event > inverter_trip > string_fault(dead) > thermal_derating
%                   > string_fault(weak) > soiling > healthy; hiçbiri -> uncertain;
%                   veri yetersiz -> unusable
%     Detail      — alt tip: dead/weak/voltage_drop, fault_status/idle_no_dc/zero_output,
%                   strong/lowinfo/over/transient (sağlıklı türleri), V/I imzası / planlı güç sınırı
%     L1          — healthy / unhealthy / uncertain / unusable (Seviye-1)
%     Confidence  — kuralın güvenilirliği (0..1); belirsiz = 0
%     LabelSource — "lf" (etiketleme fonksiyonu)
arguments
    F table
    opts.MinSteps (1,1) double = 4
    opts.WeakMinSteps (1,1) double = 8
    opts.HealthyMaxDeficit (1,1) double = 0.04
    opts.SoilingRange (1,2) double = [0.04 0.15]
end

n = height(F);
k = opts.MinSteps;
fVars = F.Properties.VariableNames;
usable = F.Coverage >= 0.6 & F.LitSteps > 8;
% Gündüz gerçekleşen tekil şebeke/kesici veya reset olaylarını da yakalamak için:
hasDayReboot = false(n, 1);
if ismember("RebootSteps", fVars)
    hasDayReboot = F.RebootSteps > 0;
end
vGrid = F.GridSteps >= k | (F.GridSteps >= 1 & ismember("RisoMin", fVars) & F.RisoMin < 1300 & F.Coverage < 0.6);
vTrip = F.TripSteps >= k | (F.TripSteps >= 1 & hasDayReboot);
vDead = F.DeadSteps >= k;
vDerate = F.DerateSteps >= k | (ismember("ThrottleSteps", fVars) & F.ThrottleSteps >= 1 & hasDayReboot);
noEvents = ~vGrid & ~vTrip & ~vDead & ~vDerate & F.OfflineSteps < k;
vWeak = noEvents & (F.WeakSteps >= opts.WeakMinSteps | ...
    (ismember("MiddayLowIsoSteps", fVars) & F.MiddayLowIsoSteps >= k & F.ResDef >= 0.03));
clean = noEvents & ~vWeak & F.WeakSteps < k;
sunny = F.Sky == "clear" | F.Sky == "partly";
enough = F.ValidSteps >= 12;

% Kısa veri setlerinde (örn. 11 haftalık SmartGridLab) 7 günlük, uzun veride 14 günlük nedensel medyan
winMed = 13;
if n < 120
    winMed = 6;
end
rolling = movmedian(F.ResDef, [winMed 0], "omitmissing");
vSoil = clean & sunny & enough ...
    & F.ResDef >= opts.SoilingRange(1) & F.ResDef <= opts.SoilingRange(2) ...
    & rolling >= opts.SoilingRange(1);
if all(ismember(["HasThrottleSig" "TcabMax"], fVars))
    vSoil = vSoil & ~(~F.HasThrottleSig & F.TcabMax >= 58);
end
hStrong = clean & enough & F.Def2Steps == 0 & abs(F.ResDef) < opts.HealthyMaxDeficit;
hLowInfo = clean & ~enough & F.Def3Steps == 0;
hOver = clean & enough & F.Def2Steps == 0 & F.ResDef <= -opts.HealthyMaxDeficit;
hTransient = clean & F.Def3Steps == 0 & F.Def2Steps > 0 & F.Def2Steps <= 4 & abs(F.ResDef) < 0.05;
vHealthy = hStrong | hLowInfo | hOver | hTransient;

names = ["grid" "trip" "dead" "derate" "weak" "soiling" "healthy"];
V = [vGrid vTrip vDead vDerate vWeak vSoil vHealthy];
votes = strings(n, 1);
for i = 1:n
    votes(i) = strjoin(names(V(i, :)), "|");
end

label = repmat("uncertain", n, 1);
detail = repmat("", n, 1);
conf = zeros(n, 1);
% Düşük öncelikten yükseğe yazılır; sonraki atama öncekini ezer.
label(hTransient) = "healthy";   detail(hTransient) = "transient"; conf(hTransient) = 0.6;
label(hOver) = "healthy";        detail(hOver) = "over";           conf(hOver) = 0.6;
label(hLowInfo) = "healthy";     detail(hLowInfo) = "lowinfo";     conf(hLowInfo) = 0.6;
label(hStrong) = "healthy";      detail(hStrong) = "strong";       conf(hStrong) = 0.85;
label(vSoil) = "soiling";        detail(vSoil) = "";               conf(vSoil) = 0.5;
label(vWeak) = "string_fault";   detail(vWeak) = "weak";           conf(vWeak) = 0.6;
if ismember("MiddayLowIsoSteps", fVars)
    detail(vWeak & F.MiddayLowIsoSteps >= k) = "weak (düşük R_iso)";
end
label(vDerate) = "thermal_derating"; detail(vDerate) = "";         conf(vDerate) = 0.9;
if ismember("ThrottleSteps", fVars)
    hidden = vDerate & (F.ThrottleSteps >= k | (F.ThrottleSteps >= 1 & hasDayReboot)) & F.StatusDerateSteps < k;
    detail(hidden) = "V/I imzası";
    if ismember("HasThrottleSig", fVars)
        detail(hidden & ~F.HasThrottleSig) = "güç+sıcaklık imzası";
    end
    if ismember("PowerLimitSteps", fVars)
        detail(vDerate & F.PowerLimitSteps >= k & F.ThrottleSteps < k) = "planlı güç sınırı (SchedP_Pct)";
    end
    detail(vDerate & F.StatusDerateSteps >= k) = "durum kodu";
end
label(vDead) = "string_fault";   detail(vDead) = "dead";           conf(vDead) = 0.9;
if ismember("VoltageDropSteps", fVars)
    detail(vDead & F.VoltageDropSteps >= k) = "voltage_drop";
end
label(vTrip) = "inverter_trip";  detail(vTrip) = F.TripKind(vTrip);
conf(vTrip & F.TripKind == "fault_status") = 0.95;
conf(vTrip & F.TripKind == "idle_no_dc") = 0.9;
conf(vTrip & ~ismember(F.TripKind, ["fault_status" "idle_no_dc"])) = 0.8;
label(vGrid) = "grid_event";     detail(vGrid) = "";               conf(vGrid) = 0.95;

% Tam gün kesinti olmayan ama 29 Temmuz gibi gündüz tekil şebeke/uyanış denemesi olan günlerde
% eğer vGrid veya vTrip tetiklendiyse unusable ezmesin, aksi halde unusable:
label(~usable & ~vGrid & ~vTrip & ~vDerate) = "unusable";
detail(~usable & ~vGrid & ~vTrip & ~vDerate) = "";
conf(~usable & ~vGrid & ~vTrip & ~vDerate) = 0;

l1 = repmat("unhealthy", n, 1);
l1(label == "healthy") = "healthy";
l1(label == "uncertain") = "uncertain";
l1(label == "unusable") = "unusable";

classes = ["healthy" "string_fault" "inverter_trip" "thermal_derating" "soiling" "grid_event" "uncertain" "unusable"];
F.Votes = votes;
F.Label = categorical(label, classes);
F.Detail = detail;
F.L1 = categorical(l1, ["healthy" "unhealthy" "uncertain" "unusable"]);
F.Confidence = conf;
F.LabelSource = repmat("lf", n, 1);
end
