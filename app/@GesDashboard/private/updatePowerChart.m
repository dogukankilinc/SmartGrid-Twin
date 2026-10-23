function h = updatePowerChart(h, ax, T, xl, ttl, mode)
%UPDATEPOWERCHART 4 modlu mühendislik grafiği verisini, eksen sınırlarını ve başlığı günceller.
%   mode: "power" (varsayılan) | "dc_mpp" | "eff_thermal" | "grid_riso"
if nargin < 6 || strlength(string(mode)) == 0
    mode = "power";
end
mode = string(mode);
if isempty(T) || height(T) == 0
    tEmpty = xl(1) + minutes([0; 15]);
    T = timetable(tEmpty, [NaN; NaN], [NaN; NaN], [NaN; NaN], VariableNames=["Pact" "Pexp" "G"]);
end
vars = string(T.Properties.VariableNames);
col = @(name, def) getCol(T, vars, name, def);

t = T.Time;
nanVec = nan(height(T), 1);

switch mode
    case "dc_mpp"
        vdc = col("Vdc", nanVec);
        vmp = col("Vmp", nanVec);
        if all(isnan(vmp)) && any(~isnan(vdc))
            tmod = col("Tmod", repmat(25, height(T), 1));
            vmp = 200 - 0.55 * (tmod - 25);
            vmp(isnan(vdc)) = NaN;
        end
        idc = col("Idc", nanVec);
        imp = col("Imp", nanVec);
        set(h.Pact, XData=t, YData=vdc, Visible="on");
        set(h.Pexp, XData=t, YData=vmp, Visible="on");
        set(h.Pac,  XData=t, YData=nanVec, Visible="off");
        set(h.G,    XData=t, YData=zeros(height(T), 1), Visible="off");
        set(h.R1,   XData=t, YData=idc, Visible="on");
        if any(~isnan(imp))
            set(h.G, XData=t, YData=max(imp, 0), Visible="on");
        end
        yyaxis(ax, "left");
        ylabel(ax, "DC Gerilim V_{dc} / V_{mp} (V)");
        yyaxis(ax, "right");
        ylabel(ax, "DC Akım I_{dc} (A)");
        vMax = max([double(vdc); double(vmp); 240], [], "omitnan");
        vMin = min([double(vdc); double(vmp); 140], [], "omitnan");
        ax.YAxis(1).Limits = [max(0, floor(vMin - 15)), ceil(vMax + 15)];
        iMax = max([double(idc); 6], [], "omitnan");
        ax.YAxis(2).Limits = [0, max(1, 1.15 * iMax)];
        if h.Mode ~= mode
            legend(ax, [h.Pact h.Pexp h.R1], ["V_{dc} (Ölçülen)" "V_{mp} (Beklenen Zarf)" "I_{dc} (DC Akım)"], ...
                Location="northwest", Orientation="horizontal", FontSize=8, Box="off");
        end

    case "eff_thermal"
        eff = col("Eff", nanVec);
        pact = col("Pact", nanVec);
        pac  = col("Pac", nanVec);
        if all(isnan(eff)) && any(~isnan(pact)) && any(~isnan(pac))
            eff = 100 * pac ./ max(pact, 0.02);
            eff(pact < 0.03) = NaN;
        elseif max(eff, [], "omitnan") <= 1.2
            eff = 100 * eff;
        end
        tmod  = col("Tmod", nanVec);
        tcell = col("Tcell", nanVec);
        tamb  = col("Tamb", nanVec);
        wind  = col("Wind", nanVec);
        if all(isnan(tcell)) && any(~isnan(tmod))
            g = max(col("G", zeros(height(T), 1)), 0);
            w = max(wind, 0);
            w(isnan(w)) = 0.5;
            tcell = tamb + g ./ (25.0 + 6.84 * w);
        end
        set(h.Pact, XData=t, YData=eff, Visible="on");
        set(h.Pac,  XData=t, YData=tcell, Visible="on");
        set(h.Pexp, XData=t, YData=tmod, Visible="on");
        wArea = max(wind, 0);
        wArea(isnan(wArea)) = 0;
        set(h.G,    XData=t, YData=wArea, Visible="on");
        set(h.R1,   XData=t, YData=wind, Visible="on");
        yyaxis(ax, "left");
        ylabel(ax, "Verim \eta_{inv} (%)  /  Sıcaklık (°C)");
        yyaxis(ax, "right");
        ylabel(ax, "Rüzgar Hızı v_{wind} (m/s)");
        ax.YAxis(1).Limits = [0, 105];
        wMax = max([double(wind); 3], [], "omitnan");
        ax.YAxis(2).Limits = [0, max(2, 1.2 * wMax)];
        if h.Mode ~= mode
            legend(ax, [h.Pact h.Pac h.Pexp h.R1], ["\eta_{inv} (%)" "T_{cell,Faiman} (°C)" "T_{mod,Ross} (°C)" "Rüzgar (m/s)"], ...
                Location="northwest", Orientation="horizontal", FontSize=8, Box="off");
        end

    case "grid_riso"
        vg = col("Vgrid", nanVec);
        vgc = col("VgridCond", nanVec);
        fg = col("Fgrid", nanVec);
        if all(isnan(vgc)) && any(~isnan(vg))
            alpha = min(max(fg / 50.0, 0.05), 1);
            vgc = vg ./ alpha;
            vgc(vg == 0 | isnan(vg)) = NaN;
        end
        riso = col("Riso", nanVec);
        set(h.Pact, XData=t, YData=vgc, Visible="on");
        set(h.Pac,  XData=t, YData=vg, Visible="on");
        set(h.Pexp, XData=t, YData=repmat(230, height(T), 1), Visible="on");
        rScaled = riso / 1000; % MOhm (0..3 MOhm -> sağ eksende 0..60 ile uyumlu olması için * 20 veya doğrudan R_iso / 100)
        rArea = max(riso / 60, 0); % 3000 kOhm -> 50 ölçeği
        rArea(isnan(rArea)) = 0;
        set(h.G,    XData=t, YData=rArea, Visible="on");
        set(h.R1,   XData=t, YData=fg, Visible="on");
        yyaxis(ax, "left");
        ylabel(ax, "L1 Şebeke Gerilimi U_{L1} / U_{L1,cond} (V)");
        yyaxis(ax, "right");
        ylabel(ax, "Frekans f_{grid} (Hz)  |  R_{iso}/60 (k\Omega)");
        ax.YAxis(1).Limits = [0, 265];
        ax.YAxis(2).Limits = [0, 55];
        if h.Mode ~= mode
            legend(ax, [h.Pact h.Pac h.R1 h.G], ["U_{L1,cond} (k/18 Düzeltmeli)" "U_{L1} (Ham)" "f_{grid} (Hz)" "R_{iso}/60 (3000k\Omega=50)"], ...
                Location="northwest", Orientation="horizontal", FontSize=8, Box="off");
        end

    otherwise % "power"
        pact = col("Pact", nanVec);
        pac  = col("Pac", nanVec);
        pexp = col("Pexp", nanVec);
        g    = col("Gpoa", col("G", nanVec));
        gh   = col("Ghoriz", nanVec);
        g(isnan(g)) = 0;
        set(h.Pact, XData=t, YData=pact, Visible="on");
        if any(~isnan(pac))
            set(h.Pac, XData=t, YData=pac, Visible="on");
        else
            set(h.Pac, XData=t, YData=nanVec, Visible="off");
        end
        set(h.Pexp, XData=t, YData=pexp, Visible="on");
        set(h.G,    XData=t, YData=g, Visible="on");
        if any(~isnan(gh))
            set(h.R1, XData=t, YData=gh, Visible="on");
        else
            set(h.R1, XData=t, YData=nanVec, Visible="off");
        end
        yyaxis(ax, "left");
        ylabel(ax, "Güç P_{dc} / P_{ac} / P_{exp} (kW)");
        yyaxis(ax, "right");
        ylabel(ax, "Işınım G_{poa} (W/m^2)");
        pMax = max([double(pact); double(pac); double(pexp)], [], "omitnan");
        if isempty(pMax) || isnan(pMax) || pMax <= 0
            pLim = 1.5;
        elseif pMax <= 2.5
            pLim = max(0.5, 1.18 * pMax);
        else
            pLim = max(5, 1.15 * pMax);
        end
        ax.YAxis(1).Limits = [0, pLim];
        ax.YAxis(2).Limits = [0, max(200, 1.12 * max([double(g); double(gh)], [], "omitnan"))];
        if h.Mode ~= "power"
            if any(~isnan(pac))
                legend(ax, [h.Pact h.Pac h.Pexp h.G], ["DC Güç" "AC Güç" "Beklenen (M1)" "POA Işınım"], ...
                    Location="northwest", Orientation="horizontal", FontSize=8, Box="off");
            else
                legend(ax, [h.Pact h.Pexp h.G], ["Gerçek" "Beklenen (M1)" "Işınım"], ...
                    Location="northwest", Orientation="horizontal", FontSize=8, Box="off");
            end
        end
end

h.Mode = mode;
xlim(ax, xl);
title(ax, ttl);
end

function v = getCol(T, vars, name, def)
if any(vars == name)
    v = double(T.(name));
else
    v = def;
end
end
