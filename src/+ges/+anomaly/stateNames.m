function s = stateNames()
%STATENAMES Sağlık durum adları (öncelik sırasıyla; consensus ve etiketleme fonksiyonlarıyla aynı).
%   SmartGridLab (tek evirici, SMA WR13TL22-8231) için genişletilmiş durum seti:
%   * 'grid_event'       — L1 şebeke gerilimi/frekansı nominal dışı (gerçek kesinti, voltage_sag vb.)
%   * 'inverter_trip'    — Şebeke normalken evirici AC üretemiyor (P_ac=0, V_dc>140 V)
%   * 'string_fault'     — DC akım/gerilim kayıpları (bypass, dead-string, voltage_drop)
%   * 'thermal_derating' — Gizli ısıl kısma (MPP → V_oc sürüklenme, dV>+6%, dI<-8%)
%   * 'soiling'          — Panel tozlanması / kirlenme
%   * 'healthy'          — Sağlıklı çalışma
%   * 'offline'          — Gece veya dışa aktarım sona ermiş; veri yok
%   * 'night'            — Güneş yüksekliği < -2° (gece)
%   * 'uncertain'        — Anomali sinyali var ama sınıflandırılamadı
s = ["grid_event" "inverter_trip" "string_fault" "thermal_derating" "soiling" ...
     "healthy" "offline" "night" "uncertain"];
end
