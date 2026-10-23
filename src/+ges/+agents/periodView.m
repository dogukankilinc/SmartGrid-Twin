function V = periodView(ctx, id, dayList)
%PERIODVIEW Bir invertörün birkaç gününün skalogramı + o günün sayısal etiketi (toplu görünüm).
%   V = ges.agents.periodView(ctx, id, dayList) — dayList: gün başlangıçları (datetime vektörü).
%   Her gün için (struct dizisi):
%     Day, Rgb (fizik-RGB skalogram; gün sürüyorsa ctx.Now sonrası maskeli), Ok (veri kapsaması yeterli),
%     Label / LabelTr / Detail (etiketleme fonksiyonlarının gün etiketi: sensör kanıtına dayanır;
%     görsel CNN'in değil), PerfPct (gerçek / beklenen DC enerji), ThrottleHours, ResDefPct.
%   Panelin Analiz sayfasında Günlük (1 gün) ve Haftalık (7 gün) skalogram şeridi için kullanılır.
%   Yalnızca ctx.Now'a kadarki veri kullanılır.
arguments
    ctx (1,1) struct
    id (1,1) string
    dayList (:,1) datetime
end
d = ges.agents.deviceData(ctx, id);
dayList = dateshift(dayList, "start", "day");
% Etiketleme fonksiyonlarının 14 günlük geriye dönük medyanı için pencere 14 gün önceden başlar
win = d.TT.Time >= min(dayList) - days(14) & d.TT.Time < max(dayList) + days(1);
TT = d.TT(win, :);
St = d.Steps(ismember(d.Steps.Time, TT.Time), :);
ev = ctx.Catalog(ctx.Catalog.Id == id, :);
F = table();
if height(TT) > 0
    F = ges.label.dayFeatures(TT, St, d.D, d.info, ev);
    F = ges.label.applyLabelingFunctions(F);
end
names = ["healthy" "string_fault" "inverter_trip" "thermal_derating" "soiling" "grid_event" "uncertain" "unusable"];
namesTr = ["sağlıklı" "string arızası" "invertör durması/trip" "ısıl kısma" "tozlanma olası" ...
    "şebeke/kabin olayı" "belirsiz" "veri yetersiz"];
V = struct("Day", {}, "Rgb", {}, "Ok", {}, "Label", {}, "LabelTr", {}, "Detail", {}, ...
    "PerfPct", {}, "ThrottleHours", {}, "ResDefPct", {});
for k = 1:numel(dayList)
    day = dayList(k);
    until = NaT(TimeZone=day.TimeZone);
    if ctx.Now < day + days(1)
        until = ctx.Now;
    end
    rgb = zeros(64, 64, 3, "single");
    ok = false;
    if any(d.TT.Time >= day & d.TT.Time < day + days(1))
        [sig, ok] = ges.scalogram.dailySignals(d.TT, d.Steps, d.info.Capacity, day, Until=until);
        rgb = ges.scalogram.makeImages(ctx.Norm.fb, sig, ctx.Norm.scale);
    end
    v = struct("Day", day, "Rgb", rgb, "Ok", ok, "Label", "unusable", "LabelTr", "veri yok", "Detail", "", ...
        "PerfPct", NaN, "ThrottleHours", 0, "ResDefPct", NaN);
    if ~isempty(F)
        r = F(F.Day == day, :);
        if ~isempty(r)
            v.Label = string(r.Label);
            v.LabelTr = namesTr(names == v.Label);
            v.Detail = string(r.Detail);
            v.ThrottleHours = r.ThrottleSteps / 4;
            v.ResDefPct = round(100 * r.ResDef, 1);
            if r.ExpectedKwh > 1
                lit = d.TT.Time >= day & d.TT.Time < day + days(1) & d.TT.Elevation > 5 & ~isnan(d.TT.P_dc);
                expRows = ismember(d.Steps.Time, d.TT.Time(lit));
                v.PerfPct = round(100 * sum(d.TT.P_dc(lit)) / sum(d.Steps.Pdc_exp(expRows), "omitnan"), 1);
            end
        end
    end
    V(end+1) = v; %#ok<AGROW>
end
end
