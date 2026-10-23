function net = adaptBN(net, X, opts)
%ADAPTBN Yeni tesise veya yeni mevsimsel rejime ETİKETSİZ uyarlama (AdaBN, Li vd., 2016):
%   BatchNorm istatistikleri hedef verinin kendisinden yeniden kestirilir; hiçbir ağırlık eğitilmez,
%   etiket gerekmez. SmartGridLab (WR13TL22-8231) üzerinde santraller arası sıfır-etiketli transfer
%   (Cross-Plant Zero-Shot Domain Adaptation) ve çevrimiçi kavram kayması uyarlaması sağlar.
arguments
    net dlnetwork
    X
    opts.Passes (1,1) double = 3
    opts.BatchSize (1,1) double = 256
    opts.UseGPU (1,1) logical = false
end
X = single(X);
if max(X, [], "all") > 1.5
    X = X / 255;
end
N = size(X, 4);
if N == 0
    return
end
useGpu = opts.UseGPU;
if useGpu
    try
        useGpu = canUseGPU();
    catch
        useGpu = false;
    end
end
for p = 1:opts.Passes
    idx = randperm(N);
    for b = 1:ceil(N / opts.BatchSize)
        bi = idx((b - 1) * opts.BatchSize + 1:min(b * opts.BatchSize, N));
        dX = dlarray(X(:, :, :, bi), "SSCB");
        if useGpu
            dX = gpuArray(dX);
        end
        [~, state] = forward(net, dX);
        net.State = state;
    end
end
end
