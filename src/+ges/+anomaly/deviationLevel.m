function level = deviationLevel(dev, opts)
%DEVIATIONLEVEL Normalleştirilmiş sapma değerinden 5 kademeli uyarı seviyesi üret.
%   level = ges.anomaly.deviationLevel(dev) — dev: normalleştirilmiş sapma (0-1+ arası)
%   Dönüş: "none" | "watch" | "warning" | "alarm" | "critical"
%
%   SmartGridLab uyarlaması:
%     - Sapma kaynağı P_ac (M1 beklenen güç), Eta_inv (evirici verimi), R_iso ve V_dc olabilir.
%     - Eşikler 1.20 kWp sistemin kısa veri penceresine (11 hafta) kalibre edilmiştir.
arguments
    dev  (:,1) double
    opts.ThreshWatch    (1,1) double = 0.05   % %5 sapma: izle
    opts.ThreshWarning  (1,1) double = 0.10   % %10 sapma: uyarı
    opts.ThreshAlarm    (1,1) double = 0.20   % %20 sapma: alarm
    opts.ThreshCritical (1,1) double = 0.40   % %40 sapma: kritik
end

level = repmat("none", numel(dev), 1);
level(dev >= opts.ThreshWatch)    = "watch";
level(dev >= opts.ThreshWarning)  = "warning";
level(dev >= opts.ThreshAlarm)    = "alarm";
level(dev >= opts.ThreshCritical) = "critical";
level(isnan(dev))                 = "none";
end
