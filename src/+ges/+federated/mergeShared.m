function net2 = mergeShared(globalNet, localNet, opts)
%MERGESHARED FedBN: global evrişim ağırlıklarını koru, BatchNorm istatistiklerini lokal tut.
%   net2 = ges.federated.mergeShared(globalNet, localNet) — lokal istemciye global ağırlıkları
%   uygular; BN istatistiklerini (Mean, Variance) lokal rejime ait tutar (AdaBN hazırlığı).
arguments
    globalNet
    localNet
    opts.ExcludeBN (1,1) logical = true
end
net2 = localNet;
try
    gp = globalNet.Learnables;
    lp = localNet.Learnables;
    for r = 1:height(gp)
        if opts.ExcludeBN
            pname = lower(string(gp.Parameter(r)));
            lname = lower(string(gp.Layer(r)));
            if contains(lname,"batchnorm") || contains(pname,"mean") || contains(pname,"variance")
                continue
            end
        end
        lp.Value{r} = gp.Value{r};
    end
    net2 = setLearnables(net2, lp);
catch ME
    warning("ges:federated:mergeFail","mergeShared başarısız: %s", ME.message);
end
end
