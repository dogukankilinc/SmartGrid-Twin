function state = healthState(TT, s, events, opts)
%HEALTHSTATE Arayüz için adım düzeyinde invertör sağlık durumu.
%   state = ges.anomaly.healthState(TT, s, events) — s ges.anomaly.detectSteps
%   çıktısı, events bu invertörün olay tablosu (Start, Severity).
%   Durumlar (categorical, öncelik sırasıyla):
%     night   : güneş < 5°
%     offline : veri yok (iletişim kaybı)
%     grid    : kabin/şebeke olayı (invertörün kendisi değil)
%     alarm   : kırmızı, yanıp söner — trip, >= %15 açıklanamayan kayıp, >= 2 ölü string
%     warning : turuncu — %10-15 kayıp, 1 ölü string
%     chronic : turuncu, sabit — ChronicDays'ten uzun süren uyarı/alarm (açık bakım kaydı)
%     thermal : ısıl kısma (v2): invertör iç sıcaklık/MPP kayması nedeniyle gücünü kısıyor
%     watch   : sarı — %5-10 kayıp, zayıf string, termal derating, düşük R_iso, yüksek L1 gerilimi, verim düşüşü
%     ok      : yeşil
%   Gerçek zamanlı uyum için nedensel bayraklar (StringDeadCausal) kullanılır.
arguments
    TT timetable
    s (1,1) struct
    events table
    opts.ChronicDays (1,1) double = 7
end

nDead = sum(s.StringDeadCausal, 2);
st = repmat("ok", height(TT), 1);
watchExtra = false(height(TT), 1);
for fn = ["qLowInsulation" "qHighGridV" "qInverterEffDrop"]
    if isfield(s, fn)
        watchExtra = watchExtra | s.(fn);
    end
end
st(s.StringWeak | s.Derate | s.DeficitLevel == 1 | watchExtra) = "watch";
if isfield(s, "ThrottleDuty")
    st(s.ThrottleDuty >= 0.25 & TT.Elevation > 5) = "thermal";
end
st(s.DeficitLevel == 2 | nDead == 1) = "warning";
st(s.DeficitLevel == 3 | s.Trip | nDead >= 2) = "alarm";

% Kronik: uyarı/alarm seviyesindeki bir olay ChronicDays'ten uzun sürüyorsa
if ~isempty(events) && ismember("Severity", events.Properties.VariableNames)
    severe = events(events.Severity >= 2, :);
    for i = 1:height(severe)
        inEp = TT.Time >= severe.Start(i) + days(opts.ChronicDays) & TT.Time <= severe.End(i);
        st(inEp & ismember(st, ["warning" "alarm"])) = "chronic";
    end
end

st(s.GridEvent) = "grid";
st(s.Offline) = "offline";
st(TT.Elevation <= 5) = "night";
state = categorical(st, ges.anomaly.stateNames());
end
