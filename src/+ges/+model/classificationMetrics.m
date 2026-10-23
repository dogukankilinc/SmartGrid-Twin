function m = classificationMetrics(yTrue, yPred, opts)
%CLASSIFICATIONMETRICS Sınıflandırma metriklerini hesapla (Accuracy, F1, Precision, Recall, κ).
%   m = ges.model.classificationMetrics(yTrue, yPred) — string/categorical diziler.
%   SmartGridLab: 6 sınıflı (grid_event, inverter_trip, string_fault, thermal_derating, soiling, healthy).
arguments
    yTrue (:,1)
    yPred (:,1)
    opts.Classes (1,:) string = ges.opinions.classes()
    opts.Verbose (1,1) logical = false
end
yT = string(yTrue);  yP = string(yPred);
cls = opts.Classes;
n = numel(yT);
m.Accuracy = mean(yT == yP, "omitmissing");
m.ConfMat  = confusionmat(yT, yP, Order=cls);

prec = zeros(numel(cls),1);  rec = prec;  f1 = prec;
for i = 1:numel(cls)
    tp = sum(yT == cls(i) & yP == cls(i));
    fp = sum(yT ~= cls(i) & yP == cls(i));
    fn = sum(yT == cls(i) & yP ~= cls(i));
    prec(i) = tp / max(tp+fp, 1);
    rec(i)  = tp / max(tp+fn, 1);
    f1(i)   = 2*prec(i)*rec(i) / max(prec(i)+rec(i), 1e-6);
end
m.Precision = prec;
m.Recall    = rec;
m.F1        = f1;
m.MacroF1   = mean(f1);
% Cohen's κ
pObserved  = m.Accuracy;
pExpected  = sum(sum(m.ConfMat,1)/n .* sum(m.ConfMat,2)'/n);
m.Kappa    = (pObserved - pExpected) / max(1 - pExpected, 1e-9);
m.Classes  = cls;
if opts.Verbose
    fprintf("Accuracy=%.3f  MacroF1=%.3f  κ=%.3f\n", m.Accuracy, m.MacroF1, m.Kappa);
    for i=1:numel(cls)
        fprintf("  %-22s  P=%.3f  R=%.3f  F1=%.3f\n", cls(i), prec(i), rec(i), f1(i));
    end
end
end
