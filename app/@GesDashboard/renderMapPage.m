function renderMapPage(app, force) %#ok<INUSD>
%RENDERMAPPAGE 5-düğümlü BTÜ SmartGridLab topolojisi + kutucuklar + seçili düğüm/evirici grafiği.
E = app.Engine;
snap = E.snapshot();
i = E.Index;
A = app.assess(app.Horizon);
tips = strings(numel(E.Ids), 1);
if app.Horizon ~= "instant"
    for k = 1:numel(tips)
        tips(k) = E.Ids(k) + newline + strjoin(app.horizonLines(A, k), newline);
    end
end
tiles = struct("id", cellstr(E.Ids), "state", cellstr(A.State), ...
    "p", num2cell(round(double(snap.Pact), 2)), "pexp", num2cell(round(double(snap.Pexp), 2)), ...
    "ratio", num2cell(round(double(A.Ratio), 3)), "tip", cellstr(tips));

% 5-Düğümlü Topoloji için canlı 21-sütun verisi
ev = @(prop, def) getEngProp(E, prop, i, def);
pac = ev("Pac", double(snap.Pact(1)));
vdc = ev("Vdc", NaN);
idc = ev("Idc", NaN);
eff = ev("Eff", NaN);
if isnan(eff) && snap.Pact(1) > 0.02 && ~isnan(pac)
    eff = 100 * pac / double(snap.Pact(1));
end
vgrid = ev("Vgrid", NaN);
fgrid = ev("Fgrid", NaN);
alpha = ev("AlphaRelay", ifelse(isnan(fgrid), NaN, min(max(fgrid / 50.0, 0), 1)));
vgridc = ev("VgridCond", ifelse(isnan(vgrid) || isnan(alpha) || alpha < 0.05, vgrid, vgrid / max(alpha, 0.05)));
wind = ev("Wind", NaN);
tcell = ev("Tcell", E.Tmod(i));
if isnan(tcell) && ~isnan(E.Tamb(i)) && ~isnan(E.Gref(i))
    tcell = E.Tamb(i) + max(E.Gref(i), 0) / (25.0 + 6.84 * max(ifelse(isnan(wind), 0.5, wind), 0));
end
topo = struct( ...
    "Gpoa", round(E.Gref(i), 1), ...
    "Ghoriz", round(ev("Ghoriz", E.Gref(i)), 1), ...
    "Tamb", round(E.Tamb(i), 1), ...
    "Tmod", round(E.Tmod(i), 1), ...
    "Tcell", round(tcell, 1), ...
    "Wind", round(wind, 2), ...
    "Vdc", round(vdc, 1), ...
    "Idc", round(idc, 2), ...
    "Pact", round(double(snap.Pact(1)), 2), ...
    "Pac", round(pac, 2), ...
    "Pexp", round(double(snap.Pexp(1)), 2), ...
    "PacSpec", round(ev("PacSpec", pac / 1.20), 2), ...
    "Eff", round(eff, 1), ...
    "Riso", round(ev("Riso", NaN), 0), ...
    "Vgrid", round(vgrid, 1), ...
    "VgridCond", round(vgridc, 1), ...
    "Igrid", round(ev("Igrid", NaN), 2), ...
    "Fgrid", round(fgrid, 2), ...
    "AlphaRelay", round(alpha, 3), ...
    "SchedP", ev("SchedP", NaN), ...
    "PacSys", round(pac, 2));

sendEventToHTMLSource(app.Mp.Html, "update", struct("tiles", tiles, "horizon", char(app.Horizon), ...
    "label", char(A.Label), "topology", topo));

if isempty(app.Selected)
    return
end
id = app.Selected;
k = find(E.Ids == id, 1);
if isempty(k), k = 1; id = E.Ids(1); end
if isnan(snap.Pact(k))
    pTxt = "veri yok";
else
    pTxt = sprintf("%.2f kW", snap.Pact(k));
end
hs = ["instant" "day" "week"];
heads = ["Anlık " + string(snap.Time, "HH:mm") "Bugün" "Son 7 gün"];
parts = strings(1, 3);
for j = 1:3
    Aj = app.assess(hs(j));
    st = Aj.State(k);
    chip = sprintf('%s: <b><font color="%s">%s</font></b>', heads(j), app.StateColor(st), app.StateTr(st));
    if hs(j) == app.Horizon
        chip = "<u>" + chip + "</u>";
    end
    parts(j) = chip;
end
nodeBadge = "";
if numel(E.Ids) <= 1
    nodeBadge = " · <font color='#0b3d91'>[" + app.MapNode + "]</font>";
end
app.Mp.Title.Text = "<b>" + id + "</b>" + nodeBadge + "&nbsp;&nbsp; " + strjoin(parts, " &nbsp;·&nbsp; ");
if app.Horizon == "instant"
    ratio = "";
    if snap.Pexp(k) > 0.05 && ~isnan(snap.Pact(k))
        ratio = sprintf(" (%%%.0f)", 100 * snap.Pact(k) / snap.Pexp(k));
    end
    extra = "";
    if ~isnan(vdc)
        extra = sprintf(" | V_dc %.1f V, I_dc %.2f A, R_iso %.0f kΩ | U_L1,cond %.1f V, f %.2f Hz", ...
            vdc, idc, topo.Riso, vgridc, fgrid);
    end
    app.Mp.Summary.Text = sprintf("Anlık güç %s / beklenen %.2f kW%s%s.", pTxt, snap.Pexp(k), ratio, extra);
else
    app.Mp.Summary.Text = strjoin(app.horizonLines(A, k), newline);
end
[t0, t1, day0] = app.horizonWindow();
T = E.series(id, t0, t1);
if app.Horizon == "week"
    xl = [day0, max(snap.Time, day0 + hours(1))];
    ttl = id + " (" + app.MapNode + ") — " + string(day0, "dd MMM") + " – " + string(snap.Time, "dd MMM yyyy");
else
    xl = [day0 + hours(5), day0 + hours(21)];
    ttl = id + " (" + app.MapNode + ") — " + string(day0, "dd MMM yyyy");
end
app.Mp.Chart = updatePowerChart(app.Mp.Chart, app.Mp.Axes, T, xl, ttl, app.ChartMode);
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
