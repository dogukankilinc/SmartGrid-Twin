function spec = smaColumnMap()
%SMACOLUMNMAP SMA Sunny Portal (SmartGridLab Data Manager M) sütunlarının kanonik ad, birim ve rol tablosu.
%   spec = ges.io.smaColumnMap() Key / Name / Unit / Role sütunlu bir tablo döndürür.
%   21 sütunun tamamı (%100 sütun kullanımı, sıfır veri kaybı) kanonik şemaya eşlenir.
%   Key, ges.io.columnKey ile [a-z0-9] karakterlerine indirgenmiş anahtardır.

rows = [
    % Tam (cihaz sonekli) SMA Sunny Portal anahtarları
    "timeperiod"                                     "Time"           ""         "time"
    "powerkwsmadata1wr13tl228231"                    "P_ac"           "kW"       "inverter"
    "specificacpowerkwkwpsmadata1wr13tl228231"       "P_ac_spec"      "kW/kWp"   "inverter"
    "gridvoltagephasel1vsmadata1wr13tl228231"        "U_L1"           "V"        "inverter"
    "gridvoltagephasel2vsmadata1wr13tl228231"        "U_L2"           "V"        "inverter"
    "gridvoltagephasel3vsmadata1wr13tl228231"        "U_L3"           "V"        "inverter"
    "gridcurrentphasel1asmadata1wr13tl228231"        "I_L1"           "A"        "inverter"
    "gridcurrentphasel2asmadata1wr13tl228231"        "I_L2"           "A"        "inverter"
    "gridcurrentphasel3asmadata1wr13tl228231"        "I_L3"           "A"        "inverter"
    "gridfrequencyhzsmadata1wr13tl228231"            "f_grid"         "Hz"       "inverter"
    "dcvoltageinputvsmadata1wr13tl228231"            "V_dc"           "V"        "inverter"
    "dccurrentinputasmadata1wr13tl228231"            "I_dc"           "A"        "inverter"
    "insulationresistancekohmsmadata1wr13tl228231"   "R_iso"          "kOhm"     "inverter"
    "moduletemperaturecsatellitesensor"              "T_mod_sat"      "°C"       "meteo"
    "powerkwsmartgridlab"                            "P_ac_sys"       "kW"       "plant"
    "systemambienttemperaturecsmartgridlab"          "T_amb"          "°C"       "meteo"
    "systeminsolationonexternalsensorwmsmartgridlab" "G_horiz"        "W/m^2"    "meteo"
    "systeminsolationonexternalsensorwm2smartgridlab" "G_horiz"       "W/m^2"    "meteo"
    "systeminsolationonexternalsensorw2smartgridlab" "G_horiz"        "W/m^2"    "meteo"
    "systemmoduletemperaturecsmartgridlab"           "T_mod_sys"      "°C"       "meteo"
    "systemwindspeedmssmartgridlab"                  "WindSpeed"      "m/s"      "meteo"
    "activepowerlimitationsetvaluesmartgridlab"      "SchedP_Pct"     "%"        "control"
    "specificacpowerkwkwpsmartgridlab"               "P_ac_spec_sys"  "kW/kWp"   "plant"

    % Cihaz sonekinden arındırılmış genel SMA anahtarları (başka SMA cihazları için)
    "gridvoltagephasel1v"                            "U_L1"           "V"        "inverter"
    "gridvoltagephasel2v"                            "U_L2"           "V"        "inverter"
    "gridvoltagephasel3v"                            "U_L3"           "V"        "inverter"
    "gridcurrentphasel1a"                            "I_L1"           "A"        "inverter"
    "gridcurrentphasel2a"                            "I_L2"           "A"        "inverter"
    "gridcurrentphasel3a"                            "I_L3"           "A"        "inverter"
    "gridfrequencyhz"                                "f_grid"         "Hz"       "inverter"
    "dcvoltageinputv"                                "V_dc"           "V"        "inverter"
    "dccurrentinputa"                                "I_dc"           "A"        "inverter"
    "insulationresistancekohm"                       "R_iso"          "kOhm"     "inverter"
    "moduletemperaturec"                             "T_mod_sat"      "°C"       "meteo"
    "systemambienttemperaturec"                      "T_amb"          "°C"       "meteo"
    "systeminsolationonexternalsensorwm"             "G_horiz"        "W/m^2"    "meteo"
    "systeminsolationonexternalsensorwm2"            "G_horiz"        "W/m^2"    "meteo"
    "systemmoduletemperaturec"                       "T_mod_sys"      "°C"       "meteo"
    "systemwindspeedms"                              "WindSpeed"      "m/s"      "meteo"
    "activepowerlimitationsetvalue"                  "SchedP_Pct"     "%"        "control"
    ];

spec = table(rows(:,1), rows(:,2), rows(:,3), rows(:,4), ...
    VariableNames=["Key" "Name" "Unit" "Role"]);
end
