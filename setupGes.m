function setupGes()
%SETUPGES BTÜ SmartGridLab GES proje klasörlerini MATLAB yoluna ekler.
%   Her betiğin başında çağrılır; tekrar çağrılması zararsızdır.

root = fileparts(mfilename("fullpath"));
addpath(root, fullfile(root, "app"), fullfile(root, "config"), ...
    fullfile(root, "src"), fullfile(root, "scripts"), ...
    fullfile(root, "scripts", "v2"), fullfile(root, "scripts", "v3"), ...
    fullfile(root, "tests"));
end
