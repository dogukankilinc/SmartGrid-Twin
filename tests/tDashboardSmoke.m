function tests = tDashboardSmoke
%TDASHBOARDSMOKE Panel duman testi (pencere ekranda AÇILMAZ: Visible=false). Çekirdek ve tam mod.
%   Panel açılıyor mu, oynatma ilerliyor mu, tüm sayfalar hatasız çiziliyor mu, teşhis kutusunda üç görüş
%   ve uzlaşı satırı var mı, çekirdek modda araştırma katmanı gerçekten kapalı mı?
%   Süre: çekirdek ~20 s, tam ~1 dk (CNN'ler yüklenir; LLM ısınması arka planda, beklenmez).
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename("fullpath")));
addpath(root, fullfile(root, "app"));
setupGes();
end

function testCoreModePanel(tc)
app = GesDashboard(Visible=false, Layers="core");
tc.addTeardown(@() delete(app));
checkPanel(tc, app);
lines = app.agentText();
tc.verifyTrue(any(contains(lines, "2. görüş") & contains(lines, "kapalı")), "Çekirdek modda görsel görüş kapalı görünmeli");
tc.verifyTrue(any(contains(lines, "UZLAŞI:")));
end

function testFullModePanel(tc)
cfg = gesConfig();
tc.assumeTrue(cfg.layers.research, "Araştırma katmanı yapılandırmada kapalı");
app = GesDashboard(Visible=false, Layers="full");
tc.addTeardown(@() delete(app));
checkPanel(tc, app);
lines = app.agentText();
tc.verifyTrue(any(startsWith(lines, "2. görüş") & ~contains(lines, "kapalı")), "Tam modda görsel görüş çalışmalı");
end

function checkPanel(tc, app)
app.runTicks(8);
for p = ["overview" "map" "analysis" "forecast" "reports" "notify" "data" "help"]
    app.showPage(p);
end
app.selectInverter("K02-INV07");
app.showPage("analysis");
lines = app.agentText();
tc.verifyTrue(any(startsWith(lines, "1. görüş")), "Teşhis kutusunda 1. görüş satırı yok");
tc.verifyTrue(any(startsWith(lines, "3. görüş")), "Teşhis kutusunda 3. görüş satırı yok");
tc.verifyTrue(any(startsWith(lines, "KARAR:")), "Teşhis kutusunda karar satırı yok");
tc.verifyFalse(any(contains(lines, "Error") | contains(lines, "hata")), "Teşhis kutusunda hata metni var");
end
