function f = ollamaChatAsync(messages, onDone, varargin)
%OLLAMACHATASYNC ollamaChat'i arka plan iş parçacığında çalıştırır; arayüz BLOKLANMAZ.
%   f = ges.llm.ollamaChatAsync(messages, onDone, Name=Value...)
%   Ad-değer seçenekleri ges.llm.ollamaChat ile aynıdır. Yanıt geldiğinde onDone(reply, err)
%   MATLAB ana iş parçacığında çağrılır (err boşsa başarılı; doluysa reply = []).
%   f (parallel.Future) iptal için saklanabilir: cancel(f).
%   Not: HTTP isteği backgroundPool'da (iş parçacığı tabanlı, ek araç kutusu gerekmez)
%   çalışır; grafik/arayüz işleri ana iş parçacığında kalır.
f = parfeval(backgroundPool, @ges.llm.ollamaChat, 1, messages, varargin{:});
afterEach(f, @(fut) deliver(fut, onDone), 0, PassFuture=true);
end

function deliver(fut, onDone)
if isempty(fut.Error)
    onDone(fetchOutputs(fut), []);
else
    onDone([], fut.Error);
end
end
