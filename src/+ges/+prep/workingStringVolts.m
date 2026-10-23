function volts = workingStringVolts(TT, installed, vmppt)
%WORKINGSTRINGVOLTS Her zaman adımında çalışan (ölü olmayan) stringlerin MPPT gerilimleri toplamı.

mpptOf = [1 1 2 2 3 3 4 4];
s = ges.prep.stringFeatures(TT{:, "I_pv" + (1:8)}, installed);
vm = vmppt(mpptOf);
vm(isnan(vm)) = 0;
volts = double(installed & ~s.Dead) * vm(:);
end
