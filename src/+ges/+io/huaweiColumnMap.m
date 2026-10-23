function spec = huaweiColumnMap()
%HUAWEICOLUMNMAP Huawei rapor sütunlarının kanonik ad ve birim tablosu.
%   spec = ges.io.huaweiColumnMap() Key/Name/Unit sütunlu bir tablo döndürür.
%   Key, sütun adının ges.io.columnKey ile [a-z0-9] karakterlerine
%   indirgenmiş halidir; böylece ℃, ², ㎡ gibi Unicode birim farkları
%   eşleştirmeyi bozmaz.

rows = [
    "inputpowerkw"                  "P_dc"           "kW"
    "activepowerkw"                 "P_ac"           "kW"
    "reactivepowerkvar"             "Q"              "kvar"
    "powerfactor"                   "PF"             ""
    "gridfrequencyhz"               "f_grid"         "Hz"
    "gridacurrenta"                 "I_a"            "A"
    "gridbcurrenta"                 "I_b"            "A"
    "gridccurrenta"                 "I_c"            "A"
    "gridablinevoltagev"            "U_ab"           "V"
    "gridbclinevoltagev"            "U_bc"           "V"
    "gridcalinevoltagev"            "U_ca"           "V"
    "devicestatus"                  "Status"         ""
    "dailyenergykwh"                "E_day"          "kWh"
    "inverterefficiency"            "Eff"            "%"
    "lifetimeenergykwh"             "E_life"         "kWh"
    "cabinettemperature"            "T_cab"          "°C"
    "totalirradiancewm"             "G"              "W/m^2"
    "dailyirradiationkwhm"          "H_day"          "kWh/m^2"
    "totalirradiance2w"             "G2"             "W/m^2"
    "dailyirradiationamount2kwhm"   "H2_day"         "kWh/m^2"
    "pvmoduletemp"                  "T_mod"          "°C"
    "ambienttemp"                   "T_amb"          "°C"
    "windspeedms"                   "WindSpeed"      "m/s"
    "winddirection"                 "WindDir"        ""
    "activeschedulingmode"          "SchedP_Mode"    ""
    "activeschedulingtargetkw"      "SchedP_Target"  "kW"
    "reactiveschedulingmode"        "SchedQ_Mode"    ""
    "reactiveschedulingprofilemode" "SchedQ_Profile" ""
    "reactiveschedulingtargetkvar"  "SchedQ_Target"  "kvar"
    ];
pv = (1:8)';
rows = [rows
    "pv" + pv + "inputvoltagev", "V_pv" + pv, repmat("V", 8, 1)
    "pv" + pv + "inputcurrenta", "I_pv" + pv, repmat("A", 8, 1)];

spec = table(rows(:,1), rows(:,2), rows(:,3), VariableNames=["Key" "Name" "Unit"]);
end
