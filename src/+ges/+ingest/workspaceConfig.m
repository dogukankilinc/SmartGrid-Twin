function cfg = workspaceConfig(cfg, name)
%WORKSPACECONFIG Yüklenen bir veri seti (workspace/<ad>) için yol yapılandırması.
name = string(name);
if name == ""
    return
end
ws = fullfile(cfg.paths.root, "workspace", name);
if ~isfolder(ws)
    error("ges:ingest:noWorkspace", "Veri seti bulunamadı: %s", ws);
end
cfg.workspace = name;
cfg.paths.workspace = ws;
cfg.paths.processed = fullfile(ws, "processed");
cfg.paths.interim = fullfile(ws, "interim");
cfg.paths.anomaly = fullfile(ws, "anomaly");
cfg.paths.throttle = fullfile(ws, "throttle");
cfg.paths.throttleP = fullfile(ws, "throttle_p");
cfg.paths.runtime = fullfile(ws, "runtime");
m = load(fullfile(ws, "manifest.mat")).manifest;
if isfield(m, "SiteName") && strlength(m.SiteName) > 0
    cfg.site.name = m.SiteName;
end
end
