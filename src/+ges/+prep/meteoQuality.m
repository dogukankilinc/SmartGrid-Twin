function [valid, reason] = meteoQuality(g, poaCs, elevation)
%METEOQUALITY Işınım ölçümünün fiziksel tutarlılık kontrolü.
%   [valid, reason] = ges.prep.meteoQuality(g, poaCs, elevation)
%   g         : ölçülen ışınım (W/m^2), N×1
%   poaCs     : aynı düzlem için açık gökyüzü ışınımı (W/m^2), N×1
%   elevation : güneş yüksekliği (derece), N×1
%   reason    : categorical — ok, missing, negative, tooHigh, nightOffset, stuck

g = g(:);
reason = repmat("ok", size(g));
reason(isnan(g)) = "missing";
reason(g < -5) = "negative";
reason(g > 1.5 * poaCs(:) + 100) = "tooHigh";
reason(elevation(:) < -2 & g > 30) = "nightOffset";

same = [false; diff(g) == 0];
run4 = same & [false; same(1:end-1)] & [false; false; same(1:end-2)];
stuck = movmax(double(run4), [0 3]) > 0 & g > 50;
reason(stuck) = "stuck";

valid = reason == "ok";
reason = categorical(reason, ["ok" "missing" "negative" "tooHigh" "nightOffset" "stuck"]);
end
