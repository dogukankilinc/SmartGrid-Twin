function M = fitThermalModel(TT, thr, evaluable, lossKw, pwork, opts)
%FITTHERMALMODEL Bir invertörün ısıl ikizi: hava → iç/hücre sıcaklığı → kısma olasılığı → kayıp (tahmin için).
%   M = ges.forecast.fitThermalModel(TT, thr, evaluable, lossKw, pwork)
%   Yalnızca opts.Before'dan önceki adımlarla kurulur (eğitim dönemi).
%     1) İç sıcaklık (T_cab varsa): T_cab = a0 + a1·T_amb + a2·Gs + a3·Gs² (Gs: son 1 saatin ortalama ışınımı, kW/m²)
%        T_cab yoksa (ör. SmartGridLab SMA): Sandia 3-terimli evirici kayıp modeli P_loss(P_dc, V_dc) ve
%        rüzgar soğutmalı dinamik Faiman sıcaklığından vekil iç sıcaklık T_inv_proxy üretilir.
%     2) Kısma olasılığı: lojistik P = 1 / (1 + exp(−(b0 + b1·T_cab))) (değerlendirilebilir adımlarda);
%        30'dan az kısılmış adım varsa M.Pooled = true (filo eğrisi kullanılmalı).
%     3) Derinlik: kısılmış adımda medyan kayıp / beklenen güç.
%     4) Ek v3 alanları: M.Sandia (evirici dönüşüm kaybı katsayıları [c0; c1; c2; cV], Vnom, EtaMed),
%        M.Faiman (dinamik Faiman + V_dc termometresi parametreleri), M.WindCoeff.
arguments
    TT timetable
    thr (:,1) logical
    evaluable (:,1) logical
    lossKw (:,1) double
    pwork (:,1) double
    opts.Before (1,1) datetime = datetime(2099, 1, 1, TimeZone="Europe/Istanbul")
    opts.After (1,1) datetime = NaT            % uyarlanır ikiz: yalnızca [After, Before) penceresi (ör. son 60 gün)
end

if isempty(opts.Before.TimeZone) && ~isempty(TT.Time.TimeZone)
    opts.Before.TimeZone = TT.Time.TimeZone;
end
train = TT.Time < opts.Before;
if ~isnat(opts.After)
    if isempty(opts.After.TimeZone) && ~isempty(TT.Time.TimeZone)
        opts.After.TimeZone = TT.Time.TimeZone;
    end
    train = train & TT.Time >= opts.After;
end
if ~any(train)
    train = true(height(TT), 1);
end

Gs = movmean(TT.G_ref, [3 0], "omitmissing") / 1000;

% T_cab mevcut mu kontrol et (Huawei'de mevcut, SmartGridLab'da yoksa vekil üretilir)
hasTcab = ismember("T_cab", TT.Properties.VariableNames) && nnz(train & TT.Elevation > 5 & ~isnan(TT.T_cab)) >= 20;
if hasTcab
    tcabSeries = TT.T_cab;
else
    % SmartGridLab: T_amb + P_loss + Gs - rüzgar soğutması ile vekil T_inv
    if ismember("WindSpeed", TT.Properties.VariableNames)
        w = fillmissing(TT.WindSpeed, "constant", 0.7);
    else
        w = zeros(height(TT), 1);
    end
    if ismember("P_dc", TT.Properties.VariableNames) && ismember("P_ac", TT.Properties.VariableNames)
        ploss = max(TT.P_dc - TT.P_ac, 0);
        pNom = max(prctile(TT.P_ac(train), 99), 1.0);
        plossNorm = fillmissing(ploss / pNom, "constant", 0);
    else
        plossNorm = zeros(height(TT), 1);
    end
    tcabSeries = TT.T_amb + 22.0 * Gs + 8.0 * plossNorm - 1.8 * w;
end

day = train & TT.Elevation > 5 & ~isnan(tcabSeries) & ~isnan(TT.T_amb) & ~isnan(Gs);
if nnz(day) >= 10
    X = [ones(nnz(day), 1) TT.T_amb(day) Gs(day) Gs(day).^2];
    y = tcabSeries(day);
    a = X \ y;
    r = y - X * a;
    keep = abs(r) < 3 * mad(r, 1) / 0.6745;                  % aykırı değerler (sensör hatası) bir kez atılır
    if nnz(keep) >= 6
        a = X(keep, :) \ y(keep);
        M.Rmse = sqrt(mean((y(keep) - X(keep, :) * a).^2));
    else
        M.Rmse = sqrt(mean(r.^2));
    end
    M.A = a;
else
    M.A = [5.0; 1.0; 25.0; -2.0];
    M.Rmse = NaN;
end

ev = train & evaluable & ~isnan(tcabSeries);
M.NumThrottled = nnz(thr(ev));
M.Pooled = M.NumThrottled < 30;
M.B = [NaN; NaN];
if ~M.Pooled
    b = glmfit(tcabSeries(ev), double(thr(ev)), "binomial", "link", "logit");
    M.B = b;
end
d = lossKw(train & thr) ./ pwork(train & thr);
d = d(isfinite(d) & d > 0 & d < 1);
M.Depth = median(d, "omitmissing");
if isnan(M.Depth)
    M.Depth = 0.3;
end
M.Before = opts.Before;

% --- v3 Ek Modeller: Sandia 3-Terimli + Gerilim Bağımlı Evirici Kayıp Modeli & Faiman İkizi ---
M.Sandia = fitSandiaInverterLoss(TT, train);
M.Faiman = fitFaimanTwinParams(TT, train);
end

function S = fitSandiaInverterLoss(TT, train)
% P_loss(P_dc, V_dc) = P_dc - P_ac = c0 + c1*P_dc + c2*P_dc^2 + cV*(V_dc - V_nom)*P_dc
S = struct("Coeffs", [0.005; 0.055; 0.008; 0.0], "Vnom", 188.8, "EtaMed", 0.9356, "RmseKw", NaN);
if ~all(ismember(["P_dc" "P_ac"], TT.Properties.VariableNames))
    return
end
pdc = TT.P_dc;
pac = TT.P_ac;
if ismember("V_dc", TT.Properties.VariableNames)
    vdc = TT.V_dc;
elseif ismember("V_pv1", TT.Properties.VariableNames)
    vdc = TT.V_pv1;
else
    vdc = nan(height(TT), 1);
end
pMax = max(pdc(train), [], "omitnan");
if isempty(pMax) || isnan(pMax) || pMax <= 0
    return
end
ok = train & TT.Elevation > 10 & pdc > 0.10 * pMax & pac > 0 & pac <= pdc * 1.02;
if nnz(ok) < 20
    return
end
eta = pac(ok) ./ pdc(ok);
S.EtaMed = median(eta, "omitnan");
ploss = pdc(ok) - pac(ok);
hasV = nnz(ok & ~isnan(vdc) & vdc > 50) >= 20;
if hasV
    ok = ok & ~isnan(vdc) & vdc > 50;
    ploss = pdc(ok) - pac(ok);
    vNom = median(vdc(ok), "omitnan");
    S.Vnom = vNom;
    X = [ones(nnz(ok), 1), pdc(ok), pdc(ok).^2, (vdc(ok) - vNom) .* pdc(ok)];
else
    X = [ones(nnz(ok), 1), pdc(ok), pdc(ok).^2, zeros(nnz(ok), 1)];
end
c = X \ ploss;
r = ploss - X * c;
keep = abs(r - median(r)) < 3 * 1.4826 * mad(r, 1);
if nnz(keep) >= 15
    c = X(keep, :) \ ploss(keep);
    S.RmseKw = sqrt(mean((ploss(keep) - X(keep, :) * c).^2));
end
S.Coeffs = c;
end

function F = fitFaimanTwinParams(TT, train)
% Dinamik Faiman + V_dc sanal hücre termometresi özeti
F = struct("U0", 25.0, "U1", 6.84, "TauMinutes", 10.0, "VmpStc", 198.0, "BetaV", -0.68, "CvLogG", 4.5);
if ~all(ismember(["T_amb" "G_ref"], TT.Properties.VariableNames))
    return
end
if ismember("G_poa", TT.Properties.VariableNames)
    g = TT.G_poa(train);
else
    g = TT.G_ref(train);
end
if ismember("WindSpeed", TT.Properties.VariableNames)
    w = TT.WindSpeed(train);
else
    w = zeros(nnz(train), 1);
end
if ismember("V_dc", TT.Properties.VariableNames)
    vdc = TT.V_dc(train);
elseif ismember("V_pv1", TT.Properties.VariableNames)
    vdc = TT.V_pv1(train);
else
    vdc = nan(nnz(train), 1);
end
[~, ~, out] = ges.solar.cellTemperatureFaiman(TT.T_amb(train), g, w, Vdc=vdc);
F.VmpStc = out.VmpStc;
F.BetaV = out.BetaV;
F.CvLogG = out.CvLogG;
end
