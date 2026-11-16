NB. ===========================================================================
NB. J Sensor Hub - Integración Nativa con JHS (J HTTP Server IDE)
NB. Uso dentro de JHS:
NB.   load '/home/droid/j-sensor-hub/jhs_sensor_app.ijs'
NB.   jpage 'jhs_sensor_app'
NB. ===========================================================================

0!:0 < '/home/droid/j-sensor-hub/sensors.ijs'

coclass 'jhs_sensor_app'
coinsert 'jhs'

HBS =: 0 : 0
jhclose ''
'title' jhh1 'J Sensor Hub (Vista Nativa JHS)'
'sub'   jhdiv 'Monitoreo y álgebra de arreglos en J sobre sensores del sistema'
jhbr
'btn_sample' jhb 'Muestrear Sensores Ahora'
'btn_spike'  jhb 'Inyectar Pico de Prueba'
'btn_reset'  jhb 'Reiniciar Historial'
jhhr
'out_box'    jhdiv ''
)

CSS =: 0 : 0
body { font-family: monospace; margin: 16px; background: #0f172a; color: #e2e8f0; }
#title { color: #33d2f6; }
button { padding: 8px 14px; margin-right: 8px; cursor: pointer; }
#out_box { white-space: pre; background: #1e293b; padding: 12px; border-radius: 8px; margin-top: 12px; }
)

render_summary =: 3 : 0
  sample_all_sensors_base_ ''
  t =. '=== MATRIZ DE SENSORES EN J (sensors_mat_base_) ===' , LF
  t =. t , 'Dimensiones ($): ' , (": $ sensors_mat_base_) , LF
  t =. t , 'Medias por fila (+/ % #)"1 : ' , (": round2_base_ (+/ % #)"1 sensors_mat_base_) , LF
  t =. t , 'Máximos por fila (>./)"1    : ' , (": round2_base_ (>./)"1 sensors_mat_base_) , LF
  t =. t , 'Vector actual (cur_vec)     : ' , (": round2_base_ cur_vec_base_) , LF
  t =. t , 'Umbrales (THRESHOLDS)       : ' , (": THRESHOLDS_base_) , LF
  t =. t , 'Máscara Alertas             : ' , (": alerts_mask_base_) , LF , LF
  t =. t , 'Últimas 8 muestras (CPU / Mem / PSI / Disk / Synth / IMU / Mic):' , LF
  t , ": round2_base_ _8 {."1 sensors_mat_base_
)

ev_create =: 3 : 0
  jhrcmds 'set out_box *' , jhfroma render_summary ''
)

ev_btn_sample_click =: 3 : 0
  jhrcmds 'set out_box *' , jhfroma render_summary ''
)

ev_btn_spike_click =: 3 : 0
  handle_control_base_ 'action=inject_spike'
  jhrcmds 'set out_box *' , jhfroma render_summary ''
)

ev_btn_reset_click =: 3 : 0
  handle_control_base_ 'action=reset_history'
  jhrcmds 'set out_box *' , jhfroma render_summary ''
)
