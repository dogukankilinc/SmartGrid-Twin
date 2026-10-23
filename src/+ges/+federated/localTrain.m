function [net2, history] = localTrain(net, X, Y, opts)
%LOCALTRAIN Federe öğrenme: tek istemci (zaman dilimi / rejim) için lokal güncelleme.
%   [net2, history] = ges.federated.localTrain(net, X, Y) — X: eğitim görüntü tensörü,
%   Y: etiket dizisi. SmartGridLab: rgb_power veya rgb_elec modunda scalogram görüntüleri.
arguments
    net
    X   % dlarray veya uint8 [H W C N]
    Y   % kategorik veya onehot
    opts.Epochs       (1,1) double  = 3
    opts.LR           (1,1) double  = 1e-4
    opts.MiniBatch    (1,1) double  = 8
    opts.Verbose      (1,1) logical = false
end
history.Loss = nan(opts.Epochs, 1);
if ~isa(X, "dlarray")
    Xd = dlarray(single(X) / 255, "SSCB");
else
    Xd = X;
end
net2 = net;
try
    for ep = 1:opts.Epochs
        [net2, info] = trainnet(Xd, Y, net2, "crossentropy", ...
            MaxEpochs=1, MiniBatchSize=opts.MiniBatch, ...
            InitialLearnRate=opts.LR, Verbose=opts.Verbose);
        history.Loss(ep) = info.TrainingLoss(end);
    end
catch ME
    warning("ges:federated:localTrainFail","Lokal eğitim başarısız: %s", ME.message);
end
end
