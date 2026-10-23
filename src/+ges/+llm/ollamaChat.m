function [reply, raw] = ollamaChat(messages, opts)
%OLLAMACHAT Yerel Ollama sunucusuna (internetsiz) sohbet isteği gönderir.
%   [reply, raw] = ges.llm.ollamaChat(messages)
%   messages : 1×N hücre; her eleman struct("role", "system"|"user"|"assistant"|"tool",
%              "content", metin) ve isteğe bağlı "images" (base64 PNG hücresi)
%   reply    : struct — Content (metin), ToolCalls (struct dizisi: Name, Arguments),
%              Seconds (yanıt süresi), EvalTokens, TokensPerSecond
%   raw      : sunucunun ham yanıtı
%   Seçenekler: Model, Tools (Ollama/OpenAI fonksiyon şeması hücresi), Format ("json"
%   ile yapılandırılmış çıktı), Temperature, NumCtx, Url, Timeout, Options (ek model
%   seçenekleri), Think (düşünme modu; varsayılan kapalı).
%   Sahada aynı istek Jetson (Ollama ARM64+CUDA) veya LabVIEW (HTTP) üzerinden de atılabilir.
arguments
    messages (1,:) cell
    opts.Model (1,1) string = "gemma4:e4b"
    opts.Tools cell = {}
    opts.Format string = string.empty
    opts.Temperature (1,1) double = 0.2
    opts.NumCtx (1,1) double = 8192
    opts.Url (1,1) string = "http://localhost:11434/api/chat"
    opts.Timeout (1,1) double = 600
    opts.Options (1,1) struct = struct()      % ek Ollama seçenekleri (ör. num_gpu = 0 → yalnızca CPU)
    opts.Think (1,1) logical = false           % "düşünme" modu: kısa bakım mesajları için kapalı (hız)
    opts.KeepAlive (1,1) string = "60m"        % model GPU'da yüklü kalır (Ollama varsayılanı 5 dk)
end

% DİKKAT: num_ctx her çağrıda AYNI olmalı; farklı değer Ollama'nın modeli boşaltıp yeniden
% yüklemesine yol açar (ölçüm: sıcak çağrı 1,3 s, num_ctx değişince 23,5 s).
modelOptions = struct("temperature", opts.Temperature, "num_ctx", opts.NumCtx);
for f = string(fieldnames(opts.Options))'
    modelOptions.(f) = opts.Options.(f);
end
body = struct("model", opts.Model, "stream", false, "think", opts.Think, "options", modelOptions, ...
    "keep_alive", opts.KeepAlive);
body.messages = messages;
if ~isempty(opts.Tools)
    body.tools = opts.Tools;
end
if ~isempty(opts.Format)
    body.format = opts.Format;
end

wo = weboptions(MediaType="application/json", Timeout=opts.Timeout, ContentType="json");
t0 = tic;
raw = webwrite(opts.Url, jsonencode(body), wo);
reply.Seconds = toc(t0);

msg = raw.message;
reply.Content = "";
if isfield(msg, "content") && ~isempty(msg.content)
    reply.Content = string(msg.content);
end
reply.ToolCalls = struct("Name", {}, "Arguments", {});
if isfield(msg, "tool_calls") && ~isempty(msg.tool_calls)
    calls = msg.tool_calls;
    if ~iscell(calls)
        calls = num2cell(calls);
    end
    for i = 1:numel(calls)
        f = calls{i}.function;
        args = struct();
        if isfield(f, "arguments") && ~isempty(f.arguments)
            args = f.arguments;
            if ischar(args) || isstring(args)
                args = jsondecode(args);
            end
        end
        reply.ToolCalls(end+1) = struct("Name", string(f.name), "Arguments", args);
    end
end
reply.EvalTokens = NaN;
reply.TokensPerSecond = NaN;
if isfield(raw, "eval_count") && isfield(raw, "eval_duration") && raw.eval_duration > 0
    reply.EvalTokens = raw.eval_count;
    reply.TokensPerSecond = raw.eval_count / (raw.eval_duration / 1e9);
end
end
