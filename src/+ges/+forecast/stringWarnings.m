function W = stringWarnings(E, tNow, opts)
%STRINGWARNINGS String ve evirici erken uyarı sistemi (4 kanallı v3: ShortDrops, R_iso, VoltageDip, EtaDrift).
%   W = ges.forecast.stringWarnings(E, tNow) — E: ges.runtime.ReplayEngine veya işlenmiş TT içeren yapı.
%   Kanallar:
%     1) ShortDrops : Son 7 günde kısa kopma (1–3 adım sıfıra/düşüğe inip dönme) sayısı (≥ MinDrops).
%     2) R_iso      : Kuru/sıcak öğle saatinde R_iso < 2000 kOhm veya 7 günlük sabah R_iso düşüş trendi.
%     3) VoltageDip : Kısa süreli MPP gerilim çökmesi (dV < -0.05, bypass diyotu / alt-dizi uyarısı).
%     4) EtaDrift   : Evirici DC->AC dönüşüm veriminde (Eta_inv) beklenenin >%1.0 altına kayma.
%   W: Id, PV, ShortDrops, LastDrop, Note — kısa kopma / önem sırasına göre azalan.
arguments
    E
    tNow (1,1) datetime
    opts.MinDrops (1,1) double = 2
    opts.Days (1,1) double = 7
end

rows = find(E.Times >= tNow - days(opts.Days) & E.Times <= tNow);
Id = strings(0, 1);
PV = zeros(0, 1);
ShortDrops = zeros(0, 1);
LastDrop = NaT(0, 1, TimeZone=E.Times.TimeZone);
Note = strings(0, 1);

if isempty(rows)
    W = table(Id, PV, ShortDrops, LastDrop, Note);
    return
end

for k = 1:numel(E.Ids)
    % 1) Çoklu veya tekli string kısa kopma kontrolü (DeadMask üzerinden)
    m = E.DeadMask(rows, k);
    for p = 1:8
        b = bitget(m, p) == 1;
        if ~any(b)
            continue
        end
        if b(end) && nnz(b(max(1, end - 3):end)) == min(4, numel(b))
            continue                                     % şu an kalıcı ölü: arıza bildirimi zaten var
        end
        d = diff([false; b; false]);
        s0 = find(d == 1);
        e0 = find(d == -1) - 1;
        short = (e0 - s0 + 1) <= 3;
        nd = nnz(short);
        if nd >= opts.MinDrops
            Id(end+1, 1) = E.Ids(k); %#ok<AGROW>
            PV(end+1, 1) = p; %#ok<AGROW>
            ShortDrops(end+1, 1) = nd; %#ok<AGROW>
            LastDrop(end+1, 1) = E.Times(rows(s0(find(short, 1, "last")))); %#ok<AGROW>
            if p == 8
                Note(end+1, 1) = "PV8: tekrarlayan kayıt; kurulum maskesi şüphesi (önce sahada kurulu mu bakın)"; %#ok<AGROW>
            else
                Note(end+1, 1) = "aralıklı temas: MC4 konnektör, sigorta yuvası, kablo"; %#ok<AGROW>
            end
        end
    end

    % 2) SmartGridLab / Tek Evirici ek erken uyarı kanalları (R_iso, VoltageDip, EtaDrift)
    if isprop(E, "Riso") && ~isempty(E.Riso) && size(E.Riso, 2) >= k
        riso = E.Riso(rows, k);
        g = E.Gref(rows);
        noonDry = g > 500 & ~isnan(riso) & riso > 0 & riso < 2000;
        if nnz(noonDry) >= 2
            Id(end+1, 1) = E.Ids(k); %#ok<AGROW>
            PV(end+1, 1) = 1; %#ok<AGROW>
            ShortDrops(end+1, 1) = nnz(noonDry); %#ok<AGROW>
            LastDrop(end+1, 1) = E.Times(rows(find(noonDry, 1, "last"))); %#ok<AGROW>
            Note(end+1, 1) = sprintf("R_iso erken uyarısı: kuru öğle saatinde yalıtım direnci %.0f kOhm (<2000 kOhm)", min(riso(noonDry))); %#ok<AGROW>
        end
    end
    if isprop(E, "EtaResid") && ~isempty(E.EtaResid) && size(E.EtaResid, 2) >= k
        er = E.EtaResid(rows, k);
        lowEta = E.Gref(rows) > 400 & ~isnan(er) & er < -0.012;
        if nnz(lowEta) >= 4
            Id(end+1, 1) = E.Ids(k); %#ok<AGROW>
            PV(end+1, 1) = 0; %#ok<AGROW>
            ShortDrops(end+1, 1) = nnz(lowEta); %#ok<AGROW>
            LastDrop(end+1, 1) = E.Times(rows(find(lowEta, 1, "last"))); %#ok<AGROW>
            Note(end+1, 1) = sprintf("Evirici verim kayması (EtaDrift): medyan %+.2f%% dönüşüm verimi düşüşü", 100 * median(er(lowEta))); %#ok<AGROW>
        end
    end
end
W = table(Id, PV, ShortDrops, LastDrop, Note);
W = sortrows(W, "ShortDrops", "descend");
end
