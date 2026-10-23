function v = mpptVoltages(TT, ref)
%MPPTVOLTAGES Referans koşullarda (açık, yüksek güneş) 4 MPPT'nin medyan gerilimi; < 100 V ise NaN.
%   Tek MPPT'li eviricide (V_dc / V_pv1) 1. MPPT gerilimini diğer MPPT yuvalarına da yansıtır.

names = "V_pv" + [1 3 5 7];
v = nan(1, 4);
cols = string(TT.Properties.VariableNames);
if all(ismember(names, cols)) && any(ref)
    v = median(TT{ref, names}, 1, "omitmissing");
elseif ismember("V_dc", cols) && any(ref)
    v(1) = median(TT.V_dc(ref), "omitmissing");
elseif ismember("V_pv1", cols) && any(ref)
    v(1) = median(TT.V_pv1(ref), "omitmissing");
end
v(v < 100) = NaN;
if ~isnan(v(1)) && all(isnan(v(2:4)))
    v(2:4) = v(1);
end
if all(isnan(v)) && ismember("V_pv1", cols)
    v1 = median(TT.V_pv1(TT.V_pv1 >= 100), "omitmissing");
    if ~isnan(v1)
        v(:) = v1;
    else
        v(:) = 195;
    end
end
end
