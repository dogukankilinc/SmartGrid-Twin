function renderDataPage(app, force) %#ok<INUSD>
%RENDERDATAPAGE Veri sayfası: seçilen dosyalar tablosu, SMA/Huawei kabin özeti ve veri setleri.
kindTr = dictionary(["sma_combined" "meteo" "inverter" "logger" "loggerControl" "plant" "unknown"], ...
    ["SMA Birleşik" "Meteoroloji" "Evirici" "SmartLogger" "SmartLogger" "Tesis sayacı" "Tanınmadı"]);
c = app.Dt.Files;
if isempty(c)
    app.Dt.Table.Data = table();
    app.Dt.Summary.Text = "Henüz dosya eklenmedi. Soldaki düğmelerle SMA Birleşik CSV veya klasörden toplu yükleyin.";
else
    fmt = @(t) string(t, "dd.MM.yyyy HH:mm");
    kNames = c.Kind;
    knownK = isKey(kindTr, kNames);
    kNames(knownK) = kindTr(kNames(knownK));
    app.Dt.Table.Data = table(c.Name, kNames, c.Id, c.Cabin, fmt(c.First), fmt(c.Last), c.Note, ...
        VariableNames=["Dosya" "Tür" "Cihaz" "Kabin" "İlk zaman" "Son zaman" "Not"]);
    hasSma = any(c.Kind == "sma_combined");
    inv = unique(c(ismember(c.Kind, ["inverter" "sma_combined"]), ["Id" "Cabin"]), "rows");
    lines = sprintf("%d kayıt, %d benzersiz dosya.", height(c), numel(unique(c.File)));
    if ~isempty(inv)
        [g, cab] = findgroups(inv.Cabin);
        cnt = splitapply(@numel, inv.Id, g);
        lines = lines + " Haritada açılacak birimler: " + strjoin(compose("Kabin %d (%d cihaz)", cab, cnt), ", ") + ".";
    end
    met = unique(c.Id(ismember(c.Kind, ["meteo" "sma_combined"])));
    lines = lines + " Meteoroloji: " + ifelse(isempty(met), "YOK — en az bir istasyon gerekli", strjoin(met, ", ")) + ".";
    lines = lines + " Tesis sayacı: " + ifelse(any(ismember(c.Kind, ["plant" "sma_combined"])), "var", "yok (isteğe bağlı)") + ".";
    if hasSma
        lines = lines + " [SMA Sunny Portal 21-sütun birleşik format algılandı: 0 kayıplı okuma aktif].";
    end
    if any(c.Kind == "unknown")
        lines = lines + sprintf(" ⚠ %d dosya tanınmadı (Not sütunu).", nnz(c.Kind == "unknown"));
    end
    app.Dt.Summary.Text = lines;
end
W = ges.ingest.listWorkspaces(gesConfig());
items = "Eğitim verisi (varsayılan)";
data = "";
for k = 1:height(W)
    items(end+1) = sprintf("%s  (%s – %s, %d cihaz)", W.Name(k), string(W.Start(k), "dd.MM.yyyy"), ...
        string(W.End(k), "dd.MM.yyyy"), W.NumInverters(k)); %#ok<AGROW>
    data(end+1) = W.Name(k); %#ok<AGROW>
end
app.Dt.Sets.Items = items;
app.Dt.Sets.ItemsData = data;
if ismember(app.Dataset, data)
    app.Dt.Sets.Value = app.Dataset;
end
[t0, t1] = app.Engine.range();
app.Dt.Current.Text = sprintf("Şu an gösterilen: %s · %s – %s · %d evirici, %d kabin/birim", ...
    ifelse(app.Dataset == "", "eğitim verisi (" + app.Cfg.site.name + ")", "veri seti '" + app.Dataset + "'"), ...
    string(t0, "dd.MM.yyyy"), string(t1, "dd.MM.yyyy"), numel(app.Engine.Ids), numel(unique(app.Engine.Cabin)));
end
