function chunks = pageContext(app, page)
%PAGECONTEXT Sayfanın o an gösterdiği bilgiler + 4 Altın Nedensel SmartGridLab Açıklaması → asistanın okuduğu parçalar.
%   İlk parça her zaman sayfanın özetidir. Asistan (ges.agents.PageChat) soruya en ilgili parçaları
%   seçer ve YALNIZCA onlarla yanıt verir.
E = app.Engine;
snap = E.snapshot();
i = E.Index;
now = string(snap.Time, "dd.MM.yyyy HH:mm");
chunks = struct("Title", {}, "Text", {});
add = @(c, t, x) [c, struct("Title", string(t), "Text", string(x))];

% Yardımcı: Engine özelliğinden güvenli okuma
ev = @(prop, def) getEngProp(E, prop, i, def);
pac = ev("Pac", double(snap.PlantKw));
vdc = ev("Vdc", NaN);
idc = ev("Idc", NaN);
eff = ev("Eff", NaN);
if isnan(eff) && snap.PlantKw > 0.02 && ~isnan(pac)
    eff = 100 * pac / snap.PlantKw;
elseif ~isnan(eff) && eff <= 1.2
    eff = 100 * eff;
end
riso = ev("Riso", NaN);
vgrid = ev("Vgrid", NaN);
fgrid = ev("Fgrid", NaN);
alpha = ev("AlphaRelay", ifelse(isnan(fgrid), NaN, min(max(fgrid / 50.0, 0), 1)));
vgridc = ev("VgridCond", ifelse(isnan(vgrid) || isnan(alpha) || alpha < 0.05, vgrid, vgrid / max(alpha, 0.05)));
wind = ev("Wind", NaN);
tcell = ev("Tcell", E.Tmod(i));
if isnan(tcell) && ~isnan(E.Tamb(i)) && ~isnan(E.Gref(i))
    tcell = E.Tamb(i) + max(E.Gref(i), 0) / (25.0 + 6.84 * max(ifelse(isnan(wind), 0.5, wind), 0));
end
elecSummary = sprintf("WR13TL22-8231 (K01-INV01, 1.20 kWp) anlık ölçümler: P_dc %.2f kW, P_ac %.2f kW, beklenen %.2f kW, dönüşüm verimi η_inv %%%.1f, V_dc %.1f V, I_dc %.2f A, yalıtım direnci R_iso %.0f kOhm, L1 şebeke koşullu gerilim U_L1,cond %.1f V (ham U_L1 %.1f V), frekans f_grid %.2f Hz (röle görev oranı α_relay=%.2f), Faiman hücre sıcaklığı T_cell,dyn %.1f °C, Ross T_mod %.1f °C, ortam T_amb %.1f °C, rüzgar hızı %.2f m/s.", ...
    snap.PlantKw, pac, snap.PlantExpectedKw, eff, vdc, idc, riso, vgridc, vgrid, fgrid, alpha, tcell, E.Tmod(i), E.Tamb(i), wind);

% 4 Altın Nedensel SmartGridLab Açıklaması (Sıfır-Halüsinasyon Koruma Katmanı)
goldenRules = [
    "1) k/18 Röle Görev Oranı Yasası (U_L1,cond ve f_grid): Sabah/akşam düşük ışınımda (G < 250 W/m²) görülen 33.33 Hz (12/18) veya 41.67 Hz (15/18) frekans ve 151–188 V gerilim değerleri şebeke çökmesi değildir; SMA eviricinin 15 dakikadaki 18 adet 50 saniyelik alt-örneklemden k tanesinde röleyi kapalı tutmasından kaynaklanır. Röle kapalıyken gerçek şebeke gerilimi U_L1,cond = U_L1 * (50 / f_grid) ≈ 228.3 V ile tamamen normaldir. Gerçek gündüz şebeke kesintisi yalnızca 29.07.2026 11:45 AM (G=873 W/m², U_L1=0 V, f=0 Hz) adımında yaşanmıştır."
    "2) Sentetik Ross T_mod vs Dinamik Faiman T_cell,dyn ve Rüzgar Soğutması: CSV'deki Module temperature sütunu gerçek bir sensör değil, rüzgarsız Ross formülüdür (T_amb + 0.028*G). Sistemimiz System wind speed (v_wind, maks 2.9 m/s) verisini Faiman konvektif soğutma modelinde kullanarak gerçek hücre sıcaklığını (T_cell,dyn) ve rüzgar soğutma kazancını (ΔT_wind) hesaplar."
    "3) R_iso Yalıtım Direnci (1153–3000 kOhm) Sabah Çiyi ve Kuruma Dinamiği: 3000 kOhm sensörün üst doygunluk sınırıdır. Sabah erken saatlerde çiy/nem veya yağışlı günlerde (28–30 Eylül) R_iso'nun 1153–1350 kOhm bandına inip güneş çıkıp panel ısındıkça 3000 kOhm'a dönmesi normaldir (>1000 kOhm güvenlidir)."
    "4) Izgara Dışı (:10, :25, :50) Active Power Limitation = 0.00% Reset İmzası ve 3 Kanonik Saha Olayı: Gündüz görülen 4 adet 0.00% kaydı (31 Temmuz 15:10, 29 Ağustos 12:25 ve 14:00, 3 Eylül 18:50) güç kısma komutu değil, kesinti sonrası evirici yeniden başlatma (Reboot/Handshake, qRebootEvent) anlarıdır. Üç ana saha olayı: Olay 1 (27–31 Temmuz 4.5 gün kesinti + 29 Temmuz 11:45 şebeke kaybı), Olay 2 (29 Ağustos 11:30 V_dc=230V MPP->Voc sıçraması ve kısma), Olay 3 (03 Eylül 17:15–19:00 kesintisi)."];

switch page
    case "overview"
        app.renderOverview(false);
        o = app.Ov;
        chunks = add(chunks, "Genel Bakış özeti", sprintf("Oynatma anı %s. Anlık güç %s (%s). Bugünkü üretim %s (%s). " + ...
            "DC Bara / Bu ay: %s (%s). L1 Şebeke / Toplam: %s (%s). Durum & Termal: %s (%s). Gökyüzü: %s (%s). %s", ...
            now, o.Power.Text, o.PowerSub.Text, o.Today.Text, o.TodaySub.Text, o.Month.Text, o.MonthSub.Text, ...
            o.Total.Text, o.TotalSub.Text, o.States.Text, o.StatesSub.Text, o.Sky.Text, o.SkySub.Text, elecSummary));
        chunks = add(chunks, "Meteoroloji, Faiman Termal İkiz ve L1 Şebeke", app.Ov.Weather.Text);
        T = app.Ov.StatusTable.Data;
        if ~isempty(T)
            chunks = add(chunks, "Durum sayıları (anlık / bugün / son 7 gün)", strjoin(compose("%s: anlık %s, bugün %s, son 7 gün %s", ...
                string(T{:, 1}), string(T{:, 2}), string(T{:, 3}), string(T{:, 4})), "; "));
        end
        L = app.Ov.LowTable.Data;
        if ~isempty(L)
            chunks = add(chunks, "Performans ve kayıp özeti tablosu", strjoin(compose("%s: %s, performans %%%s, kayıp %s, neden %s", ...
                string(L{:, 1}), string(L{:, 2}), string(L{:, 3}), string(L{:, 4}), string(L{:, 5})), "; "));
        end
        modes = dictionary(["week" "month" "year"], ["son 7 gün (günlük)" "bu ay (günlük)" "son 12 ay (aylık)"]);
        tNow = snap.Time;
        today = dateshift(tNow, "start", "day");
        m0 = dateshift(tNow, "start", "month");
        S7 = E.energySeries(today - days(6), today + days(1), "day");
        S12 = E.energySeries(m0 - calmonths(11), m0 + calmonths(1), "month");
        chunks = add(chunks, "Enerji grafiği: son 7 gün", "Grafik modu: " + modes(app.EnergyMode) + ". Günlük gerçek / beklenen enerji: " + ...
            strjoin(compose("%s %.2f / %.2f kWh (%%%.1f)", string(S7.Time, "dd.MM"), S7.Eact, S7.Eexp, S7.Perf), "; "));
        ok = ~isnan(S12.Eact);
        chunks = add(chunks, "Enerji grafiği: son 12 ay", "Aylık gerçek / beklenen enerji: " + ...
            strjoin(compose("%s %.1f / %.1f kWh (%%%.1f)", string(S12.Time(ok), "MM.yyyy"), S12.Eact(ok), S12.Eexp(ok), S12.Perf(ok)), "; "));
        chunks = add(chunks, "SmartGridLab Fiziksel Kurallar (Röle, Faiman, R_iso, Reset)", strjoin(goldenRules, " "));

    case "map"
        A = app.assess(app.Horizon);
        st = ["ok" "watch" "thermal" "warning" "alarm" "chronic" "grid" "offline" "night"];
        cnt = arrayfun(@(s) nnz(A.State == s), st);
        chunks = add(chunks, "Saha haritası ve SmartGrid-Twin 5-Düğümlü Topoloji özeti", sprintf("Oynatma anı %s. Seçili değerlendirme: %s (%s). Seçili topoloji düğümü: %s. Kutucuk sayıları: %s. %s", ...
            now, app.HorizonTr(app.Horizon), A.Label, app.MapNode, strjoin(compose("%s %d", app.StateLower(st(cnt > 0))', cnt(cnt > 0)'), ", "), elecSummary));
        chunks = add(chunks, "5 Topoloji Düğümü (METEO-SmartGrid-Twin, PV-ARRAY, WR13TL22-8231, GRID-PCC, DATA-MANAGER)", ...
            "1) METEO-SmartGrid-Twin: G_poa, G_horiz, T_amb, rüzgar hızı v_wind, Ross T_mod vs Faiman T_cell,dyn. " + ...
            "2) PV-ARRAY (1.20 kWp): V_dc, I_dc, P_dc, R_iso yalıtım direnci (1153–3000 kOhm). " + ...
            "3) WR13TL22-8231: P_ac, P_spec (kW/kWp), dönüşüm verimi η_inv, aktif güç sınırı SchedP_Pct. " + ...
            "4) GRID-PCC (L1-L2-L3): Koşullu gerilim U_L1,cond, ham U_L1, I_L1, f_grid, k/18 röle oranı, L2=0V, L3=0V tek-faz onayı. " + ...
            "5) DATA-MANAGER: Tesis sayacı P_ac,sys ile evirici P_ac tam mutabakatı (ΔP = 0.000 kW).");
        if ~isempty(app.Selected)
            chunks = add(chunks, "Seçili cihaz " + app.Selected, strjoin(app.detailText(), " "));
        end
        chunks = add(chunks, "Değerlendirme kuralları ve k/18 röle yasası", strjoin(goldenRules, " "));

    case "analysis"
        if isempty(app.Selected)
            chunks = add(chunks, "Analiz", "Seçili cihaz yok.");
            return
        end
        app.renderAnalysis(false);
        chunks = add(chunks, "Seçili cihaz " + app.Selected + " ve aktif grafik modu", "Oynatma anı " + now + ". Grafik katmanı: " + app.ChartMode + ". " + ...
            replace(regexprep(string(app.An.Status.Text), "<[^>]+>", ""), "&nbsp;", " ") + ". " + elecSummary);
        chunks = add(chunks, "Teşhis (ajanlar — 3 görüş: Sensör, Görsel CNN, Elektriksel İkiz & Öz-Akran)", strjoin(string(app.An.Agent.Value), " "));
        lab = strings(0, 1);
        for j = 1:7
            if app.An.ScaloImg(j).Visible == "on"
                lab(end+1) = replace(string(app.An.ScaloLbl(j).Text), newline, " ") + " — " + string(app.An.ScaloImg(j).Tooltip); %#ok<AGROW>
            end
        end
        chunks = add(chunks, "Skalogram günleri (gün etiketi, performans)", strjoin(lab, "; "));
        evTbl = app.An.Events.Data;
        if isempty(evTbl)
            chunks = add(chunks, "Olaylar (son 30 gün)", "Son 30 günde kayıtlı olay yok.");
        else
            suf = repmat("", height(evTbl), 1);
            suf(logical(evTbl{:, 6})) = " (kronik)";
            chunks = add(chunks, "Olaylar (son 30 gün)", strjoin(compose("%s PV%d başlangıç %s, %.1f gün, kayıp %.2f kWh%s", string(evTbl{:, 1}), ...
                evTbl{:, 2}, string(evTbl{:, 3}), evTbl{:, 4}, evTbl{:, 5}, suf), "; "));
        end
        chunks = add(chunks, "SmartGridLab Fiziksel Kurallar (4-Kadranlı MPP, k/18 Röle, Faiman, R_iso)", strjoin(goldenRules, " "));

    case "forecast"
        chunks = add(chunks, "Tahmin sayfası özeti", "Oynatma anı " + now + ". " + string(app.Fc.Status.Text));
        if ~isempty(app.Forecast)
            fc = app.Forecast.fc;
            d = dateshift(fc.Time, "start", "day");
            [g, dd] = findgroups(d);
            e = splitapply(@(x) sum(x) * app.dtHours(), fc.PlantKw, g);
            chunks = add(chunks, "48 saatlik üretim tahmini (günlük)", strjoin(compose("%s: %.2f kWh", string(dd, "dd.MM.yyyy"), e), "; "));
        end
        if isfield(app.Fc, "Context")
            for k = 1:numel(app.Fc.Context)
                chunks = add(chunks, app.Fc.Context(k).Title, app.Fc.Context(k).Text);
            end
        end
        chunks = add(chunks, "Erken Uyarı Kuralları (R_iso, Kısa Kopma, Reset)", strjoin(goldenRules, " "));

    case "reports"
        chunks = add(chunks, "Raporlar özeti", string(app.Rp.Info.Text));
        titles = dictionary(["loss" "thermal" "soil" "cloud" "degr" "maint"], ...
            ["Kayıp dağılımı ve evirici verimi" "Isıl kısma ve Faiman rüzgar soğutması" "Tozlanma oranı ve kirlenme hızı" ...
             "Bulutluluk ve L1 şebeke R_th analizi" "Yalıtım direnci R_iso ve degradasyon" "Bakım önerileri ve saha olayları"]);
        for k = keys(titles)'
            if isfield(app.Rp.Text, k)
                v = string(app.Rp.Text.(k).Value);
                v = v(strlength(v) > 0);
                part = "";
                for idx = 1:numel(v)
                    if strlength(part) + strlength(v(idx)) > 600 && part ~= ""
                        chunks = add(chunks, titles(k), part);
                        part = "";
                    end
                    part = strtrim(part + " " + v(idx));
                end
                if part ~= ""
                    chunks = add(chunks, titles(k), part);
                end
            end
        end
        chunks = add(chunks, "SmartGridLab Rapor Bulguları (Röle, Faiman, R_iso, Reset)", strjoin(goldenRules, " "));

    case "notify"
        n = app.Notifications;
        chunks = add(chunks, "Bildirimler özeti", sprintf("Toplam %d bildirim (en yeni üstte). Alarm %d, kontrol önerisi %d, bilgi %d.", numel(n), ...
            nnz(string({n.kind}) == "alarm"), nnz(string({n.kind}) == "check"), nnz(string({n.kind}) == "info")));
        for k = 1:min(30, numel(n))
            chunks = add(chunks, "Bildirim " + n(k).time + " [" + n(k).kind + ifelse(n(k).tag ~= "", ", " + n(k).tag, "") + "]", n(k).text);
        end

    case "data"
        app.renderDataPage(false);
        chunks = add(chunks, "Veri sayfası özeti", string(app.Dt.Current.Text) + ". " + string(app.Dt.Summary.Text));
        chunks = add(chunks, "Gerekli dosyalar ve SMA Birleşik CSV Şeması", ...
            "SmartGrid-Twin SMA Sunny Portal birleşik CSV dosyaları (sep=;, 14 satır metadata, 21 sütun: WR13TL22-8231 evirici + Satellite Sensor + SmartGridLab sistem) " + ...
            "tek adımda okunur. Hafta başı 12.00 AM mükerrer satırlar coalesceDuplicates ile birleştirilir; :10/:25/:50 ızgara dışı reset satırları (qRebootEvent) korunur.");
        if ~isempty(app.Dt.Log.Value)
            chunks = add(chunks, "İşleme günlüğü", strjoin(string(app.Dt.Log.Value(max(1, end - 8):end)), " | "));
        end

    case "help"
        g = app.Hp.Glossary;
        chunks = add(chunks, "Yardım sayfası", "Sözlük: " + strjoin(string({g.Term}), ", ") + ". Ayrıca harita durumları ve sayfaların içerikleri.");
        for k = 1:numel(g)
            chunks = add(chunks, g(k).Term, g(k).Short + " " + g(k).Long);
        end
end
end

function v = getEngProp(E, prop, idx, def)
v = def;
try
    if isprop(E, prop) && ~isempty(E.(prop))
        arr = E.(prop);
        if size(arr, 1) >= idx
            v = double(arr(idx, 1));
        end
    end
catch
end
end
