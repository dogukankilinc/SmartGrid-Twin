function T = compactTable(T, opts)
%COMPACTTABLE Gün tablosunu raporlama için sıkıştır: büyük struct sütunlarını skaler alanlara dönüştür.
%   T = ges.opinions.compactTable(T) — O1/O3/C struct sütunlarından Label/Level/Check alanlarını çıkar.
arguments
    T    table
    opts.IncludeDetail (1,1) logical = true
end
for col = ["O1" "O3" "C"]
    if ismember(col, T.Properties.VariableNames)
        s = T.(col);
        if isstruct(s) || (iscell(s) && isstruct(s{1}))
            try
                if isstruct(s)
                    T.(col+"_Label") = string({s.Label}');
                    T.(col+"_Level") = string({s.Level}');
                    T.(col+"_Check") = logical([s.Check]');
                    if opts.IncludeDetail && isfield(s, "Detail")
                        T.(col+"_Detail") = string({s.Detail}');
                    end
                end
            catch
            end
            T.(col) = [];
        end
    end
end
if ismember("PeerF", T.Properties.VariableNames)
    pf = T.PeerF;
    if isstruct(pf)
        try
            T.PeerRatio = [pf.Ratio]';
        catch; end
    end
    T.PeerF = [];
end
end
