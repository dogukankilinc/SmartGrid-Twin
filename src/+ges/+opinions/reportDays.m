function T = reportDays(cfg, fleet, startDay, endDay, opts)
%REPORTDAYS Günlük 3-görüş raporunu üret ve konsola yaz.
%   T = ges.opinions.reportDays(cfg, fleet, startDay, endDay) — startDay/endDay: datetime.
%   SmartGridLab (tek evirici, K01-INV01): hem üç görüşü hem de 6 altın saha olayını içerir.
arguments
    cfg       (1,1) struct
    fleet     (1,1) struct
    startDay  (1,1) datetime
    endDay    (1,1) datetime
    opts.Ids      (:,1) string  = strings(0,1)
    opts.Verbose  (1,1) logical = true
    opts.MaxDays  (1,1) double  = 90
end

T = ges.opinions.dayTable(cfg, fleet, startDay, endDay, Ids=opts.Ids, Verbose=false);
if isempty(T)
    return
end
Tc = ges.opinions.compactTable(T);

if opts.Verbose
    fprintf("\n=== SmartGridLab 3-Görüş Raporu  %s – %s ===\n", ...
        string(startDay,"yyyy-MM-dd"), string(endDay,"yyyy-MM-dd"));
    fprintf("%-12s  %-20s  %-18s  %-18s  %-10s  %-8s\n", ...
        "Tarih","Sensör (G1)","Görsel-CNN (G2)","Elektriksel İkiz+ÖzAkran (G3)","Uzlaşı","Saha?");
    fprintf("%s\n", repmat("-",1,96));
    for r = 1:min(height(Tc), opts.MaxDays)
        row = Tc(r,:);
        fprintf("%-12s  %-20s  %-18s  %-18s  %-10s  %-8s\n", ...
            string(row.Day,"yyyy-MM-dd"), ...
            valueOrDash(Tc, r, "O1_Label"), ...
            valueOrDash(Tc, r, "O3_Label"), ...
            valueOrDash(Tc, r, "C_Label"), ...
            valueOrDash(Tc, r, "C_Level"), ...
            ifelse(ismember("C_Check", Tc.Properties.VariableNames) && Tc.C_Check(r), "✓", ""));
    end
    if height(Tc) > opts.MaxDays
        fprintf("  ... (%d gün daha)\n", height(Tc) - opts.MaxDays);
    end

    % Özet
    if ismember("C_Label", Tc.Properties.VariableNames)
        lbl = Tc.C_Label;
        cls = ges.opinions.classes();
        fprintf("\nOzet:\n");
        for c = cls
            n = nnz(lbl == c);
            if n > 0; fprintf("  %-22s: %d gün\n", c, n); end
        end
    end
    if ismember("C_Check", Tc.Properties.VariableNames)
        fprintf("Saha kontrolü önerilen gün sayısı: %d\n", nnz(Tc.C_Check));
    end
end
T = Tc;
end

function v = valueOrDash(T, r, col)
if ismember(col, T.Properties.VariableNames)
    v = string(T.(col)(r));
else
    v = "-";
end
end

function out = ifelse(cond, a, b)
if cond; out = a; else; out = b; end
end
