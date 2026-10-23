function map = calibrationMap(elevation, sunAzimuth, ratio, opts)
%CALIBRATIONMAP İnvertöre özgü gölge/kalibrasyon haritası (güneş konumu ızgarasında çarpan).
%   map = ges.model.calibrationMap(elevation, sunAzimuth, ratio) — ratio =
%   gerçek / global model tahmini (sağlıklı eğitim adımları). Her (yükseklik,
%   azimut) hücresinde medyan oran alınır ve örnek sayısına göre 1'e doğru
%   büzülür (shrinkage): c = (n*medyan + k*1) / (n + k). Az örnekli
%   hücrelerde harita 1'e yakın kalır; aşırı uyum önlenir.
%   Kısa veri setlerinde (örn. 11 haftalık SmartGridLab) shrinkage katsayısı k
%   örneklem büyüklüğüne göre otomatik ölçeklenir.
arguments
    elevation (:,1) double
    sunAzimuth (:,1) double
    ratio (:,1) double
    opts.ElevEdges (1,:) double = [0 10 20 30 40 50 60 75 90]
    opts.AzEdges (1,:) double = 45:15:315
    opts.Shrinkage (1,1) double = 30
end

ie = discretize(elevation, opts.ElevEdges);
ia = discretize(sunAzimuth, opts.AzEdges);
ok = ~isnan(ie) & ~isnan(ia) & isfinite(ratio) & ratio > 0.2 & ratio < 2.5;
nE = numel(opts.ElevEdges) - 1;
nA = numel(opts.AzEdges) - 1;
if ~any(ok)
    map.ElevEdges = opts.ElevEdges;
    map.AzEdges = opts.AzEdges;
    map.Factor = ones(nE, nA);
    map.Count = zeros(nE, nA);
    return
end
cnt = accumarray([ie(ok) ia(ok)], 1, [nE nA]);
med = accumarray([ie(ok) ia(ok)], ratio(ok), [nE nA], @median, NaN);
med(isnan(med)) = 1;
k = opts.Shrinkage;
if nnz(ok) < 5000
    k = min(k, max(5, round(nnz(ok) / 150)));
end
map.ElevEdges = opts.ElevEdges;
map.AzEdges = opts.AzEdges;
map.Factor = (cnt .* med + k) ./ (cnt + k);
map.Count = cnt;
end
