function net2 = fedAvg(nets, opts)
%FEDAVG FedAvg (McMahan vd. 2017): istemci ağırlıklarının veri büyüklüğüne göre ağırlıklı ortalaması.
%   net2 = ges.federated.fedAvg(nets) — nets: {net1, net2, ...} cell dizisi.
%   SmartGridLab (tek evirici, zaman dilimi istemcileri) için FedBN modu varsayılandır.
arguments
    nets  (1,:) cell
    opts.DataSizes (1,:) double  = []     % her istemcinin örnek sayısı (boşsa eşit)
    opts.FedBN     (1,1) logical = true   % BatchNorm'u istemcide tut
end
if isempty(opts.DataSizes) || numel(opts.DataSizes) ~= numel(nets)
    w = [];
else
    w = opts.DataSizes(:) / sum(opts.DataSizes);
end
net2 = ges.federated.aggregate(nets, ExcludeBN=opts.FedBN, Weights=w);
end
