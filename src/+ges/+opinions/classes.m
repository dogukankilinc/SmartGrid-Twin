function c = classes()
%CLASSES Üç görüşün ve uzlaşının ortak sınıf düzeni (öncelik sırası).
%   Öncelik: şebeke/kabin > trip > string > ısıl kısma > tozlanma.
%   SmartGridLab'da 'string_fault' alt tipleri Detail alanında tutulur:
%     'current_step_drop' (paralel dizi kopması), 'voltage_drop' (bypass diyot kısa devresi),
%     'efficiency_collapse' (evirici verim çöküşü), 'voltage_sag_swell' (L1 gerilim dalgalanması).
c = ["grid_event" "inverter_trip" "string_fault" "thermal_derating" "soiling" "healthy"];
end
