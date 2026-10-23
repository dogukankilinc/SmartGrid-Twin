function out = predictThrottle(M, t, Tamb, G, pwork, opts)
%PREDICTTHROTTLE Isıl ikizle kısma, Faiman hücre sıcaklığı ve evirici kayıp tahmini.
%   out = ges.forecast.predictThrottle(M, t, Tamb, G, pwork) — M: ges.forecast.fitThermalModel;
%   t, Tamb (°C), G (W/m², panel düzlemi), pwork (beklenen DC güç, kW) aynı uzunlukta 15 dk seriler.
%   out.Tcab (tahmini iç sıcaklık), out.P (kısma olasılığı), out.Hours (beklenen kısma saati),
%   out.LossKwh (beklenen kayıp), out.TcellDyn (dinamik Faiman hücre sıcaklığı),
%   out.EtaPred (tahmini evirici verimi), out.InvLossKwh (beklenen DC->AC dönüşüm kaybı).
arguments
    M (1,1) struct
    t (:,1) datetime
    Tamb (:,1) double
    G (:,1) double
    pwork (:,1) double
    opts.Fleet (2,1) double = [NaN; NaN]
    opts.Elevation (:,1) double = []
    opts.WindSpeed (:,1) double = []
end

Gs = movmean(G, [3 0], "omitmissing") / 1000;
out.Tcab = M.A(1) + M.A(2) * Tamb + M.A(3) * Gs + M.A(4) * Gs.^2;
if ~isempty(opts.WindSpeed) && numel(opts.WindSpeed) == numel(Tamb)
    w = fillmissing(opts.WindSpeed(:), "constant", 0.7);
else
    w = repmat(0.7, numel(Tamb), 1);
end
[out.TcellDyn, ~, faimanOut] = ges.solar.cellTemperatureFaiman(Tamb, G, w);
out.DeltaTWind = faimanOut.DeltaTWind;

b = M.B;
if M.Pooled || any(isnan(b))
    b = opts.Fleet;
end
if any(isnan(b))
    b = [-24.0; 0.40]; % varsayılan filo lojistik eğrisi (T50 = 60 °C)
end
p = 1 ./ (1 + exp(-(b(1) + b(2) * out.Tcab)));
ev = G > 250;                                            % kısma yalnızca güçlü güneşte değerlendirilir (B01/B02 ile aynı)
if ~isempty(opts.Elevation)
    ev = ev & opts.Elevation > 15;
end
p(~ev | isnan(p)) = 0;
out.P = p;
out.Hours = sum(p) * 0.25;
pw = pwork;
pw(isnan(pw)) = 0;
out.LossKwh = sum(p .* M.Depth .* pw) * 0.25;

% Sandia evirici dönüşüm verimi ve kaybı tahmini
if isfield(M, "Sandia") && isfield(M.Sandia, "Coeffs")
    c = M.Sandia.Coeffs;
    ploss = max(c(1) + c(2) * pw + c(3) * pw.^2, 0);
    ploss(pw <= 0.01) = 0;
    out.EtaPred = max(min(1 - ploss ./ max(pw, 0.05), 0.985), 0.80);
    out.EtaPred(pw <= 0.01) = NaN;
    out.InvLossKwh = sum(ploss) * 0.25;
else
    out.EtaPred = repmat(0.9356, numel(pw), 1);
    out.InvLossKwh = sum(pw * (1 - 0.9356)) * 0.25;
end
out.Time = t;
end
