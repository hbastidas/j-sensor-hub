NB. ===========================================================================
NB. J Sensor Hub - Motor de Sensores en J (J9.7) para Google Pixel (droid VM)
NB. Compatible con Android 16 Linux Terminal (Crosvm / Tensor G4 / ARM64)
NB. https://www.jsoftware.com/
NB. ===========================================================================

require 'convert/pjson'

cocurrent 'base'

NB. --- Verbos Tácitos de Estadística y Álgebra de Arreglos en J --------------
mean     =: +/ % #
minv     =: <./
maxv     =: >./
ptp      =: >./ - <./
variance =: (+/@:*:@(- mean)) % (1 >. #)
stddev   =: %:@variance
movavg   =: 4 : 'if. (#y) < x do. ,mean y else. x (+/ % #)\ y end.'

slope =: 3 : 0
  n =. # y
  if. n < 2 do. 0 return. end.
  xmat =. 1 ,. i. n
  try. {: y %. xmat catch. 0 end.
)

zscore =: 3 : 0
  if. (#y) < 2 do. 0 return. end.
  s =. stddev y
  if. s < 1e_9 do. 0 else. (({:y) - mean y) % s end.
)

round2 =: 0.01 * <.@:(0.5 + 100 * ])
kv     =: 4 : '1 2 $ (<,x) , (<y)'

NB. --- Utilidades de Lectura Segura de /proc y /sys (Kernel 6.12 Android16) --
fread_safe =: 3 : 0
  try.
    r =. 1!:1 < y
    r -. CR
  catch.
    ''
  end.
)

NB. En sysfs (/sys/class/*), st_size es 4096; cortamos hasta el primer LF
fread_line =: 3 : 0
  r =. fread_safe y
  (r i. LF) {. r
)

nums_from_str =: 3 : 0
  if. 0 = #y do. i.0 return. end.
  clean =. ' ' (I. -. y e. '0123456789.') } y
  ". clean
)

NB. --- Estado Global de Sensores, Historial y Controladores ------------------
HIST_LEN =: 60

init_sensors =: 3 : 0
  cpu_hist     =: 20 $ 4.0
  mem_hist     =: 20 $ 45.0
  swap_hist    =: 20 $ 10.0
  load_hist    =: 20 $ 0.20
  psi_cpu_hist =: 20 $ 0.05
  psi_io_hist  =: 20 $ 0.10
  psi_mem_hist =: 20 $ 0.02
  disk_hist    =: 20 $ 0.0
  net_hist     =: 20 $ 0.5
  accel_hist   =: 20 $ 9.81
  mic_hist     =: 20 $ 30.0
  synth_hist   =: 20 $ 50.0

  PREV_CPU_RAW  =: 9 10 $ 0
  PREV_DISK_OPS =: 0
  PREV_NET_RX   =: 0
  PREV_NET_TX   =: 0
  TICK_COUNT    =: 0

  NB. Sensores físicos del Google Pixel enviados por el navegador (Chrome Android)
  CLIENT_ACCEL_X   =: 0
  CLIENT_ACCEL_Y   =: 0
  CLIENT_ACCEL_Z   =: 9.81
  CLIENT_ACCEL_MAG =: 9.81
  CLIENT_GYRO_A    =: 0
  CLIENT_GYRO_B    =: 0
  CLIENT_GYRO_G    =: 0
  CLIENT_COMPASS   =: 0
  CLIENT_TOUCH_PRS =: 0
  CLIENT_TOUCH_PTS =: 0
  CLIENT_BAT_LVL   =: 100
  CLIENT_BAT_CHG   =: 1
  CLIENT_MIC_DB    =: 30
  CLIENT_LIGHT_LUX =: 250
  CLIENT_NET_RTT   =: 20
  CLIENT_PTR_SPEED =: 0
  CLIENT_ACTIVE    =: 0

  NB. 8 canales de sensores:
  NB. 0=cpu_tensor, 1=memoria, 2=psi_pressure, 3=disk_zram, 4=net_virtio, 5=synth_j, 6=pixel_imu, 7=pixel_env
  SENS_ENABLED =: 1 1 1 1 1 1 1 1
  THRESHOLDS   =: 80 85 5 500 500 85 15 75

  ACT_LED_1     =: 0
  ACT_LED_2     =: 0
  ACT_LED_3     =: 0
  ACT_ALARM     =: 0
  ACT_HAPTIC    =: 1
  ACT_AUTO_COOL =: 1
  POLL_MS       =: 1000
  SYNTH_MODE    =: 0
  SYNTH_GAIN    =: 1.0
  SYNTH_OFFSET  =: 50.0

  read_cpu_raw ''
  read_net_virtio ''
  i. 0 0
)

NB. --- CPU Google Tensor G4 (4x A520 + 3x A720 + 1x X4) en /proc/stat --------
read_cpu_raw =: 3 : 0
  txt =. fread_safe '/proc/stat'
  if. 0 = #txt do. 0 ; (8 $ 0) ; (0 0 0) return. end.
  lines =. <;._2 txt
  cpulines =. (3 {. each lines) = <'cpu'
  cpulines =. cpulines # lines
  n =. 9 <. # cpulines
  mat =. (n, 10) $ 0
  for_i. i. n do.
    row =. 10 {. nums_from_str > i { cpulines
    mat =. row i } mat
  end.
  diff =. 0 >. mat - (n {. PREV_CPU_RAW)
  PREV_CPU_RAW =: mat
  totals =. 1 >. +/"1 diff
  idles =. +/"1 (3 4 {"1 diff)
  usages =. round2 100 * 1 - idles % totals
  tot =. {. usages
  cores =. 8 {. (}. usages) , 8 $ 0
  NB. Clusters del Google Tensor: Little (cpu0..3 A520), Mid (cpu4..6 A720), Prime (cpu7 X4)
  c_little =. round2 mean 0 1 2 3 { cores
  c_mid    =. round2 mean 4 5 6 { cores
  c_prime  =. round2 7 { cores
  tot ; cores ; (c_little , c_mid , c_prime)
)

NB. --- Memoria RAM, Swap y Cgroup v2 del contenedor/VM Pixel -----------------
read_mem_info =: 3 : 0
  txt =. fread_safe '/proc/meminfo'
  if. 0 = #txt do. 0 0 0 0 0 return. end.
  lines =. <;._2 txt
  vals =. ; {. each nums_from_str each 20 {. lines
  if. (#vals) < 16 do. 0 0 0 0 0 return. end.
  mem_total =. 1 >. 0 { vals
  mem_free  =. 1 { vals
  mem_avail =. 2 { vals
  swap_tot  =. 1 >. 14 { vals
  swap_free =. 15 { vals
  used_pct  =. round2 100 * (mem_total - mem_avail) % mem_total
  swap_pct  =. round2 100 * (swap_tot - swap_free) % swap_tot
  total_mb  =. <. mem_total % 1024
  avail_mb  =. <. mem_avail % 1024
  used_pct , swap_pct , total_mb , avail_mb , mem_free
)

read_load_uptime =: 3 : 0
  ltxt =. fread_safe '/proc/loadavg'
  utxt =. fread_safe '/proc/uptime'
  lnums =. 3 {. (nums_from_str ltxt) , 0 0 0
  unums =. 2 {. (nums_from_str utxt) , 0 0
  lnums , unums
)

read_psi =: 3 : 0
  p_cpu =. 3 {. (nums_from_str fread_safe '/proc/pressure/cpu') , 0 0 0
  p_io  =. 3 {. (nums_from_str fread_safe '/proc/pressure/io') , 0 0 0
  p_mem =. 3 {. (nums_from_str fread_safe '/proc/pressure/memory') , 0 0 0
  p_irq =. 3 {. (nums_from_str fread_safe '/proc/pressure/irq') , 0 0 0
  ({. p_cpu) , ({. p_io) , ({. p_mem) , ({. p_irq)
)

read_disk_io =: 3 : 0
  txt =. fread_safe '/proc/diskstats'
  if. 0 = #txt do. 0 0 0 return. end.
  lines =. <;._2 txt
  total_ios =. 0
  read_sec  =. 0
  write_sec =. 0
  for_ln. lines do.
    s =. > ln
    if. (+./ 'vda ' E. s) +. (+./ 'zram0 ' E. s) do.
      ns =. nums_from_str s
      if. (#ns) >: 10 do.
        total_ios =. total_ios + (2 { ns) + (6 { ns)
        read_sec  =. read_sec + (4 { ns)
        write_sec =. write_sec + (8 { ns)
      end.
    end.
  end.
  delta_ops =. 0 >. total_ios - PREV_DISK_OPS
  if. PREV_DISK_OPS = 0 do. delta_ops =. 0 end.
  PREV_DISK_OPS =: total_ios
  delta_ops , (<. read_sec % 2048) , (<. write_sec % 2048)
)

NB. --- Red Virtio del Google Pixel (/sys/class/net/enp0s14/statistics/*) -----
read_net_virtio =: 3 : 0
  rx_b =. {. (nums_from_str fread_line '/sys/class/net/enp0s14/statistics/rx_bytes') , 0
  tx_b =. {. (nums_from_str fread_line '/sys/class/net/enp0s14/statistics/tx_bytes') , 0
  rx_p =. {. (nums_from_str fread_line '/sys/class/net/enp0s14/statistics/rx_packets') , 0
  tx_p =. {. (nums_from_str fread_line '/sys/class/net/enp0s14/statistics/tx_packets') , 0
  if. PREV_NET_RX = 0 do.
    d_rx_kb =. 0
    d_tx_kb =. 0
  else.
    d_rx_kb =. round2 (0 >. rx_b - PREV_NET_RX) % 1024
    d_tx_kb =. round2 (0 >. tx_b - PREV_NET_TX) % 1024
  end.
  PREV_NET_RX =: rx_b
  PREV_NET_TX =: tx_b
  tot_kb_s =. round2 d_rx_kb + d_tx_kb
  rx_mb =. round2 rx_b % 1048576
  tx_mb =. round2 tx_b % 1048576
  tot_kb_s , d_rx_kb , d_tx_kb , rx_mb , tx_mb , rx_p , tx_p
)

NB. --- Periféricos Hardware del Pixel VM (/sys/class/* y /proc/version) ------
read_hw_peripherals =: 3 : 0
  rtc_date  =. fread_line '/sys/class/rtc/rtc0/date'
  rtc_time  =. fread_line '/sys/class/rtc/rtc0/time'
  rtc_epoch =. {. (nums_from_str fread_line '/sys/class/rtc/rtc0/since_epoch') , 0
  net_state =. fread_line '/sys/class/net/enp0s14/operstate'
  net_mac   =. fread_line '/sys/class/net/enp0s14/address'
  drm_stat  =. fread_line '/sys/class/drm/card0-Virtual-1/status'
  snd_id    =. fread_line '/sys/class/sound/card0/id'
  in0       =. fread_line '/sys/class/input/input0/name'
  in1       =. fread_line '/sys/class/input/input1/name'
  in2       =. fread_line '/sys/class/input/input2/name'
  in3       =. fread_line '/sys/class/input/input3/name'
  rtc_date ; rtc_time ; rtc_epoch ; net_state ; net_mac ; drm_stat ; snd_id ; < (in0 ; in1 ; in2 ; in3)
)

compute_synth =: 3 : 0
  TICK_COUNT =: >: TICK_COUNT
  phase =. 0.25 * TICK_COUNT
  base_wave =. SYNTH_OFFSET + (20 * SYNTH_GAIN * 1 o. phase) + (5 * SYNTH_GAIN * 2 o. (2.7 * phase))
  noise =. (_5 + ? 11) * 0.6 * SYNTH_GAIN
  select. SYNTH_MODE
  case. 0 do. val =. base_wave + 0.3 * noise
  case. 1 do. val =. SYNTH_OFFSET + (_25 + ? 51) * SYNTH_GAIN
  case. 2 do. val =. base_wave + 45 * SYNTH_GAIN
  fcase.  do. val =. base_wave
  end.
  round2 0 >. 100 <. val
)

push_hist =: 4 : '((-HIST_LEN) {. x , y)'

stats_kv =: 3 : 0
  v   =. , y
  cur =. round2 {: v
  mn  =. round2 mean v
  sd  =. round2 stddev v
  lo  =. round2 minv v
  hi  =. round2 maxv v
  sl  =. round2 slope v
  zs  =. round2 zscore v
  ma5 =. round2 {: 5 movavg v
  ('current' kv cur) , ('mean' kv mn) , ('std' kv sd) , ('min' kv lo) , ('max' kv hi) , ('slope' kv sl) , ('zscore' kv zs) , ('ma5' kv ma5) , ('history' kv round2 v)
)

NB. --- Paso Principal de Muestreo y Álgebra Matricial en J -------------------
sample_all_sensors =: 3 : 0
  'cpu_tot cpu_cores cpu_clusters' =. read_cpu_raw ''
  'mem_pct swap_pct mem_tot_mb mem_avail_mb mem_free_kb' =. read_mem_info ''
  'load1 load5 load15 up_sec idle_sec' =. read_load_uptime ''
  'psi_c psi_i psi_m psi_q' =. read_psi ''
  'disk_ops disk_r_mb disk_w_mb' =. read_disk_io ''
  'net_kbs net_rx_kbs net_tx_kbs net_rx_mb net_tx_mb net_rx_p net_tx_p' =. read_net_virtio ''
  'rtc_d rtc_t rtc_ep net_st net_mc drm_s snd_s inputs' =. read_hw_peripherals ''
  synth_val =. compute_synth ''

  if. 0 { SENS_ENABLED do.
    cpu_hist  =: cpu_hist push_hist cpu_tot
    load_hist =: load_hist push_hist load1
  end.
  if. 1 { SENS_ENABLED do.
    mem_hist  =: mem_hist push_hist mem_pct
    swap_hist =: swap_hist push_hist swap_pct
  end.
  if. 2 { SENS_ENABLED do.
    psi_cpu_hist =: psi_cpu_hist push_hist psi_c
    psi_io_hist  =: psi_io_hist push_hist psi_i
    psi_mem_hist =: psi_mem_hist push_hist psi_m
  end.
  if. 3 { SENS_ENABLED do.
    disk_hist =: disk_hist push_hist disk_ops
  end.
  if. 4 { SENS_ENABLED do.
    net_hist =: net_hist push_hist net_kbs
  end.
  if. 5 { SENS_ENABLED do.
    synth_hist =: synth_hist push_hist synth_val
  end.
  if. 6 { SENS_ENABLED do.
    accel_hist =: accel_hist push_hist CLIENT_ACCEL_MAG
  end.
  if. 7 { SENS_ENABLED do.
    mic_hist =: mic_hist push_hist CLIENT_MIC_DB
  end.

  NB. Matriz global de 8 sensores x últimas 20 muestras en J
  n_win =. 20 <. <./ (#cpu_hist),(#mem_hist),(#psi_cpu_hist),(#disk_hist),(#net_hist),(#synth_hist),(#accel_hist),(#mic_hist)
  sensors_mat =: ((-n_win){.cpu_hist) , ((-n_win){.mem_hist) , ((-n_win){.psi_cpu_hist) , ((-n_win){.disk_hist) , ((-n_win){.net_hist) , ((-n_win){.synth_hist) , ((-n_win){.accel_hist) ,: ((-n_win){.mic_hist)

  cur_vec     =: ({:cpu_hist) , ({:mem_hist) , ({:psi_cpu_hist) , ({:disk_hist) , ({:net_hist) , ({:synth_hist) , ({:accel_hist) , ({:mic_hist)
  alerts_mask =: SENS_ENABLED *. (cur_vec > THRESHOLDS)

  if. ACT_AUTO_COOL do.
    ACT_LED_3 =: +./ alerts_mask
  end.

  sys_info =. ('engine' kv JVERSION) , ('platform' kv 'Google Pixel Linux VM (Android 16 / Crosvm / Tensor G4 aarch64)') , ('soc_topology' kv '4x Cortex-A520 (0xd80) + 3x Cortex-A720 (0xd81) + 1x Cortex-X4 (0xd82)') , ('tick' kv TICK_COUNT) , ('uptime_sec' kv round2 up_sec) , ('poll_ms' kv POLL_MS) , ('rtc_date' kv rtc_d) , ('rtc_time' kv rtc_t) , ('rtc_epoch' kv rtc_ep) , ('net_if' kv 'enp0s14 (' , net_st , ' / ' , net_mc , ')') , ('drm_status' kv drm_s) , ('sound_card' kv snd_s) , ('input_devices' kv inputs)

  s_cpu   =. (stats_kv cpu_hist) , ('cores' kv round2 cpu_cores) , ('clusters' kv round2 cpu_clusters) , ('enabled' kv 0{SENS_ENABLED) , ('threshold' kv 0{THRESHOLDS) , ('alert' kv 0{alerts_mask)
  s_mem   =. (stats_kv mem_hist) , ('swap_pct' kv swap_pct) , ('total_mb' kv mem_tot_mb) , ('avail_mb' kv mem_avail_mb) , ('enabled' kv 1{SENS_ENABLED) , ('threshold' kv 1{THRESHOLDS) , ('alert' kv 1{alerts_mask)
  s_psi   =. (stats_kv psi_cpu_hist) , ('io_avg10' kv psi_i) , ('mem_avg10' kv psi_m) , ('irq_avg10' kv psi_q) , ('enabled' kv 2{SENS_ENABLED) , ('threshold' kv 2{THRESHOLDS) , ('alert' kv 2{alerts_mask)
  s_disk  =. (stats_kv disk_hist) , ('read_mb' kv disk_r_mb) , ('write_mb' kv disk_w_mb) , ('enabled' kv 3{SENS_ENABLED) , ('threshold' kv 3{THRESHOLDS) , ('alert' kv 3{alerts_mask)
  s_net   =. (stats_kv net_hist) , ('rx_kbs' kv net_rx_kbs) , ('tx_kbs' kv net_tx_kbs) , ('rx_mb' kv net_rx_mb) , ('tx_mb' kv net_tx_mb) , ('rx_pkts' kv net_rx_p) , ('tx_pkts' kv net_tx_p) , ('enabled' kv 4{SENS_ENABLED) , ('threshold' kv 4{THRESHOLDS) , ('alert' kv 4{alerts_mask)
  s_load  =. (stats_kv load_hist) , ('load5' kv load5) , ('load15' kv load15)
  s_synth =. (stats_kv synth_hist) , ('mode' kv SYNTH_MODE) , ('gain' kv SYNTH_GAIN) , ('offset' kv SYNTH_OFFSET) , ('enabled' kv 5{SENS_ENABLED) , ('threshold' kv 5{THRESHOLDS) , ('alert' kv 5{alerts_mask)
  s_imu   =. (stats_kv accel_hist) , ('ax' kv round2 CLIENT_ACCEL_X) , ('ay' kv round2 CLIENT_ACCEL_Y) , ('az' kv round2 CLIENT_ACCEL_Z) , ('ga' kv round2 CLIENT_GYRO_A) , ('gb' kv round2 CLIENT_GYRO_B) , ('gg' kv round2 CLIENT_GYRO_G) , ('compass' kv round2 CLIENT_COMPASS) , ('touch_pressure' kv round2 CLIENT_TOUCH_PRS) , ('touch_points' kv CLIENT_TOUCH_PTS) , ('active' kv CLIENT_ACTIVE) , ('enabled' kv 6{SENS_ENABLED) , ('threshold' kv 6{THRESHOLDS) , ('alert' kv 6{alerts_mask)
  s_env   =. (stats_kv mic_hist) , ('battery_level' kv CLIENT_BAT_LVL) , ('battery_charging' kv CLIENT_BAT_CHG) , ('light_lux' kv CLIENT_LIGHT_LUX) , ('net_rtt' kv CLIENT_NET_RTT) , ('ptr_speed' kv round2 CLIENT_PTR_SPEED) , ('enabled' kv 7{SENS_ENABLED) , ('threshold' kv 7{THRESHOLDS) , ('alert' kv 7{alerts_mask)

  sensors_data =. ('cpu' kv s_cpu) , ('memory' kv s_mem) , ('psi' kv s_psi) , ('disk' kv s_disk) , ('net' kv s_net) , ('load' kv s_load) , ('synth' kv s_synth) , ('client_imu' kv s_imu) , ('client_env' kv s_env)

  actuators_data =. ('led1' kv ACT_LED_1) , ('led2' kv ACT_LED_2) , ('led3' kv ACT_LED_3) , ('alarm' kv ACT_ALARM) , ('haptic' kv ACT_HAPTIC) , ('auto_cool' kv ACT_AUTO_COOL) , ('synth_mode' kv SYNTH_MODE) , ('synth_gain' kv SYNTH_GAIN) , ('synth_offset' kv SYNTH_OFFSET)

  j_matrix_summary =. ('shape' kv $ sensors_mat) , ('row_means' kv round2 (+/ % #)"1 sensors_mat) , ('row_maxs' kv round2 (>./)"1 sensors_mat) , ('row_stds' kv round2 stddev"1 sensors_mat) , ('active_alerts' kv +/ alerts_mask)

  root =. ('status' kv 'ok') , ('system' kv sys_info) , ('sensors' kv sensors_data) , ('actuators' kv actuators_data) , ('j_analytics' kv j_matrix_summary)
  enc_pjson_ root
)

NB. --- Evaluación Segura de Expresiones J desde la Web -----------------------
eval_j_expr =: 3 : 0
  expr =. y
  if. 0 = # deb expr do.
    enc_pjson_ ('status' kv 'error') , ('result' kv 'Expresión vacía') return.
  end.
  if. (+./ '2!:' E. expr) +. (+./ '1!:55' E. expr) +. (+./ 'exit' E. expr) do.
    enc_pjson_ ('status' kv 'error') , ('result' kv 'Operación de sistema restringida en el sandbox interactivo.') return.
  end.
  try.
    res =. ". expr
    sh  =. ": $ res
    if. 0 = # $ res do. sh =. 'escalar (atom)' end.
    fmt =. ": res
    if. 1 < #$ fmt do.
      out_str =. ; (<"1 fmt) , each LF
    else.
      out_str =. , fmt
    end.
    enc_pjson_ ('status' kv 'ok') , ('expr' kv expr) , ('shape' kv sh) , ('result' kv out_str)
  catch.
    err =. 13!:12 ''
    enc_pjson_ ('status' kv 'error') , ('expr' kv expr) , ('result' kv err)
  end.
)

NB. --- Decodificador URL y Parser de Parámetros HTTP -------------------------
HEX_CHARS =: '0123456789ABCDEF'
url_decode =: 3 : 0
  s =. y rplc '+';' '
  out =. ''
  i =. 0
  n =. # s
  while. i < n do.
    c =. i { s
    if. (c = '%') *. ((i + 2) < n) do.
      h1 =. HEX_CHARS i. toupper (i + 1) { s
      h2 =. HEX_CHARS i. toupper (i + 2) { s
      if. (h1 < 16) *. (h2 < 16) do.
        out =. out , ((16 * h1) + h2) { a.
        i =. i + 3
      else.
        out =. out , c
        i =. i + 1
      end.
    else.
      out =. out , c
      i =. i + 1
    end.
  end.
  out
)

get_param =: 4 : 0
  k =. , x
  body =. , y
  if. 0 = #body do. '' return. end.
  pairs =. <;._1 '&' , body
  for_p. pairs do.
    str =. > p
    eq =. str i. '='
    if. eq < #str do.
      key =. eq {. str
      if. key -: k do.
        url_decode (>:eq) }. str return.
      end.
    end.
  end.
  ''
)

num_param =: 4 : 0
  s =. x get_param y
  if. 0 = #s do. 0 return. end.
  s =. s rplc '-';'_'
  {. (". s) , 0
)

handle_control =: 3 : 0
  body =. y
  act =. 'action' get_param body
  select. act
  case. 'toggle_sensor' do.
    idx =. 0 >. 7 <. <. 'idx' num_param body
    val =. 0 ~: 'val' num_param body
    SENS_ENABLED =: val idx } SENS_ENABLED
  case. 'set_threshold' do.
    idx =. 0 >. 7 <. <. 'idx' num_param body
    val =. 'val' num_param body
    THRESHOLDS =: val idx } THRESHOLDS
  case. 'toggle_actuator' do.
    id  =. 'id' get_param body
    val =. 0 ~: 'val' num_param body
    if. id -: 'led1'      do. ACT_LED_1     =: val end.
    if. id -: 'led2'      do. ACT_LED_2     =: val end.
    if. id -: 'led3'      do. ACT_LED_3     =: val end.
    if. id -: 'alarm'     do. ACT_ALARM     =: val end.
    if. id -: 'haptic'    do. ACT_HAPTIC    =: val end.
    if. id -: 'auto_cool' do. ACT_AUTO_COOL =: val end.
  case. 'set_synth' do.
    SYNTH_MODE   =: 0 >. 2 <. <. 'mode' num_param body
    SYNTH_GAIN   =: 0.1 >. 3.0 <. 'gain' num_param body
    SYNTH_OFFSET =: 0 >. 100 <. 'offset' num_param body
  case. 'set_poll' do.
    POLL_MS =: 250 >. 5000 <. <. 'poll_ms' num_param body
  case. 'inject_spike' do.
    cpu_hist   =: cpu_hist push_hist 96.5
    synth_hist =: synth_hist push_hist 98.2
  case. 'reset_history' do.
    init_sensors ''
  end.
  sample_all_sensors ''
)

handle_client_sensors =: 3 : 0
  body =. y
  CLIENT_ACTIVE    =: 1
  CLIENT_ACCEL_X   =: 'ax' num_param body
  CLIENT_ACCEL_Y   =: 'ay' num_param body
  CLIENT_ACCEL_Z   =: 'az' num_param body
  CLIENT_ACCEL_MAG =: round2 %: +/ *: CLIENT_ACCEL_X , CLIENT_ACCEL_Y , CLIENT_ACCEL_Z
  CLIENT_GYRO_A    =: 'ga' num_param body
  CLIENT_GYRO_B    =: 'gb' num_param body
  CLIENT_GYRO_G    =: 'gg' num_param body
  CLIENT_COMPASS   =: 'cmp' num_param body
  CLIENT_TOUCH_PRS =: 'prs' num_param body
  CLIENT_TOUCH_PTS =: <. 'pts' num_param body
  CLIENT_BAT_LVL   =: 'bat' num_param body
  CLIENT_BAT_CHG   =: 0 ~: 'chg' num_param body
  CLIENT_MIC_DB    =: 'mic' num_param body
  CLIENT_LIGHT_LUX =: 'lux' num_param body
  CLIENT_NET_RTT   =: 'rtt' num_param body
  CLIENT_PTR_SPEED =: 'ptr' num_param body
  enc_pjson_ ('status' kv 'ok') , ('accel_mag' kv CLIENT_ACCEL_MAG) , ('mic_db' kv CLIENT_MIC_DB)
)

init_sensors ''
