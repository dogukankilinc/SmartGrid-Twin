function buildReports(app, parent)
%BUILDREPORTS Raporlar: tüm veriyle yapılan çevrim dışı analizler (artifacts/v2 & SmartGridLab 21-sütun analizleri).
%   Değerler ges.agents.plantInsights'tan OKUNUR; her bölüm güven düzeyini ve mühendislik bulgularını yazar.
g = uigridlayout(parent, [2 1], RowHeight={"fit", "1x"}, Padding=[2 2 2 2], RowSpacing=4);
app.Rp.Info = uilabel(g, Text="", FontColor=[0.35 0.4 0.45], WordWrap="on");
tabs = uitabgroup(g);
app.Rp.Tabs = tabs;
names = ["loss" "thermal" "soil" "cloud" "degr" "maint"];
titles = [ ...
    "Kayıp dağılımı & Verim" ...
    "Isıl kısma & Faiman Termal" ...
    "Tozlanma (32° POA)" ...
    "Bulutluluk & L1 Şebeke (R_th)" ...
    "R_iso Yalıtım & Degradasyon" ...
    "Bakım & Saha Olayları"];
for i = 1:numel(names)
    t = uitab(tabs, Title=titles(i));
    tg = uigridlayout(t, [1 2], ColumnWidth={"3x", "2x"}, Padding=[4 4 4 4], ColumnSpacing=6);
    app.Rp.Axes.(names(i)) = uiaxes(tg);
    disableDefaultInteractivity(app.Rp.Axes.(names(i)));
    app.Rp.Text.(names(i)) = uitextarea(tg, Editable="off", FontSize=12);
end
try
    I = ges.agents.plantInsights(app.Ctx, "hepsi");
catch err
    app.Rp.Info.Text = "Bu veri seti için analiz raporu yok (" + err.message + "). Raporlar scripts/v2 zinciriyle üretilir.";
    return
end
app.Rp.Insights = I;
app.Rp.Info.Text = "Dönem: " + I.Donem + ". Kaynak: " + I.Kaynak + ". Oynatma anından bağımsızdır (tüm veriyle yapılan analiz).";

% 1) Kayıplar & Evirici Verimi
try
    K = I.Kayiplar;
    r = K.KayipSiralamasi;
    ax = app.Rp.Axes.loss;
    cats = string({r.Neden});
    vals = [r.MWh];
    uLbl = ifelse(max(vals) < 1, "kWh (tüm dönem)", "MWh (tüm dönem)");
    if max(vals) < 1, vals = vals * 1000; end
    barh(ax, categorical(cats, flip(cats)), vals, FaceColor=[0.85 0.33 0.10]);
    xlabel(ax, uLbl);
    title(ax, sprintf("Beklenen %s, teslim edilen %%%.1f", energyText(K.BeklenenMWh * 1000), K.TeslimOrani));
    grid(ax, "on");
    app.Rp.Text.loss.Value = [K.SiralamaOzeti; ""; "Kayıp sayılmayan: " + K.KayipDegil; "Açıklanamayan: " + K.Aciklanamayan; ...
        ""; "Ölçüm kapsamı: " + K.OlcumKapsami; ""; "Güven: " + K.Guven];
catch err
    app.Rp.Text.loss.Value = "Kayıp özeti çizilemedi: " + err.message;
end

% 2) Isıl kısma & Faiman Rüzgar Soğutması
try
    T = I.IsilKisma;
    ax = app.Rp.Axes.thermal;
    mo = T.AylikKayip;
    bar(ax, categorical(string({mo.Ay}), string({mo.Ay})), [mo.KayipYuzde], FaceColor=[0.76 0.09 0.36]);
    ylabel(ax, "Kısma / termal kayıp (DC üretimin %'si)");
    title(ax, "Aylık ısıl kısma ve termal kayıp oranı");
    grid(ax, "on");
    lines = [
        sprintf("Toplam kısma kaybı: DC üretimin %%%.2f'i (4-kadranlı V/I zarf imzası).", T.DcUretimYuzde)
        sprintf("Kısma başlangıcı: %%10 olasılık %.1f °C, %%50 olasılık %.1f °C sıcaklık.", T.BaslangicT10_C, T.BaslangicT50_C)
        "Termal karşılaştırma: " + T.AyniSicaklikta2025vs2024
        "Kontrol öncelikli birim: " + strjoin(string(T.FanFiltreKontrolAdayi), ", ")
        "Doğrulama: " + T.Dogrulama
        "Güven: " + T.Guven
        ""
        T.Not];
    app.Rp.Text.thermal.Value = lines;
catch err
    app.Rp.Text.thermal.Value = "Termal analiz çizilemedi: " + err.message;
end

% 3) Tozlanma (32° POA)
try
    S = I.Tozlanma;
    ax = app.Rp.Axes.soil;
    sp = S.KuruDonemler;
    lab = string({sp.Grup}) + " " + string({sp.Baslangic});
    bar(ax, categorical(lab, lab), [sp.KirlenmeHiziYuzdeGun], FaceColor=[0.55 0.42 0.25]);
    ylabel(ax, "Kirlenme hızı (%/gün)");
    title(ax, "Kuru dönemlerde kirlenme hızı (Theil–Sen eğimi, 32° POA)");
    grid(ax, "on");
    app.Rp.Text.soil.Value = [sprintf("32° eğimli dizide tozlanma oranı (medyan): %.3f (1,000 = temiz).", S.TozlanmaOraniMedyan_32derece); ...
        ""; S.Ozet; ""; "Güven: " + S.Guven; ""; "Not: " + S.Not; ""; "Kuru dönemler (%/gün, %95 güven aralığı):"; ...
        compose("  %s %s → %s: %+.3f %s", string({sp.Grup})', string({sp.Baslangic})', string({sp.Bitis})', [sp.KirlenmeHiziYuzdeGun]', string({sp.GA95})')];
catch err
    app.Rp.Text.soil.Value = "Tozlanma analizi çizilemedi: " + err.message;
end

% 4) Bulutluluk & L1 Şebeke Kalitesi
try
    B = I.Bulutluluk;
    ax = app.Rp.Axes.cloud;
    a = B.Aylik;
    yyaxis(ax, "left");
    bar(ax, categorical(string({a.Ay}), string({a.Ay})), [a.BulutlulukYuzde], FaceColor=[0.45 0.55 0.70]);
    ylabel(ax, "Bulutluluk oranı (%)");
    yyaxis(ax, "right");
    plot(ax, categorical(string({a.Ay}), string({a.Ay})), [a.AcikGun], "-o", LineWidth=1.4);
    ylabel(ax, "Açık gün sayısı");
    title(ax, "Aylık bulutluluk oranı ve açık gün sayısı");
    grid(ax, "on");
    app.Rp.Text.cloud.Value = ["Tanım: " + B.Tanim; ""; "Güven: " + B.Guven; ""; "Ay: bulutluluk % · açık / parçalı / kapalı gün"; ...
        compose("  %s: %%%.1f · %d / %d / %d", string({a.Ay})', [a.BulutlulukYuzde]', [a.AcikGun]', [a.ParcaliGun]', [a.KapaliGun]')];
catch err
    app.Rp.Text.cloud.Value = "Bulutluluk analizi çizilemedi: " + err.message;
end

% 5) Degradasyon & R_iso Yalıtım Direnci
try
    D = I.Degradasyon;
    ax = app.Rp.Axes.degr;
    axis(ax, "off");
    text(ax, 0.02, 0.6, ["Sensör ölçeği: " + D.SensorOlcegi; "Açık-gök ölçeği: " + D.AcikGokOlcegi], FontSize=12.5, Units="normalized");
    title(ax, sprintf("Performans istikrarı ve R_iso yalıtım sağlığı (%d birim)", D.InvertorSayisi));
    app.Rp.Text.degr.Value = [D.Sonuc; ""; "Güven: " + D.Guven];
catch err
    app.Rp.Text.degr.Value = "Degradasyon analizi çizilemedi: " + err.message;
end

% 6) Bakım & Kanonik Saha Olayları
try
    M = I.Bakim;
    ax = app.Rp.Axes.maint;
    rs = M.TekrarlayanStringler;
    if ~isempty(rs)
        lab = string({rs.Id}) + " PV" + string([rs.PV]);
        barh(ax, categorical(lab, flip(lab)), [rs.Tekrar], FaceColor=[0.40 0.40 0.45]);
        xlabel(ax, "Olay / tekrar sayısı");
        title(ax, "Kaydedilen DC dizi / kesinti olayları");
        grid(ax, "on");
    end
    app.Rp.Text.maint.Value = ["Dizi & Kesinti Analizi: " + M.StringArizasi; ""; "Termal & Rüzgar Bakımı: " + M.IsilBakim; ""; ...
        "Temizlik aralığı: " + M.TemizlikAraligi; ""; "Not: " + M.Not];
catch err
    app.Rp.Text.maint.Value = "Bakım analizi çizilemedi: " + err.message;
end
end
