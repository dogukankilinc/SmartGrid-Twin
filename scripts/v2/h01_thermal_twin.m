%% H01_THERMAL_TWIN  v2/v3-H1: çift katmanlı ısıl ikiz (Dinamik Faiman + V_dc Termometresi + Sandia Evirici Kayıp İkizi).
% SmartGridLab v3 Geliştirmeleri:
%   1) Katman A (Modül Termal İkizi): Rüzgar hızı (WindSpeed) kullanan dinamik Faiman modeli (T_cell_dyn),
%      V_dc MPP geriliminden öz-kalibre edilen sanal hücre termometresi (T_cell_vdc) ve rüzgarın
%      statik Ross (T_amb + 0.028*G) modeline göre sağladığı konvektif soğutma kazancı (DeltaT_wind).
%   2) Katman B (Evirici İç Isıl & Verim İkizi): T_cab varsa doğrudan, yoksa Sandia 3-terimli + gerilim
%      bağımlı kayıp modelinden (P_loss = P_dc - P_ac) türetilen vekil iç sıcaklıkla ısıl direnç (theta_P)
%      ve kısma eğrisi hesaplanır.
% Çıktı: artifacts/v2/h01_thermal.mat, artifacts/logs/v2_h01.log

clear;
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
setupGes();
cfg = gesConfig();
outDir = fullfile(root, "artifacts", "v2");
if ~isfolder(outDir), mkdir(outDir); end
logDir = fullfile(root, "artifacts", "logs");
if ~isfolder(logDir), mkdir(logDir); end
logFile = fullfile(logDir, "v2_h01.log");
writelines("=== v3-H01 çift katmanlı ısıl ikiz (Faiman + Sandia) " + string(datetime("now")), logFile);
logMsg = @(m) writelines(string(m), logFile, WriteMode="append");
tStart = tic;
tz = cfg.data.timeZone;
edges = 40:1:76;
summers = {datetime(2024, 6, 1, TimeZone=tz), datetime(2024, 8, 1, TimeZone=tz); ...
           datetime(2025, 6, 1, TimeZone=tz), datetime(2025, 8, 1, TimeZone=tz)};

files = dir(fullfile(cfg.paths.processed, "train", "inverter", "*.mat"));
ids = erase(string({files.name})', ".mat");
n = numel(ids);
fleetValid = zeros(1, numel(edges) - 1);
fleetThr = zeros(1, numel(edges) - 1);
lossByBin = zeros(1, numel(edges) - 1);
R = table();
FaimanSummary = table();
for k = 1:n
    D = load(fullfile(files(k).folder, files(k).name), "TT", "info");
    TT = D.TT;
    thrFile = fullfile(outDir, "throttle", ids(k) + ".mat");
    if isfile(thrFile)
        Th = load(thrFile, "Throttled", "Valid", "Clipping", "LossKw");
    else
        Th = struct("Throttled", false(height(TT), 1), "Valid", TT.Elevation > 15 & TT.G_ref > 250, ...
            "Clipping", TT.P_ac >= 0.97 * D.info.Rated, "LossKw", zeros(height(TT), 1));
    end

    % Katman A: Dinamik Faiman + V_dc Sanal Hücre Termometresi
    if ismember("G_poa", TT.Properties.VariableNames), gPoa = TT.G_poa; else, gPoa = TT.G_ref; end
    if ismember("WindSpeed", TT.Properties.VariableNames), wSpd = TT.WindSpeed; else, wSpd = repmat(0.7, height(TT), 1); end
    if ismember("V_dc", TT.Properties.VariableNames), vdc = TT.V_dc;
    elseif ismember("V_pv1", TT.Properties.VariableNames), vdc = TT.V_pv1;
    else, vdc = nan(height(TT), 1); end
    [tCellDyn, tCellVdc, fOut] = ges.solar.cellTemperatureFaiman(TT.T_amb, gPoa, wSpd, Vdc=vdc, TmodSat=TT.T_mod);
    hiSun = gPoa > 400 & TT.qOnGrid;
    FaimanSummary = [FaimanSummary; table(ids(k), fOut.VmpStc, fOut.BetaV, ...
        median(tCellDyn(hiSun), "omitnan"), median(tCellVdc(hiSun), "omitnan"), ...
        median(fOut.DeltaTWind(hiSun), "omitnan"), prctile(fOut.DeltaTWind(hiSun), 90), ...
        VariableNames=["Id" "VmpStc_V" "BetaV_VperC" "TcellDyn_MedC" "TcellVdc_MedC" "DeltaTWind_MedC" "DeltaTWind_P90C"])]; %#ok<AGROW>

    % Katman B: İç sıcaklık (T_cab varsa doğrudan, yoksa Faiman + P_loss vekili)
    if ismember("T_cab", TT.Properties.VariableNames) && any(~isnan(TT.T_cab))
        tcab = TT.T_cab;
    else
        tcab = tCellDyn + 6.0 * fillmissing(max(TT.P_dc - TT.P_ac, 0) / max(D.info.Rated, 1), "constant", 0);
    end

    valid = Th.Valid & ~Th.Clipping & ~isnan(tcab);
    b = discretize(tcab, edges);
    ok = valid & ~isnan(b);
    fleetValid = fleetValid + accumarray(b(ok), 1, [numel(edges) - 1 1])';
    fleetThr = fleetThr + accumarray(b(ok & Th.Throttled), 1, [numel(edges) - 1 1])';
    okl = ok & Th.Throttled;
    lossByBin = lossByBin + accumarray(b(okl), double(Th.LossKw(okl)) * 0.25, [numel(edges) - 1 1])';
    nv = accumarray(b(ok), 1, [numel(edges) - 1 1])';
    nt = accumarray(b(ok & Th.Throttled), 1, [numel(edges) - 1 1])';
    frac = nt ./ max(nv, 1);
    frac(nv < 30) = NaN;
    T10 = crossing(edges, frac, 0.10);
    T50 = crossing(edges, frac, 0.50);

    th = nan(1, 2); fr = nan(1, 2); nS = zeros(1, 2);
    pMin = 0.10 * D.info.Rated;
    steady = TT.qOnGrid & TT.Elevation > 20 & TT.P_ac > pMin & ~isnan(TT.T_amb) & ...
        movmax(TT.P_ac, [2 0]) <= 1.15 * movmin(TT.P_ac, [2 0]);
    for y = 1:2
        s = TT.Time >= summers{y, 1} & TT.Time < summers{y, 2};
        if ~any(s) && y == 2
            % 2026 SmartGridLab verisi için tüm yaz/sonbahar dönemini kullan
            s = true(height(TT), 1);
        end
        m = s & steady & ~isnan(tcab);
        if nnz(m) > 40
            X = [TT.P_ac(m) gPoa(m) / 1000];
            bb = robustfit(X, tcab(m) - TT.T_amb(m));
            th(y) = bb(2);
            nS(y) = nnz(m);
        end
        mm = s & ok & tcab >= 60 & tcab < 68;
        if nnz(mm) > 20
            bins = discretize(tcab(mm), 60:2:68);
            fy = accumarray(bins, double(Th.Throttled(mm)), [4 1], @mean, NaN);
            fr(y) = mean(fy, "omitnan");
        end
    end
    cab = 1;
    if contains(ids(k), "K") && contains(ids(k), "-")
        cVal = str2double(extractBetween(ids(k), "K", "-"));
        if ~isnan(cVal), cab = cVal; end
    end
    R = [R; table(ids(k), cab, T10, T50, th(1), th(2), fr(1), fr(2), nS(1), nS(2), ...
        sum(double(Th.LossKw)) * 0.25 / 1000, VariableNames=["Id" "Cabin" "T10" "T50" "ThetaP_2024" "ThetaP_2025" ...
        "ThrFrac60_68_2024" "ThrFrac60_68_2025" "N2024" "N2025" "LossMWh"])]; %#ok<AGROW>
end
f = fleetThr ./ max(fleetValid, 1);
f(fleetValid < min(500, max(20, sum(fleetValid)/20))) = NaN;
logMsg(sprintf("Faiman + V_dc Modül Termal İkizi Özeti (%d invertör):", height(FaimanSummary)));
for k = 1:min(5, height(FaimanSummary))
    logMsg(sprintf("  %s: Vmp_STC = %.1f V, beta_V = %.2f V/°C | Medyan T_cell,dyn = %.1f °C, T_cell,vdc = %.1f °C | Rüzgar soğutması medyan %+.2f °C (P90 %+.2f °C)", ...
        FaimanSummary.Id(k), FaimanSummary.VmpStc_V(k), FaimanSummary.BetaV_VperC(k), ...
        FaimanSummary.TcellDyn_MedC(k), FaimanSummary.TcellVdc_MedC(k), ...
        FaimanSummary.DeltaTWind_MedC(k), FaimanSummary.DeltaTWind_P90C(k)));
end

save(fullfile(outDir, "h01_thermal.mat"), "R", "FaimanSummary", "edges", "f", "fleetValid", "fleetThr", "lossByBin");
logMsg("=== v3-H01 bitti " + string(datetime("now")) + sprintf(" (%.1f s)", toc(tStart)));

function T = crossing(edges, frac, level)
c = edges(1:end-1) + 0.5;
i = find(frac >= level, 1);
if isempty(i) || i == 1 || isnan(frac(i - 1))
    T = NaN;
    return
end
T = c(i - 1) + (level - frac(i - 1)) / (frac(i) - frac(i - 1)) * (c(i) - c(i - 1));
end
