function s = energyText(kwh)
%ENERGYTEXT Enerji metni: <1 kWh için Wh, <100 kWh için 2 ondalık kWh, <10 MWh için kWh, üstü MWh.
if isnan(kwh)
    s = "—";
elseif abs(kwh) > 0 && abs(kwh) < 1
    s = sprintf("%.0f Wh", kwh * 1000);
elseif abs(kwh) < 100
    s = sprintf("%.2f kWh", kwh);
elseif abs(kwh) < 10000
    s = sprintf("%.0f kWh", kwh);
else
    s = sprintf("%.2f MWh", kwh / 1000);
end
s = string(s);
end
