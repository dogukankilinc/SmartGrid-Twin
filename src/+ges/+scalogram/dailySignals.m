function [sig, ok, expectedN, sigElec] = dailySignals(TT, Steps, capacity, day, opts)
%DAILYSIGNALS Skalogram için bir invertör-gününün sabit pencereli Fizik-RGB ve Elektriksel-İkiz sinyalleri.
%   [sig, ok, expectedN, sigElec] = ges.scalogram.dailySignals(TT, Steps, capacity, day)
%   Pencere: yerel saatle WindowStart'tan itibaren NumSteps × 15 dk (varsayılan 05:00-21:00, 64 adım).
%   Dal 1 — sig (NumSteps×3, "rgb_power", tümü normalize güç biriminde ≈ 0..1.2):
%     1 R: P_dc / kapasite                       — invertörün ne ürettiği
%     2 G: G_poa / 1000 (yoksa G_ref / 1000)     — gökyüzünün dizi düzlemine ne verdiği (bulut imzası)
%     3 B: max(P_dc_beklenen - P_dc, 0) / kapasite — M1'e göre eksik üretim
%   Dal 2 — sigElec (NumSteps×3, "rgb_elec", tek evirici elektriksel ikiz imzası):
%     1 R: max(dV, 0) * 5                        — MPP->Voc gerilim sıçraması (ısıl kısma testere dişi)
%     2 G: max(0.9356 - Eta_inv, 0)*5 + max(-dI, 0) — evirici verim çökmesi + dizi akım açığı
%     3 B: (1 - RelayDuty) + |U_L1_cond - 230|/230  — şebeke röle görev oranı ve L1 gerilim sapması
arguments
    TT timetable
    Steps timetable
    capacity (1,1) double
    day (1,1) datetime
    opts.WindowStart (1,1) duration = hours(5)
    opts.NumSteps (1,1) double = 64
    opts.MinCoverage (1,1) double = 0.8
    opts.Until (1,1) datetime = NaT
    opts.Mode (1,1) string = "rgb_power"       % "rgb_power" | "rgb_elec" | "dual"
end

t0 = dateshift(day, "start", "day") + opts.WindowStart;
tGrid = t0 + minutes(15) * (0:opts.NumSteps - 1)';
[tf, loc] = ismember(tGrid, TT.Time);
vars = TT.Properties.VariableNames;

pdc = nan(opts.NumSteps, 1);
g = nan(opts.NumSteps, 1);
pexp = nan(opts.NumSteps, 1);
elev = nan(opts.NumSteps, 1);
dV = zeros(opts.NumSteps, 1);
dI = zeros(opts.NumSteps, 1);
eta = repmat(0.9356, opts.NumSteps, 1);
relayDuty = ones(opts.NumSteps, 1);
uCond = repmat(230, opts.NumSteps, 1);

pdc(tf) = double(TT.P_dc(loc(tf)));
if ismember("G_poa", vars) && any(~isnan(TT.G_poa))
    g(tf) = double(TT.G_poa(loc(tf)));
else
    g(tf) = double(TT.G_ref(loc(tf)));
end
elev(tf) = double(TT.Elevation(loc(tf)));
if ismember("dV", vars), dV(tf) = fillmissing(double(TT.dV(loc(tf))), "constant", 0); end
if ismember("dI", vars), dI(tf) = fillmissing(double(TT.dI(loc(tf))), "constant", 0); end
if ismember("Eta_inv", vars)
    eta(tf) = fillmissing(double(TT.Eta_inv(loc(tf))), "constant", 0.9356);
elseif ismember("Eff", vars)
    eta(tf) = fillmissing(double(TT.Eff(loc(tf))) / 100, "constant", 0.9356);
end
if ismember("RelayDuty", vars)
    relayDuty(tf) = fillmissing(double(TT.RelayDuty(loc(tf))), "constant", 1);
elseif ismember("f_grid", vars)
    fg = fillmissing(double(TT.f_grid(loc(tf))), "constant", 50);
    relayDuty(tf) = min(max(fg / 50.0, 0), 1);
end
if ismember("U_L1_cond", vars)
    uCond(tf) = fillmissing(double(TT.U_L1_cond(loc(tf))), "constant", 230);
elseif ismember("U_L1", vars)
    ul = fillmissing(double(TT.U_L1(loc(tf))), "constant", 230);
    uCond(tf) = ul ./ max(relayDuty(tf), 1/18);
end

[tf2, loc2] = ismember(tGrid, Steps.Time);
pexp(tf2) = double(Steps.Pdc_exp(loc2(tf2)));

lit = elev > 3;
if ~isnat(opts.Until)
    lit = lit & tGrid <= opts.Until;
end
ok = nnz(lit & ~isnan(pdc)) >= opts.MinCoverage * max(nnz(lit), 1) && nnz(lit) > 8;

night = ~(elev > 0);
pdc(night & isnan(pdc)) = 0;
g(night & isnan(g)) = 0;
pexp(night & isnan(pexp)) = 0;
pdc = fillmissing(pdc, "linear", EndValues=0);
g = fillmissing(g, "linear", EndValues=0);
pexp = fillmissing(pexp, "linear", EndValues=0);

if ~isnat(opts.Until)
    future = tGrid > opts.Until;
    pdc(future) = 0;
    g(future) = 0;
    pexp(future) = 0;
    dV(future) = 0;
    dI(future) = 0;
    relayDuty(future) = 1;
    uCond(future) = 230;
end

cap = max(capacity, 0.01);
sigPower = [pdc / cap, g / 1000, max(pexp - pdc, 0) / cap];
sigElec = [min(max(dV, 0) * 5, 1.5), ...
           min(max(0.9356 - eta, 0) * 5 + max(-dI, 0), 1.5), ...
           min(max(1 - relayDuty, 0) + abs(uCond - 230) / 230, 1.5)];
sigElec(night, :) = 0;

switch opts.Mode
    case "rgb_elec"
        sig = sigElec;
    case "dual"
        sig = [sigPower, sigElec];
    otherwise
        sig = sigPower;
end
expectedN = pexp / cap;
end
