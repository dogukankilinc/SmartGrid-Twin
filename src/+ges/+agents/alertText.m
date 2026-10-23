function [msg, parts] = alertText(ctx, r)
%ALERTTEXT Teşhisten kural tabanlı, anında üretilen Türkçe bakım bildirimi (LLM gerektirmez).
%   [msg, parts] = ges.agents.alertText(ctx, r) — r: ges.agents.diagnoseDay çıktısı
%   msg   : tek satır bildirim — evirici adı, karar, uzlaşı düzeyi, kanıt, somut saha eylemi
%   parts : Name ("WR13TL22-8231"), LabelTr, Evidence, Action, Severity, Opinions (üç görüşün kısa özeti)
%   Önem: "alarm" (sorun kabul edildi) | "check" (görüşler çelişiyor / belirsiz → manuel kontrol)
%         | "info" (karar sağlıklı; anlık sapma geçici olabilir → izleme).
%   VLM karara girmez; çalıştırıldıysa yalnızca sağlıklı/sağlıksız ikinci görüşü olarak anılır.
arguments
    ctx (1,1) struct
    r (1,1) struct
end

f = r.Fusion;
n = r.Numeric;
num = double(regexp(r.Id, "\d+", "match"));
parts.Name = "WR13TL22-8231";
if isfield(ctx, "Cfg") && isfield(ctx.Cfg, "site") && ~isempty(num) && num(1) > 1
    parts.Name = sprintf("%s (Kabin-%d INV-%02d)", parts.Name, num(1), num(2));   % çok cihazlı çalışma alanı
end
parts.LabelTr = trLabel(ctx, f.Label);
parts.Evidence = evidenceText(n);
if isfield(r, "Electrical") && isstruct(r.Electrical) && r.Electrical.Steps > 0
    E = r.Electrical;
    if ~isnan(E.RisoMin) && E.RisoMin < 1500
        parts.Evidence = parts.Evidence + sprintf("; R_iso en düşük %.0f kΩ (<1500 kΩ: sabah nemi/çiyi olabilir, öğlen düşük kalırsa uyarıdır)", E.RisoMin);
    end
    if ~isempty(E.GridOutageTimes)
        parts.Evidence = parts.Evidence + sprintf("; gerçek şebeke kesintisi %s (V_L1 = 0 V, f = 0 Hz)", string(E.GridOutageTimes(1), "HH:mm"));
    elseif E.RelaySteps > 0
        parts.Evidence = parts.Evidence + sprintf("; %d adımda k/18 röle alt-örneklemesi (düşük frekans/gerilim şebeke çökmesi değildir)", E.RelaySteps);
    end
    if ~isempty(E.ResetTimes)
        parts.Evidence = parts.Evidence + sprintf("; evirici yeniden başlatma %s (Active power limitation = 0,00 %% bir kısma komutu değildir)", string(E.ResetTimes(1), "HH:mm"));
    end
end
peerEv = "";
if isfield(r, "Peer") && r.Peer.Opinion.Available && r.Peer.Opinion.Evidence ~= ""
    peerEv = "Self-Peer karşılaştırması: " + r.Peer.Opinion.Evidence;
end
parts.Action = actionText(f.Label, n);
parts.Opinions = opinionsText(ctx, r);

vlm = "";
if isfield(r, "Vlm") && ~isempty(r.Vlm) && r.Vlm.Label ~= ""
    l1 = "sağlıksız";
    if r.Vlm.Label == "healthy"
        l1 = "sağlıklı";
    end
    vlm = sprintf(" VLM ikinci görüşü (karara girmez): %s (%%%.0f).", l1, 100 * r.Vlm.Confidence);
end

if f.Label == "uncertain" && ~f.Check
    parts.Severity = "info";                   % hiçbir görüş karar veremedi (veri yok / gün yeni başladı)
    parts.Action = "veri gelince yeniden değerlendirilecek; iletişim kesintisi sürerse SMA Data Manager / Speedwire bağlantısını kontrol edin.";
    msg = sprintf("%s: %s — teşhis için yeterli veri yok (%s). İzleniyor.", parts.Name, f.LevelTr, parts.Opinions);
elseif f.Label == "healthy"
    parts.Severity = "info";
    msg = sprintf("%s: anlık üretim beklenenin altında, ancak gün geneli teşhis sağlıklı (%s: %s).%s Geçici etki (gölge/bulut) olası; izleniyor.", ...
        parts.Name, f.LevelTr, parts.Opinions, vlm);
elseif f.Check
    parts.Severity = "check";
    claim = f.Label;
    if claim == "uncertain"
        claim = string(n.Label);
    end
    reason = f.Note;
    if reason == ""
        reason = "görüşler karar veremedi";
    end
    parts.Action = "görüşler ayrışıyor; " + trLabel(ctx, claim) + " olasılığı için " + actionText(claim, n);
    msg = sprintf("%s: %s — %s (%s).%s Kararsız kaldık, lütfen %s eviricisini manuel kontrol ediniz.", ...
        parts.Name, f.LevelTr, reason, parts.Opinions, vlm, parts.Name);
else
    parts.Severity = "alarm";
    ev = "sensör: " + parts.Evidence;
    if peerEv ~= "" && r.Peer.Opinion.Stance(ges.opinions.classes() == f.Label) > 0
        ev = ev + "; " + peerEv;
    end
    msg = sprintf("%s: %s (%s, %d/%d görüş). Kanıt: %s.%s Öneri: %s", parts.Name, parts.LabelTr, ...
        f.LevelTr, f.SupportN, f.Available, ev, vlm, parts.Action);
    if f.Note ~= ""
        msg = msg + " Not: " + f.Note + ".";
    end
end
msg = string(msg);
end

function s = opinionsText(ctx, r)
% Üç görüşün tek satırlık özeti: "sensör: ısıl kısma · görsel CNN: ısıl kısma · Self-Peer: karar yok"
short = dictionary(["sensor" "visual" "peer"], ["sensör" "görsel CNN" "Self-Peer"]);
items = strings(0, 1);
for o = r.Opinions
    if ~o.Available
        t = "karar yok";
        if o.Key == "visual"
            t = "kapalı";
        end
    elseif o.Label == ""
        t = "karar yok";
    else
        t = strjoin(arrayfun(@(c) trLabel(ctx, c), o.Labels), " + ");
    end
    items(end+1) = short(o.Key) + ": " + t; %#ok<AGROW>
end
s = strjoin(items, " · ");
end

function s = evidenceText(n)
items = strings(0, 1);
if ~isempty(n.DeadPV)
    pv = strjoin("PV" + string(n.DeadPV), ", ");
    if isscalar(n.DeadPV)
        items(end+1) = pv + " string akımı 0 A";
    else
        items(end+1) = pv + " string akımları 0 A";
    end
elseif n.DeadStrings > 0
    items(end+1) = sprintf("%d string akımı 0 A", n.DeadStrings);
end
if ~isempty(n.WeakPV)
    items(end+1) = strjoin("PV" + string(n.WeakPV), ", ") + " akımı komşularından düşük";
end
switch string(n.Detail)
    case "fault_status"
        items(end+1) = "evirici arıza durum kodu";
    case "idle_no_dc"
        items(end+1) = "güneş varken DC giriş yok";
    case "zero_output"
        items(end+1) = "güneş varken çıkış sıfır";
end
if n.GridSteps >= 4
    items(end+1) = "gündüz şebeke kesintisi (V_L1 = 0 V, f = 0 Hz; k/18 röle etkisi değil)";
end
powerSig = isfield(n, "ThrottleSource") && n.ThrottleSource == "P";
if isfield(n, "HasThrottleSignature") && ~n.HasThrottleSignature && n.TcabMax >= 58 ...
        && ~(powerSig && n.ThrottleSteps >= 4)
    items(end+1) = sprintf("iç sıcaklık %.0f °C (≥ 58 °C kısma bölgesi): ısıl kısma olası — V_dc/I_dc imzası doğrulanamadı", n.TcabMax);
end
if isfield(n, "ThrottleSteps") && n.ThrottleSteps >= 4
    if powerSig
        % v2-B02: gerilimsiz invertör — güç+sıcaklık imzası (V/I'lı 91 invertörde doğrulandı)
        t = sprintf("%.1f saat ısıl kısma (güç+sıcaklık imzası: iç sıcaklık ≥ 58 °C iken açık havada güç beklenenin en az %%8 altına iniyor; PV gerilimi ölçülmediği için V/I ile doğrulanamıyor)", n.ThrottleSteps / 4);
    else
        t = sprintf("%.1f saat ısıl kısma (string gerilimi yükseldi, akım düştü: MPP dışı çalışma)", n.ThrottleSteps / 4);
    end
    if ~isnan(n.TcabMax)
        t = t + sprintf(", iç sıcaklık en yüksek %.0f °C", n.TcabMax);
    end
    if n.ThrottleLossKwh > 0
        t = t + sprintf(", kısma kaybı %.0f kWh", n.ThrottleLossKwh);
    end
    items(end+1) = t;
end
if n.ResDefPct >= 3
    items(end+1) = sprintf("açıklanamayan eksik üretim %%%.1f", n.ResDefPct);
end
if isempty(items)
    items = sprintf("beklenen güce göre toplam sapma %%%.1f", n.TotDefPct);
end
s = strjoin(items, "; ");
end

function s = actionText(label, n)
switch string(label)
    case "string_fault"
        pv = [n.DeadPV n.WeakPV];
        if isempty(pv)
            s = "akımı düşük string sigortasını, MC4 konnektörlerini ve kablolarını kontrol edin.";
        else
            s = strjoin("PV" + string(pv), ", ") + " string sigortası, MC4 konnektörleri ve kablosunu kontrol edin.";
        end
    case "inverter_trip"
        s = "evirici olay kaydını (SMA Data Manager) okuyun; AC/DC şalterleri ve R_iso yalıtım direncini kontrol edin.";
    case "thermal_derating"
        s = "evirici soğutma kanatlarını, fan ve hava girişini kontrol edin; rüzgarsız sıcak saatlerde havalandırmayı iyileştirin.";
    case "soiling"
        s = "panel yüzeyini kontrol edin; yıkama planına alın.";
    case "grid_event"
        s = "şebeke bağlantı noktası (L1) gerilimini, koruma ve sigorta kayıtlarını kontrol edin; sabah/akşam k/18 röle adımları arıza değildir.";
    otherwise
        s = "eylem gerekmiyor; izlemeye devam.";
end
s = string(s);
end

function t = trLabel(ctx, label)
label = string(label);
if isKey(ctx.ClassTr, label)
    t = ctx.ClassTr(label);
else
    t = "belirsiz";
end
end
