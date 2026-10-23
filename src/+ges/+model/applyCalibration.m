function m = applyCalibration(m, calMap, opts)
%APPLYCALIBRATION Eğitim diliminde hesaplanan kalibrasyon haritasını M1 beklenen güce uygula.
%   m = ges.model.applyCalibration(m, calMap) — m: model struct (Pexp alanına sahip),
%   calMap: calibrationMap çıktısı (Elevation × SunAzimuth büzülmeli ızgara).
%   SmartGridLab uyarlaması: tek evirici için kalibrasyon haritası 2 boyutludur;
%   G_poa ve T_cell_dyn zaten m1Features içinde kullanıldığı için ek ölçek gerekmeyebilir.
arguments
    m       struct
    calMap  struct
    opts.Field  (1,1) string  = "Pexp"
    opts.Clamp  (1,1) logical = true   % 0..1.1*Capacity arası kıs
    opts.Cap    (1,1) double  = NaN    % NaN → calMap.Cap'ten al
end
if ~isfield(m, opts.Field)
    return
end
cap = opts.Cap;
if isnan(cap) && isfield(calMap, "Cap")
    cap = calMap.Cap;
elseif isnan(cap)
    cap = 1.20;
end

Praw = m.(opts.Field);
if isfield(calMap, "Scale") && ~isempty(calMap.Scale)
    try
        Praw = Praw .* calMap.Scale(:);
    catch
    end
end
if opts.Clamp
    Praw = max(0, min(Praw, 1.1 * cap));
end
m.(opts.Field) = Praw;
end
