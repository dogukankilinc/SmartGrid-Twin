function [intercept, slope, slopeCi] = theilSen(x, y, opts)
%THEILSEN Aykırı değerlere dayanıklı doğrusal trend (Theil-Sen) ve eğim güven aralığı.
%   [intercept, slope, slopeCi] = ges.stats.theilSen(x, y)
%   slope   : ikili eğimlerin medyanı; intercept: medyan(y - slope*x)
%   slopeCi : 1×2, ikili eğimlerin dağılımından yaklaşık %95 aralık (Sen, 1968)
%             veya opts.BlockSize > 0 ise blok-bootstrap %95 güven aralığı.
%   NaN değerler atlanır; < MinPoints nokta varsa NaN döner.
arguments
    x (:,1) double
    y (:,1) double
    opts.MinPoints (1,1) double = 4
    opts.BlockSize (1,1) double = 0
    opts.NumBootstrap (1,1) double = 300
end

ok = ~isnan(x) & ~isnan(y);
x = x(ok);
y = y(ok);
n = numel(x);
intercept = NaN;
slope = NaN;
slopeCi = [NaN NaN];
if n < opts.MinPoints
    return
end
[i, j] = find(triu(true(n), 1));
dx = x(j) - x(i);
keep = dx ~= 0;
if ~any(keep)
    return
end
s = sort((y(j(keep)) - y(i(keep))) ./ dx(keep));
slope = median(s);
intercept = median(y - slope * x);
N = numel(s);
c = 1.96 * sqrt(n * (n - 1) * (2 * n + 5) / 18);   % Kendall varyansı
lo = max(1, floor((N - c) / 2));
hi = min(N, ceil((N + c) / 2) + 1);
slopeCi = [s(lo) s(hi)];

if opts.BlockSize > 0 && n >= max(opts.MinPoints, 6)
    blocks = unique(floor((x - min(x)) / opts.BlockSize));
    nb = numel(blocks);
    if nb >= 3
        bs = nan(opts.NumBootstrap, 1);
        bId = floor((x - min(x)) / opts.BlockSize);
        for r = 1:opts.NumBootstrap
            pick = blocks(randi(nb, nb, 1));
            xb = [];
            yb = [];
            for p = 1:nb
                sel = bId == pick(p);
                xb = [xb; x(sel)]; %#ok<AGROW>
                yb = [yb; y(sel)]; %#ok<AGROW>
            end
            if numel(xb) >= opts.MinPoints
                [ib, jb] = find(triu(true(numel(xb)), 1));
                dxb = xb(jb) - xb(ib);
                kb = dxb ~= 0;
                if any(kb)
                    bs(r) = median((yb(jb(kb)) - yb(ib(kb))) ./ dxb(kb));
                end
            end
        end
        bs = bs(~isnan(bs));
        if numel(bs) >= 20
            slopeCi = [prctile(bs, 2.5), prctile(bs, 97.5)];
        end
    end
end
end
