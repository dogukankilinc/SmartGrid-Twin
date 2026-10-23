function s = skyText(kc, daily)
%SKYTEXT Açıklık indeksi → gökyüzü metni (eşikler ges.prep.dailySummary ile aynı: < 0,4 kapalı, ≥ 0,75 açık).
if isnan(kc)
    s = "—";
elseif kc >= 0.75
    s = sprintf("☀ Açık%s  (%%%.0f)", ifelse(daily, " gün", ""), 100 * kc);
elseif kc >= 0.4
    s = sprintf("⛅ Parçalı bulutlu  (%%%.0f)", 100 * kc);
else
    s = sprintf("☁ Kapalı  (%%%.0f)", 100 * kc);
end
s = string(s);
end
