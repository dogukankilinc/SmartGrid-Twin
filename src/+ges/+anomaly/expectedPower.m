function ex = expectedPower(bundle, TT, info, fingerprint, opts)
%EXPECTEDPOWER M1 modeliyle beklenen DC/AC güç ("kesikli çizgi") ve beklenen dönüşüm verimi.
%   ex = ges.anomaly.expectedPower(bundle, TT, info, fingerprint)
%   bundle      : s04_train_expected_power / c01_train_m1_v2 çıktısı (m1_expected_power.mat)
%   TT, info    : işlenmiş invertör verisi ve künyesi
%   fingerprint : AmPm, Vmean, Cabin
%   ex alanları (N×1):
%     Pdc     — tüm KURULU stringler sağlam olsaydı beklenen DC güç (kW)
%     PdcWork — yalnızca o an çalışan stringlerle beklenen DC güç (kW)
%     Pac     — Pdc'den DC->AC verim eğrisi (doğrusal veya Sandia 3-terimli + gerilim modeli)
%               ve nominal güç sınırıyla AC güç (kW)
%     EtaExp  — beklenen DC->AC dönüşüm verimi (Pac / Pdc)
%     Calibrated — invertöre özgü kalibrasyon haritası kullanıldı mı (soğuk başlangıçta false)
arguments
    bundle (1,1) struct
    TT timetable
    info (1,1) struct
    fingerprint (1,1) struct
    opts.UseCalibration (1,1) logical = true
    opts.Yhat (:,1) double = []                % toplu tahminde önceden hesaplanmış ham GBT çıktısı
end

[X, ~, aux] = ges.model.m1Features(TT, info, fingerprint);
if isempty(opts.Yhat)
    Xpred = alignPredictorColumns(bundle.Gbt, X);
    yhat = predict(bundle.Gbt, Xpred);
else
    yhat = opts.Yhat;
end
ex.Calibrated = false;
if opts.UseCalibration && isfield(bundle, "CalibrationGbt") && ~isempty(bundle.CalibrationGbt)
    k = find(string({bundle.CalibrationGbt.Id}) == string(info.Id), 1);
    if isempty(k) && isscalar(bundle.CalibrationGbt)
        k = 1;
    end
    if ~isempty(k)
        yhat = yhat .* ges.model.applyCalibration(bundle.CalibrationGbt(k).Map, TT.Elevation, TT.SunAzimuth);
        ex.Calibrated = true;
    end
end
yhat = max(yhat, 0);
yhat(~aux.Lit) = 0;
ex.Pdc = yhat * aux.VInst / 1000;
ex.PdcWork = yhat .* aux.VWork / 1000;

rated = 1.20;
if isfield(info, "Rated") && ~isempty(info.Rated) && ~isnan(info.Rated)
    rated = info.Rated;
end

if isfield(bundle, "EtaSandia") && ~isempty(bundle.EtaSandia)
    % Sandia / Schmidt-Sauer 3-terimli + gerilim bağımlı evirici kayıp modeli:
    % P_loss = c0 + c1*Pdc + c2*Pdc^2 + cV*(Vdc - Vnom)*Pdc
    c = bundle.EtaSandia;
    vdc = repmat(c.Vnom, height(TT), 1);
    if ismember("V_dc", TT.Properties.VariableNames)
        vdc = fillmissing(double(TT.V_dc), "constant", c.Vnom);
    elseif ismember("V_pv1", TT.Properties.VariableNames)
        vdc = fillmissing(double(TT.V_pv1), "constant", c.Vnom);
    end
    pLoss = c.c0 + c.c1 * ex.Pdc + c.c2 * (ex.Pdc .^ 2) + c.cV * (vdc - c.Vnom) .* ex.Pdc;
    pacRaw = ex.Pdc - pLoss;
    pacRaw(ex.Pdc <= 0.005) = 0;
elseif isfield(bundle, "Eta") && numel(bundle.Eta) >= 2
    pacRaw = bundle.Eta(1) + bundle.Eta(2) * ex.Pdc;
else
    pacRaw = 0.9356 * ex.Pdc;
end
ex.Pac = min(max(pacRaw, 0), rated);
ex.Pac(~aux.Lit) = 0;
ex.EtaExp = min(max(ex.Pac ./ max(ex.Pdc, 1e-4), 0), 1);
ex.EtaExp(ex.Pdc <= 0.02) = NaN;
end

function Xpred = alignPredictorColumns(mdl, X)
if isprop(mdl, "PredictorNames") && ~isempty(mdl.PredictorNames)
    req = string(mdl.PredictorNames);
    Xpred = table();
    for i = 1:numel(req)
        col = req(i);
        if ismember(col, string(X.Properties.VariableNames))
            Xpred.(col) = X.(col);
        else
            Xpred.(col) = zeros(height(X), 1);
        end
    end
else
    Xpred = X;
end
end
