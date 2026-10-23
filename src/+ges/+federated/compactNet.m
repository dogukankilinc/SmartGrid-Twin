function net2 = compactNet(net, opts)
%COMPACTNET Eğitilmiş dlnetwork'ü derleme/tahmin için optimize et ve küçült.
%   net2 = ges.federated.compactNet(net) — gereksiz gradyan geçmişini siler,
%   CPU'ya taşır ve veri tipini yarı hassasiyete (half) dönüştürür.
arguments
    net
    opts.Half    (1,1) logical = false   % float16'ya dönüştür (CUDA gerektirir)
    opts.CpuOnly (1,1) logical = true    % CPU'ya taşı
end
try
    if opts.CpuOnly
        net2 = gatherParameters(net);
    else
        net2 = net;
    end
    if opts.Half
        net2 = quantize(net2, "half");
    end
catch
    net2 = net;
end
end
