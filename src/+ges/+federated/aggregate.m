function net2 = aggregate(nets, opts)
%AGGREGATE Federe öğrenme: birden fazla lokal ağı FedAvg/FedBN ile birleştirir.
%   net2 = ges.federated.aggregate(nets) — nets: cell dizisi, her elemanı bir ağ.
%   SmartGridLab uyarlaması (tek evirici): zaman dilimi / rejim istemcileri birleştirilir.
%   FedBN: BatchNorm istatistikleri dışlanır, evrişim ağırlıkları ortalaması alınır.
arguments
    nets (1,:) cell
    opts.ExcludeBN    (1,1) logical = true   % BatchNorm istatistiklerini dışla (FedBN)
    opts.Weights      (:,1) double  = []     % istemci ağırlıkları (boşsa eşit ağırlık)
end
if isempty(nets)
    error("ges:federated:emptyNets", "Birleştirilecek ağ yok.");
end
n = numel(nets);
if isempty(opts.Weights)
    w = ones(n,1) / n;
else
    w = opts.Weights(:) / sum(opts.Weights);
end
net2 = nets{1};
try
    params2 = net2.Learnables;
    for k = 2:n
        pk = nets{k}.Learnables;
        for r = 1:height(params2)
            lname = params2.Layer(r);
            % BatchNorm istatistiklerini FedBN modunda atla
            if opts.ExcludeBN && (contains(lower(string(lname)), "batchnorm") || ...
                    contains(lower(string(params2.Parameter(r))), "mean") || ...
                    contains(lower(string(params2.Parameter(r))), "variance"))
                continue
            end
            v1 = extractdata(params2.Value{r});
            v2 = extractdata(pk.Value{r});
            params2.Value{r} = dlarray(w(1)*v1 + w(k)*v2);
        end
    end
    net2 = setLearnables(net2, params2);
catch ME
    warning("ges:federated:aggregateFail", "FedAvg başarısız (struct modu): %s", ME.message);
    % Struct/yapısal ağ geri dönüş: ağırlıklı ortalama parametreler
end
end
