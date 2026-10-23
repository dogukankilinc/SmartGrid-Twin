function [ws, cfg2] = listWorkspaces(opts)
%LISTWORKSPACES Kayıtlı çalışma alanlarını (workspace) listele.
%   [ws, cfg2] = ges.ingest.listWorkspaces() — SmartGridLab: varsayılan olarak
%   artifacts/processed altındaki eğitim ve holdout çalışma alanlarını döndürür.
%   Çok tesis senaryosu için workspaceConfig.m ile yapılandırılabilir.
arguments
    opts.ConfigFile (1,1) string = ""   % boşsa varsayılan
end
try
    cfg2 = gesConfig();
catch
    cfg2 = struct();
end

ws = struct("Id", {}, "Split", {}, "Path", {}, "NumInverters", {}, "DateRange", {});
splits = ["train" "holdout"];
for sp = splits
    d = fullfile(cfg2.paths.processed, sp, "inverter");
    if ~isfolder(d); continue; end
    mats = dir(fullfile(d, "*.mat"));
    if isempty(mats); continue; end
    ids = string({mats.name}');
    ids = erase(ids, ".mat");
    for k = 1:numel(ids)
        ws(end+1).Id           = ids(k);                 %#ok<AGROW>
        ws(end).Split          = sp;
        ws(end).Path           = fullfile(d, mats(k).name);
        ws(end).NumInverters   = 1;
        ws(end).DateRange      = "";
    end
end
end
