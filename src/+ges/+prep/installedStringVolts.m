function volts = installedStringVolts(installed, vmppt)
%INSTALLEDSTRINGVOLTS Σ(kurulu stringlerin MPPT gerilimi) — her satır bir invertör.
%   Kurulu olmayan MPPT'lerde NaN gerilim varsa 0*NaN=NaN oluşmasını önler.

mpptOf = [1 1 2 2 3 3 4 4];
vm = vmppt(:, mpptOf);
vm(isnan(vm)) = 0;
volts = sum(double(installed) .* vm, 2);
end
