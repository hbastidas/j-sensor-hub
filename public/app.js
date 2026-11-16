// ============================================================================
// J Sensor Hub — Controlador Web y Puente de Hardware para Google Pixel (droid)
// ============================================================================

let isPaused = false;
let pollMs = 1000;
let pollTimer = null;
let audioCtx = null;
let micAnalyser = null;
let wakeLockSentinel = null;

// Estado local de sensores físicos del Google Pixel enviados al motor J
const clientSensors = {
  ax: 0.0,
  ay: 0.0,
  az: 9.81,
  ga: 0.0,
  gb: 0.0,
  gg: 0.0,
  cmp: 0.0,
  prs: 0.0,
  pts: 0,
  bat: 100,
  chg: 1,
  mic: 30.0,
  lux: 250,
  rtt: 20,
  ptr: 0.0
};

// Captura táctil de la pantalla OLED del Google Pixel (presión + puntos multi-touch + velocidad)
let lastPtrX = 0, lastPtrY = 0, lastPtrT = performance.now();
window.addEventListener('pointermove', (e) => {
  const now = performance.now();
  const dt = Math.max(16, now - lastPtrT);
  const dx = e.clientX - lastPtrX;
  const dy = e.clientY - lastPtrY;
  clientSensors.ptr = Math.min(999, Math.round((Math.hypot(dx, dy) / dt) * 100));
  if (typeof e.pressure === 'number' && e.pressure > 0) {
    clientSensors.prs = Number(e.pressure.toFixed(2));
  }
  lastPtrX = e.clientX;
  lastPtrY = e.clientY;
  lastPtrT = now;
});

window.addEventListener('touchstart', (e) => {
  clientSensors.pts = e.touches ? e.touches.length : 1;
  if (e.touches && e.touches[0] && typeof e.touches[0].force === 'number') {
    clientSensors.prs = Number(e.touches[0].force.toFixed(2));
  }
}, { passive: true });

window.addEventListener('touchend', (e) => {
  clientSensors.pts = e.touches ? e.touches.length : 0;
  if (clientSensors.pts === 0) clientSensors.prs = 0;
}, { passive: true });

// Inicializar sensores pasivos (Batería del Pixel y Red)
async function initBrowserPassiveSensors() {
  if ('getBattery' in navigator) {
    try {
      const bat = await navigator.getBattery();
      const updateBat = () => {
        clientSensors.bat = Math.round(bat.level * 100);
        clientSensors.chg = bat.charging ? 1 : 0;
      };
      updateBat();
      bat.addEventListener('levelchange', updateBat);
      bat.addEventListener('chargingchange', updateBat);
    } catch (_) {}
  }
  if (navigator.connection && typeof navigator.connection.rtt === 'number') {
    clientSensors.rtt = navigator.connection.rtt || 20;
  }
}

// Conectar sensores físicos del Google Pixel (IMU 6-DOF, Brújula, Luz, Micrófono)
async function startPhysicalHardwareSensors() {
  const btn = document.getElementById('btn-start-hw');
  try {
    if (typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') {
      await DeviceMotionEvent.requestPermission();
    }
    window.addEventListener('devicemotion', (e) => {
      const acc = e.accelerationIncludingGravity || e.acceleration;
      if (acc && acc.x !== null) {
        clientSensors.ax = Number((acc.x || 0).toFixed(2));
        clientSensors.ay = Number((acc.y || 0).toFixed(2));
        clientSensors.az = Number((acc.z || 0).toFixed(2));
        syncImuSliders();
      }
    });

    window.addEventListener('deviceorientation', (e) => {
      if (e.alpha !== null) {
        clientSensors.ga = Number((e.alpha || 0).toFixed(1));
        clientSensors.gb = Number((e.beta || 0).toFixed(1));
        clientSensors.gg = Number((e.gamma || 0).toFixed(1));
        clientSensors.cmp = Number((e.webkitCompassHeading || (360 - e.alpha) % 360 || 0).toFixed(0));
      }
    });

    if ('AmbientLightSensor' in window) {
      try {
        const light = new window.AmbientLightSensor();
        light.addEventListener('reading', () => {
          clientSensors.lux = Math.round(light.illuminance);
          document.getElementById('lbl-lux').textContent = clientSensors.lux;
        });
        light.start();
      } catch (_) {}
    }

    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
        audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
        const src = audioCtx.createMediaStreamSource(stream);
        micAnalyser = audioCtx.createAnalyser();
        micAnalyser.fftSize = 256;
        src.connect(micAnalyser);
      } catch (_) {}
    }

    triggerPixelHaptic([60, 40, 90]);
    btn.textContent = '✅ Sensores Físicos del Pixel Activos → J';
    btn.classList.add('btn-primary');
  } catch (err) {
    console.warn('Aviso al iniciar sensores físicos del Pixel:', err);
  }
}

function sampleMicIfActive() {
  if (!micAnalyser) return;
  const buf = new Uint8Array(micAnalyser.frequencyBinCount);
  micAnalyser.getByteTimeDomainData(buf);
  let sumSq = 0;
  for (let i = 0; i < buf.length; i++) {
    const norm = (buf[i] - 128) / 128;
    sumSq += norm * norm;
  }
  const rms = Math.sqrt(sumSq / buf.length);
  const db = Math.max(20, Math.min(100, Math.round(20 * Math.log10(rms + 1e-4) + 95)));
  clientSensors.mic = db;
  document.getElementById('lbl-mic').textContent = db;
  document.getElementById('sim-mic').value = db;
}

function syncImuSliders() {
  document.getElementById('lbl-ax').textContent = clientSensors.ax;
  document.getElementById('lbl-ay').textContent = clientSensors.ay;
  document.getElementById('lbl-az').textContent = clientSensors.az;
  document.getElementById('sim-ax').value = clientSensors.ax;
  document.getElementById('sim-ay').value = clientSensors.ay;
  document.getElementById('sim-az').value = clientSensors.az;
}

// Motor Háptico del Google Pixel (Vibration API)
function triggerPixelHaptic(pattern = [120, 60, 120]) {
  if ('vibrate' in navigator) {
    try {
      navigator.vibrate(pattern);
    } catch (_) {}
  }
}

// Bloqueo de pantalla encendida en el Pixel (Screen Wake Lock API)
async function toggleWakeLock() {
  const btn = document.getElementById('btn-wakelock');
  if (!('wakeLock' in navigator)) {
    btn.textContent = '⚠️ WakeLock no soportado';
    return;
  }
  try {
    if (wakeLockSentinel) {
      await wakeLockSentinel.release();
      wakeLockSentinel = null;
      btn.textContent = '🔆 Mantener Pantalla Activa';
      btn.classList.remove('btn-primary');
    } else {
      wakeLockSentinel = await navigator.wakeLock.request('screen');
      btn.textContent = '🔆 Pantalla Activa (ON)';
      btn.classList.add('btn-primary');
      wakeLockSentinel.addEventListener('release', () => {
        wakeLockSentinel = null;
        btn.textContent = '🔆 Mantener Pantalla Activa';
        btn.classList.remove('btn-primary');
      });
    }
  } catch (_) {}
}

// Sirena acústica WebAudio + Vibración Háptica cuando se activa una alerta en J
function triggerAlertFeedback() {
  if (document.getElementById('act-haptic').checked) {
    triggerPixelHaptic([90, 50, 90]);
  }
  if (!document.getElementById('act-alarm').checked) return;
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(660, audioCtx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(880, audioCtx.currentTime + 0.12);
    gain.gain.setValueAtTime(0.08, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.15);
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.start();
    osc.stop(audioCtx.currentTime + 0.16);
  } catch (_) {}
}

async function sendControl(paramsObj) {
  const body = new URLSearchParams(paramsObj).toString();
  try {
    const res = await fetch('/api/control', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });
    const data = await res.json();
    if (data && data.status === 'ok') {
      renderDashboard(data);
    }
  } catch (err) {
    console.error('Error en control J:', err);
  }
}

async function pushClientSensors() {
  sampleMicIfActive();
  if (navigator.connection && typeof navigator.connection.rtt === 'number') {
    clientSensors.rtt = navigator.connection.rtt || clientSensors.rtt;
  }
  const body = new URLSearchParams(clientSensors).toString();
  try {
    await fetch('/api/client-sensors', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });
    clientSensors.ptr = Math.max(0, Math.round(clientSensors.ptr * 0.6));
  } catch (_) {}
}

function drawSensorChart(canvasId, historyArr, thresholdVal, colorHex, maxScaleHint = 100) {
  const canvas = document.getElementById(canvasId);
  if (!canvas || !Array.isArray(historyArr) || historyArr.length === 0) return;
  const ctx = canvas.getContext('2d');
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  const vals = historyArr.map(Number);
  const maxVal = Math.max(maxScaleHint, ...vals, thresholdVal * 1.05, 1);
  const minVal = Math.min(0, ...vals);
  const span = Math.max(1e-3, maxVal - minVal);

  ctx.strokeStyle = 'rgba(143, 163, 192, 0.1)';
  ctx.lineWidth = 1;
  for (let i = 1; i <= 3; i++) {
    const y = (h / 4) * i;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }

  if (thresholdVal <= maxVal && thresholdVal >= minVal) {
    const ty = h - ((thresholdVal - minVal) / span) * (h - 14) - 7;
    ctx.save();
    ctx.strokeStyle = 'rgba(239, 68, 68, 0.65)';
    ctx.setLineDash([5, 4]);
    ctx.beginPath();
    ctx.moveTo(0, ty);
    ctx.lineTo(w, ty);
    ctx.stroke();
    ctx.restore();
  }

  const stepX = vals.length > 1 ? w / (vals.length - 1) : w;
  ctx.beginPath();
  vals.forEach((v, idx) => {
    const x = idx * stepX;
    const y = h - ((v - minVal) / span) * (h - 14) - 7;
    if (idx === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });

  ctx.strokeStyle = colorHex;
  ctx.lineWidth = 2.2;
  ctx.stroke();

  ctx.lineTo(w, h);
  ctx.lineTo(0, h);
  ctx.closePath();
  const grad = ctx.createLinearGradient(0, 0, 0, h);
  grad.addColorStop(0, colorHex + '44');
  grad.addColorStop(1, colorHex + '05');
  ctx.fillStyle = grad;
  ctx.fill();
}

function drawSensorBarChart(canvasId, historyArr, thresholdVal, colorHex, maxScaleHint = 100) {
  const canvas = document.getElementById(canvasId);
  if (!canvas || !Array.isArray(historyArr) || historyArr.length === 0) return;
  const ctx = canvas.getContext('2d');
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  const vals = historyArr.map(Number);
  const maxVal = Math.max(maxScaleHint, ...vals, thresholdVal * 1.05, 1);
  const minVal = Math.min(0, ...vals);
  const span = Math.max(1e-3, maxVal - minVal);

  ctx.strokeStyle = 'rgba(143, 163, 192, 0.1)';
  ctx.lineWidth = 1;
  for (let i = 1; i <= 3; i++) {
    const y = (h / 4) * i;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }

  const n = vals.length;
  const padX = 6;
  const usableW = w - padX * 2;
  const slotW = usableW / n;
  const barW = Math.max(4, slotW * 0.68);
  const bottomPad = 4;
  const maxBarH = h - 14;

  vals.forEach((v, idx) => {
    const norm = Math.max(0, (v - minVal) / span);
    const barH = Math.max(3, norm * maxBarH);
    const x = padX + idx * slotW + (slotW - barW) / 2;
    const y = h - bottomPad - barH;
    const isAlert = v > thresholdVal;
    const topColor = isAlert ? '#ef4444' : colorHex;

    const grad = ctx.createLinearGradient(0, y, 0, h - bottomPad);
    grad.addColorStop(0, topColor + 'ee');
    grad.addColorStop(1, topColor + '33');

    ctx.fillStyle = grad;
    ctx.strokeStyle = topColor;
    ctx.lineWidth = 1;

    const radius = Math.min(3, barW / 2, barH / 2);
    ctx.beginPath();
    if (typeof ctx.roundRect === 'function') {
      ctx.roundRect(x, y, barW, barH, [radius, radius, 0, 0]);
    } else {
      ctx.rect(x, y, barW, barH);
    }
    ctx.fill();
    ctx.stroke();
  });

  if (thresholdVal <= maxVal && thresholdVal >= minVal) {
    const ty = h - ((thresholdVal - minVal) / span) * maxBarH - bottomPad;
    ctx.save();
    ctx.strokeStyle = 'rgba(239, 68, 68, 0.75)';
    ctx.lineWidth = 1.5;
    ctx.setLineDash([5, 4]);
    ctx.beginPath();
    ctx.moveTo(0, ty);
    ctx.lineTo(w, ty);
    ctx.stroke();
    ctx.restore();
  }
}

function renderJStats(containerId, sensorObj) {
  const el = document.getElementById(containerId);
  if (!el || !sensorObj) return;
  const cells = [
    { lbl: '+/ % # (Media)', val: sensorObj.mean },
    { lbl: 'σ (StdDev)', val: sensorObj.std },
    { lbl: '<./ (Mín)', val: sensorObj.min },
    { lbl: '>./ (Máx)', val: sensorObj.max },
    { lbl: '%. (Pendiente)', val: sensorObj.slope },
    { lbl: 'Z-Score', val: sensorObj.zscore }
  ];
  el.innerHTML = cells
    .map(
      (c) => `
    <div class="stat-cell">
      <span class="st-lbl">${c.lbl}</span>
      <span class="st-val">${Number(c.val || 0).toFixed(2)}</span>
    </div>`
    )
    .join('');
}

function updateCardState(cardId, sensorObj) {
  const card = document.getElementById(cardId);
  if (!card || !sensorObj) return;
  card.classList.toggle('alert-state', Boolean(sensorObj.alert));
  card.classList.toggle('paused-state', !Boolean(sensorObj.enabled));
}

function renderDashboard(data) {
  const sys = data.system || {};
  const sens = data.sensors || {};
  const acts = data.actuators || {};
  const jmat = data.j_analytics || {};

  const firstLineEngine = (sys.engine || 'J9.7').split('\n')[0].replace('Engine: ', '');
  document.getElementById('j-engine-badge').textContent = firstLineEngine;
  document.getElementById('rtc-clock').textContent = `${sys.rtc_date || ''} ${sys.rtc_time || ''}`.trim();
  document.getElementById('kpi-shape').textContent = Array.isArray(jmat.shape) ? jmat.shape.join(' × ') : '8 × 20';
  document.getElementById('kpi-tick').textContent = sys.tick ?? 0;
  document.getElementById('kpi-uptime').textContent = `${Math.round(sys.uptime_sec || 0)} s`;

  const activeAlerts = Number(jmat.active_alerts || 0);
  document.getElementById('kpi-alerts').textContent = activeAlerts;
  document.getElementById('kpi-alert-box').classList.toggle('alert-active', activeAlerts > 0);
  if (activeAlerts > 0) {
    triggerAlertFeedback();
  }

  document.getElementById('act-led1').classList.toggle('active', Boolean(acts.led1));
  document.getElementById('act-led2').classList.toggle('active', Boolean(acts.led2));
  document.getElementById('act-led3').classList.toggle('active', Boolean(acts.led3));
  document.getElementById('act-auto-cool').checked = Boolean(acts.auto_cool);

  // Inventario de Hardware del Google Pixel VM
  const hwList = document.getElementById('hw-peripherals-list');
  const inputs = Array.isArray(sys.input_devices) ? sys.input_devices.filter(Boolean).join(', ') : 'N/A';
  hwList.innerHTML = `
    <li><span>SoC Google Pixel</span><strong>${sys.soc_topology || 'Tensor G4 (A520/A720/X4)'}</strong></li>
    <li><span>Red Virtio (<code>enp0s14</code>)</span><strong>${sys.net_if || 'up'}</strong></li>
    <li><span>Reloj RTC (<code>/sys/class/rtc/rtc0</code>)</span><strong>${sys.rtc_date} ${sys.rtc_time}</strong></li>
    <li><span>Display / Audio Virtio</span><strong>DRM: ${sys.drm_status || 'connected'} • ${sys.sound_card || 'SoundCard'}</strong></li>
    <li><span>Input Crosvm (<code>/dev/input</code>)</span><strong title="${inputs}">${inputs.slice(0, 44)}${inputs.length > 44 ? '…' : ''}</strong></li>
  `;

  // 0. CPU Google Tensor G4
  if (sens.cpu) {
    document.getElementById('val-cpu').textContent = `${Number(sens.cpu.current).toFixed(1)}%`;
    drawSensorChart('chart-cpu', sens.cpu.history, sens.cpu.threshold, '#33d2f6', 100);
    renderJStats('stats-cpu', sens.cpu);
    updateCardState('card-cpu', sens.cpu);
    if (Array.isArray(sens.cpu.clusters)) {
      const [cLittle, cMid, cPrime] = sens.cpu.clusters;
      document.getElementById('cpu-clusters-pills').innerHTML = `
        <span class="sub-pill">4× A520 (Efic.): <b>${Number(cLittle || 0).toFixed(1)}%</b></span>
        <span class="sub-pill">3× A720 (Perf.): <b>${Number(cMid || 0).toFixed(1)}%</b></span>
        <span class="sub-pill">1× X4 (Prime): <b>${Number(cPrime || 0).toFixed(1)}%</b></span>
      `;
    }
    if (Array.isArray(sens.cpu.cores)) {
      const coreLabels = ['A520', 'A520', 'A520', 'A520', 'A720', 'A720', 'A720', 'X4'];
      document.getElementById('cpu-cores-bars').innerHTML = sens.cpu.cores
        .map(
          (v, i) => `
        <div class="core-item">
          <div style="display:flex;justify-content:space-between"><span>c${i} <small style="color:#8fa3c0">${coreLabels[i] || ''}</small></span><b>${Number(v).toFixed(0)}%</b></div>
          <div class="core-bar-bg"><div class="core-bar-fill" style="width:${Math.min(100, v)}%"></div></div>
        </div>`
        )
        .join('');
    }
  }

  // 1. Memoria + ZRAM
  if (sens.memory) {
    document.getElementById('val-memory').textContent = `${Number(sens.memory.current).toFixed(1)}%`;
    drawSensorChart('chart-memory', sens.memory.history, sens.memory.threshold, '#10b981', 100);
    renderJStats('stats-memory', sens.memory);
    updateCardState('card-memory', sens.memory);
    document.getElementById('mem-details').innerHTML = `
      <span class="sub-pill">RAM VM: <b>${sens.memory.total_mb} MB</b></span>
      <span class="sub-pill">Libre/Disp: <b>${sens.memory.avail_mb} MB</b></span>
      <span class="sub-pill">ZRAM Swap: <b>${Number(sens.memory.swap_pct).toFixed(1)}%</b></span>
      <span class="sub-pill">LoadAvg: <b>${sens.load ? sens.load.current : 0} / ${sens.load ? sens.load.load5 : 0}</b></span>
    `;
  }

  // 2. PSI
  if (sens.psi) {
    document.getElementById('val-psi').textContent = `${Number(sens.psi.current).toFixed(2)}%`;
    drawSensorChart('chart-psi', sens.psi.history, sens.psi.threshold, '#f59e0b', 15);
    renderJStats('stats-psi', sens.psi);
    updateCardState('card-psi', sens.psi);
    document.getElementById('psi-details').innerHTML = `
      <span class="sub-pill">PSI CPU: <b>${sens.psi.current}%</b></span>
      <span class="sub-pill">PSI I/O: <b>${sens.psi.io_avg10}%</b></span>
      <span class="sub-pill">PSI Mem: <b>${sens.psi.mem_avg10}%</b></span>
      <span class="sub-pill">PSI IRQ: <b>${sens.psi.irq_avg10}%</b></span>
    `;
  }

  // 4. Red Virtio enp0s14
  if (sens.net) {
    document.getElementById('val-net').textContent = `${Number(sens.net.current).toFixed(1)} KB/s`;
    drawSensorChart('chart-net', sens.net.history, sens.net.threshold, '#38bdf8', 100);
    renderJStats('stats-net', sens.net);
    updateCardState('card-net', sens.net);
    document.getElementById('net-details').innerHTML = `
      <span class="sub-pill">RX: <b>${sens.net.rx_kbs} KB/s (${sens.net.rx_mb} MB)</b></span>
      <span class="sub-pill">TX: <b>${sens.net.tx_kbs} KB/s (${sens.net.tx_mb} MB)</b></span>
      <span class="sub-pill">Paquetes RX/TX: <b>${sens.net.rx_pkts} / ${sens.net.tx_pkts}</b></span>
    `;
  }

  // 5. Sintético + Disco
  if (sens.synth) {
    document.getElementById('val-synth').textContent = `${Number(sens.synth.current).toFixed(1)}`;
    drawSensorChart('chart-synth', sens.synth.history, sens.synth.threshold, '#8b5cf6', 100);
    renderJStats('stats-synth', sens.synth);
    updateCardState('card-synth', sens.synth);
    const dsk = sens.disk || {};
    document.getElementById('disk-details').innerHTML = `
      <span class="sub-pill">Virtio VDA+ZRAM IOPS: <b>${dsk.current ?? 0} ops/s</b></span>
      <span class="sub-pill">Lectura: <b>${dsk.read_mb ?? 0} MB</b></span>
      <span class="sub-pill">Escritura: <b>${dsk.write_mb ?? 0} MB</b></span>
      <span class="sub-pill">Media Móvil (5): <b>${sens.synth.ma5}</b></span>
    `;
  }

  // 6. Cliente IMU + Touch del Google Pixel
  if (sens.client_imu) {
    document.getElementById('val-imu').textContent = `${Number(sens.client_imu.current).toFixed(2)} m/s²`;
    drawSensorChart('chart-imu', sens.client_imu.history, sens.client_imu.threshold, '#06b6d4', 25);
    renderJStats('stats-imu', sens.client_imu);
    updateCardState('card-imu', sens.client_imu);
    document.getElementById('imu-details').innerHTML = `
      <span class="sub-pill">Gyro (α/β/γ): <b>${sens.client_imu.ga}° / ${sens.client_imu.gb}° / ${sens.client_imu.gg}°</b></span>
      <span class="sub-pill">Brújula: <b>${sens.client_imu.compass}°</b></span>
      <span class="sub-pill">Presión OLED: <b>${sens.client_imu.touch_pressure} (${sens.client_imu.touch_points} pts)</b></span>
    `;
  }

  // 7. Cliente Ambiental del Google Pixel
  if (sens.client_env) {
    document.getElementById('val-env').textContent = `${Number(sens.client_env.current).toFixed(1)} dB`;
    drawSensorBarChart('chart-env', sens.client_env.history, sens.client_env.threshold, '#ec4899', 100);
    renderJStats('stats-env', sens.client_env);
    updateCardState('card-env', sens.client_env);
    document.getElementById('env-details').innerHTML = `
      <span class="sub-pill">Batería Pixel: <b>${sens.client_env.battery_level}% (${sens.client_env.battery_charging ? '⚡ Cargando' : '🔋'})</b></span>
      <span class="sub-pill">Luz: <b>${sens.client_env.light_lux} lux</b></span>
      <span class="sub-pill">Red RTT: <b>${sens.client_env.net_rtt} ms</b></span>
      <span class="sub-pill">Velocidad Touch: <b>${sens.client_env.ptr_speed} px/s</b></span>
    `;
  }
}

async function pollState() {
  if (isPaused) return;
  try {
    await pushClientSensors();
    const res = await fetch('/api/state');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    document.getElementById('conn-dot').className = 'dot online';
    document.getElementById('conn-text').textContent = 'Conectado a J';
    renderDashboard(data);
  } catch (err) {
    document.getElementById('conn-dot').className = 'dot offline';
    document.getElementById('conn-text').textContent = 'Reconectando...';
  }
}

function restartTimer() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = setInterval(pollState, pollMs);
}

async function evaluateJExpression(expr) {
  const outEl = document.getElementById('repl-result');
  const shapeEl = document.getElementById('repl-shape');
  const exprEl = document.getElementById('repl-last-expr');
  try {
    const body = new URLSearchParams({ expr }).toString();
    const res = await fetch('/api/eval', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });
    const data = await res.json();
    exprEl.textContent = data.expr || expr;
    shapeEl.textContent = data.shape || '-';
    outEl.textContent = data.result || '';
    outEl.style.color = data.status === 'ok' ? '#a7f3d0' : '#fca5a5';
  } catch (err) {
    outEl.textContent = 'Error de conexión con el motor J: ' + err.message;
  }
}

window.addEventListener('DOMContentLoaded', () => {
  initBrowserPassiveSensors();

  document.getElementById('poll-interval-select').addEventListener('change', (e) => {
    pollMs = Number(e.target.value) || 1000;
    sendControl({ action: 'set_poll', poll_ms: pollMs });
    restartTimer();
  });

  document.getElementById('btn-pause').addEventListener('click', (e) => {
    isPaused = !isPaused;
    e.target.textContent = isPaused ? '▶ Reanudar' : '⏸ Pausar';
  });

  document.getElementById('btn-spike').addEventListener('click', () => {
    sendControl({ action: 'inject_spike' });
  });

  document.getElementById('btn-reset').addEventListener('click', () => {
    sendControl({ action: 'reset_history' });
  });

  document.getElementById('btn-test-haptic').addEventListener('click', () => {
    triggerPixelHaptic([80, 40, 150, 40, 80]);
  });

  document.getElementById('btn-wakelock').addEventListener('click', toggleWakeLock);

  document.querySelectorAll('.led-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const id = btn.dataset.id;
      const nextVal = btn.classList.contains('active') ? 0 : 1;
      sendControl({ action: 'toggle_actuator', id, val: nextVal });
    });
  });

  document.getElementById('act-auto-cool').addEventListener('change', (e) => {
    sendControl({ action: 'toggle_actuator', id: 'auto_cool', val: e.target.checked ? 1 : 0 });
  });

  const updateSynth = () => {
    const mode = document.getElementById('synth-mode').value;
    const gain = document.getElementById('synth-gain').value;
    const offset = document.getElementById('synth-offset').value;
    document.getElementById('synth-gain-val').textContent = gain;
    document.getElementById('synth-offset-val').textContent = offset;
    sendControl({ action: 'set_synth', mode, gain, offset });
  };
  document.getElementById('synth-mode').addEventListener('change', updateSynth);
  document.getElementById('synth-gain').addEventListener('input', updateSynth);
  document.getElementById('synth-offset').addEventListener('input', updateSynth);

  document.querySelectorAll('.sensor-enable').forEach((chk) => {
    chk.addEventListener('change', () => {
      sendControl({
        action: 'toggle_sensor',
        idx: chk.dataset.idx,
        val: chk.checked ? 1 : 0
      });
    });
  });

  document.querySelectorAll('.threshold-slider').forEach((slider) => {
    slider.addEventListener('input', () => {
      const idx = slider.dataset.idx;
      document.getElementById(`th-lbl-${idx}`).textContent = slider.value;
    });
    slider.addEventListener('change', () => {
      sendControl({
        action: 'set_threshold',
        idx: slider.dataset.idx,
        val: slider.value
      });
    });
  });

  ['ax', 'ay', 'az'].forEach((axis) => {
    const sl = document.getElementById(`sim-${axis}`);
    sl.addEventListener('input', () => {
      clientSensors[axis] = Number(sl.value);
      document.getElementById(`lbl-${axis}`).textContent = sl.value;
    });
  });
  document.getElementById('sim-mic').addEventListener('input', (e) => {
    clientSensors.mic = Number(e.target.value);
    document.getElementById('lbl-mic').textContent = e.target.value;
  });
  document.getElementById('sim-lux').addEventListener('input', (e) => {
    clientSensors.lux = Number(e.target.value);
    document.getElementById('lbl-lux').textContent = e.target.value;
  });

  document.getElementById('btn-start-hw').addEventListener('click', startPhysicalHardwareSensors);

  document.getElementById('j-repl-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const expr = document.getElementById('j-expr-input').value;
    evaluateJExpression(expr);
  });

  document.querySelectorAll('.chip').forEach((chip) => {
    chip.addEventListener('click', () => {
      const expr = chip.dataset.expr;
      document.getElementById('j-expr-input').value = expr;
      evaluateJExpression(expr);
    });
  });

  pollState();
  evaluateJExpression('(+/ % #)"1 sensors_mat');
  restartTimer();
});
