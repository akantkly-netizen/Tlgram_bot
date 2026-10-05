(() => {
  const canvas = document.querySelector("#game-canvas");
  const frame = document.querySelector("#game-frame");
  if (!(canvas instanceof HTMLCanvasElement) || !(frame instanceof HTMLElement)) return;

  const ctx = canvas.getContext("2d", { alpha: false });
  if (!ctx) return;

  const ui = {
    score: document.querySelector("#score-value"),
    best: document.querySelector("#best-value"),
    lives: document.querySelector("#lives-value"),
    shards: document.querySelector("#shards-value"),
    time: document.querySelector("#time-value"),
    finalScore: document.querySelector("#final-score-value"),
    intro: document.querySelector("#intro-screen"),
    pause: document.querySelector("#pause-screen"),
    gameOver: document.querySelector("#game-over-screen"),
    pauseButton: document.querySelector("#pause-button"),
    soundButton: document.querySelector("#sound-toggle"),
    startButton: document.querySelector("#start-button"),
    resumeButton: document.querySelector("#resume-button"),
    restartButton: document.querySelector("#restart-button"),
    lifePips: [...document.querySelectorAll(".life-pips i")],
  };

  const faNumber = new Intl.NumberFormat("fa-IR", {
    maximumFractionDigits: 0,
    useGrouping: false,
  });
  const state = {
    status: "ready",
    score: 0,
    best: readBest(),
    lives: 3,
    shards: 0,
    elapsed: 0,
    survivalTick: 0,
    hazardTick: 0,
    shardTick: 0,
    ship: { x: 0, y: 0, targetX: 0, targetY: 0, angle: -Math.PI / 2 },
    hazards: [],
    crystals: [],
    particles: [],
    stars: [],
    keys: new Set(),
    pressedNudges: new Set(),
    pointerActive: false,
    pointerSeen: false,
    pointerX: 0,
    pointerY: 0,
    invulnerable: 0,
    hitFlash: 0,
    soundOn: true,
    audio: null,
  };

  let width = 0;
  let height = 0;
  let dpr = 1;
  let lastFrame = performance.now();

  function readBest() {
    try {
      return Math.max(0, Number(localStorage.getItem("madar-akhar-record-v1")) || 0);
    } catch {
      return 0;
    }
  }

  function saveBest() {
    try {
      localStorage.setItem("madar-akhar-record-v1", String(state.best));
    } catch {
      // The current session remains playable when browser storage is unavailable.
    }
  }

  function formatScore(value, digits = 5) {
    return faNumber.format(Math.max(0, Math.floor(value))).padStart(digits, "۰");
  }

  function setHidden(element, hidden) {
    if (element) element.hidden = hidden;
  }

  function updateHud() {
    if (ui.score) ui.score.textContent = formatScore(state.score);
    if (ui.best) ui.best.textContent = formatScore(state.best);
    if (ui.lives) ui.lives.textContent = faNumber.format(state.lives);
    if (ui.shards) ui.shards.textContent = faNumber.format(state.shards);
    if (ui.time) {
      const totalSeconds = Math.floor(state.elapsed);
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      ui.time.textContent = `${faNumber.format(minutes).padStart(2, "۰")}:${faNumber.format(seconds).padStart(2, "۰")}`;
    }
    if (ui.finalScore) ui.finalScore.textContent = formatScore(state.score);
    ui.lifePips.forEach((pip, index) => pip.classList.toggle("is-empty", index >= state.lives));
    if (ui.pauseButton instanceof HTMLButtonElement) {
      ui.pauseButton.hidden = state.status !== "playing" && state.status !== "paused";
      ui.pauseButton.disabled = false;
      ui.pauseButton.setAttribute("aria-label", state.status === "paused" ? "ادامهٔ بازی" : "مکث بازی");
    }
  }

  function showStatus(status) {
    state.status = status;
    setHidden(ui.intro, status !== "ready");
    setHidden(ui.pause, status !== "paused");
    setHidden(ui.gameOver, status !== "gameover");
    updateHud();
  }

  function resetRun() {
    state.score = 0;
    state.lives = 3;
    state.shards = 0;
    state.elapsed = 0;
    state.survivalTick = 0;
    state.hazardTick = 0;
    state.shardTick = 0;
    state.hazards.length = 0;
    state.crystals.length = 0;
    state.particles.length = 0;
    state.invulnerable = 0;
    state.hitFlash = 0;
    state.ship.x = width * 0.5;
    state.ship.y = height * 0.73;
    state.ship.targetX = state.ship.x;
    state.ship.targetY = state.ship.y;
    state.ship.angle = -Math.PI / 2;
    updateHud();
  }

  function beginRun() {
    resetRun();
    showStatus("playing");
    unlockAudio();
  }

  function pauseRun() {
    if (state.status === "playing") showStatus("paused");
  }

  function resumeRun() {
    if (state.status === "paused") {
      showStatus("playing");
      unlockAudio();
    }
  }

  function endRun() {
    if (state.status !== "playing") return;
    state.best = Math.max(state.best, state.score);
    saveBest();
    showStatus("gameover");
  }

  function unlockAudio() {
    if (!state.soundOn || state.audio) return;
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (AudioContextClass) state.audio = new AudioContextClass();
    } catch {
      state.audio = null;
    }
  }

  function playTone(frequency, duration, type = "sine", volume = 0.035) {
    if (!state.soundOn || !state.audio) return;
    try {
      if (state.audio.state === "suspended") void state.audio.resume();
      const oscillator = state.audio.createOscillator();
      const gain = state.audio.createGain();
      oscillator.type = type;
      oscillator.frequency.setValueAtTime(frequency, state.audio.currentTime);
      gain.gain.setValueAtTime(volume, state.audio.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, state.audio.currentTime + duration);
      oscillator.connect(gain);
      gain.connect(state.audio.destination);
      oscillator.start();
      oscillator.stop(state.audio.currentTime + duration);
    } catch {
      // Audio is decorative and never blocks the game.
    }
  }

  function resizeCanvas() {
    const bounds = canvas.getBoundingClientRect();
    width = Math.max(1, bounds.width);
    height = Math.max(1, bounds.height);
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    state.ship.x = clamp(state.ship.x || width * 0.5, 24, width - 24);
    state.ship.y = clamp(state.ship.y || height * 0.73, 24, height - 24);
    state.ship.targetX = state.ship.x;
    state.ship.targetY = state.ship.y;
    state.stars = Array.from({ length: Math.max(38, Math.round((width * height) / 7600)) }, () => ({
      x: Math.random() * width,
      y: Math.random() * height,
      radius: Math.random() * 1.2 + 0.25,
      alpha: Math.random() * 0.48 + 0.12,
      drift: Math.random() * 10 + 5,
    }));
  }

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function moveTargetFromPointer(event) {
    const bounds = frame.getBoundingClientRect();
    state.pointerSeen = true;
    state.pointerX = clamp(event.clientX - bounds.left, 20, bounds.width - 20);
    state.pointerY = clamp(event.clientY - bounds.top, 20, bounds.height - 20);
  }

  function directionFromInput() {
    let x = 0;
    let y = 0;
    if (state.keys.has("arrowleft") || state.keys.has("a") || state.pressedNudges.has("left")) x -= 1;
    if (state.keys.has("arrowright") || state.keys.has("d") || state.pressedNudges.has("right")) x += 1;
    if (state.keys.has("arrowup") || state.keys.has("w") || state.pressedNudges.has("up")) y -= 1;
    if (state.keys.has("arrowdown") || state.keys.has("s") || state.pressedNudges.has("down")) y += 1;
    return { x, y };
  }

  function createHazard() {
    const radius = 12 + Math.random() * 16;
    const sides = 7 + Math.floor(Math.random() * 4);
    const points = Array.from({ length: sides }, (_, index) => {
      const angle = (index / sides) * Math.PI * 2;
      return { angle, radius: radius * (0.74 + Math.random() * 0.42) };
    });
    state.hazards.push({
      x: Math.random() * Math.max(1, width - radius * 2) + radius,
      y: -radius - 12,
      radius,
      speed: 92 + Math.min(state.elapsed * 2, 105) + Math.random() * 46,
      drift: (Math.random() - 0.5) * 32,
      rotation: Math.random() * Math.PI * 2,
      spin: (Math.random() - 0.5) * 1.4,
      points,
      color: Math.random() > 0.6 ? "#a88768" : "#718485",
    });
  }

  function createCrystal() {
    state.crystals.push({
      x: 24 + Math.random() * Math.max(1, width - 48),
      y: -20,
      speed: 76 + Math.min(state.elapsed * 0.8, 45) + Math.random() * 20,
      phase: Math.random() * Math.PI * 2,
      radius: 10,
    });
  }

  function burst(x, y, color, count = 10) {
    for (let i = 0; i < count; i += 1) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 24 + Math.random() * 110;
      const life = 0.35 + Math.random() * 0.5;
      state.particles.push({
        x,
        y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        radius: 1.2 + Math.random() * 2.1,
        life,
        maxLife: life,
        color,
      });
    }
  }

  function update(dt) {
    state.elapsed += dt;
    state.survivalTick += dt;
    state.hazardTick += dt;
    state.shardTick += dt;
    state.invulnerable = Math.max(0, state.invulnerable - dt);
    state.hitFlash = Math.max(0, state.hitFlash - dt);

    if (state.survivalTick >= 0.24) {
      state.score += Math.floor(state.survivalTick * 4);
      state.survivalTick %= 0.24;
    }

    const hazardInterval = Math.max(0.34, 0.94 - state.elapsed * 0.009);
    if (state.hazardTick >= hazardInterval) {
      state.hazardTick %= hazardInterval;
      createHazard();
    }
    const crystalInterval = Math.max(1.1, 2.05 - state.elapsed * 0.006);
    if (state.shardTick >= crystalInterval) {
      state.shardTick %= crystalInterval;
      createCrystal();
    }

    const direction = directionFromInput();
    if (direction.x || direction.y) {
      const magnitude = Math.hypot(direction.x, direction.y) || 1;
      const velocity = 264;
      state.ship.targetX = clamp(state.ship.x + (direction.x / magnitude) * velocity * dt, 20, width - 20);
      state.ship.targetY = clamp(state.ship.y + (direction.y / magnitude) * velocity * dt, 20, height - 20);
    } else if (state.pointerSeen) {
      state.ship.targetX = clamp(state.pointerX, 20, width - 20);
      state.ship.targetY = clamp(state.pointerY, 20, height - 20);
    }

    const oldX = state.ship.x;
    const oldY = state.ship.y;
    const follow = 1 - Math.exp(-dt * (state.pointerSeen && !direction.x && !direction.y ? 11 : 8));
    state.ship.x += (state.ship.targetX - state.ship.x) * follow;
    state.ship.y += (state.ship.targetY - state.ship.y) * follow;
    const moveX = state.ship.x - oldX;
    const moveY = state.ship.y - oldY;
    if (Math.abs(moveX) + Math.abs(moveY) > 0.05) {
      const desiredAngle = Math.atan2(moveY, moveX);
      let difference = ((desiredAngle - state.ship.angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
      state.ship.angle += difference * Math.min(1, dt * 8);
    } else {
      state.ship.angle += (-Math.PI / 2 - state.ship.angle) * Math.min(1, dt * 2.5);
    }

    for (const hazard of state.hazards) {
      hazard.y += hazard.speed * dt;
      hazard.x += hazard.drift * dt;
      hazard.rotation += hazard.spin * dt;
      if (state.invulnerable <= 0 && distance(hazard.x, hazard.y, state.ship.x, state.ship.y) < hazard.radius + 12) {
        state.lives -= 1;
        state.invulnerable = 1.35;
        state.hitFlash = 0.2;
        burst(state.ship.x, state.ship.y, "#ef927b", 18);
        playTone(130, 0.23, "triangle", 0.055);
        if (state.lives <= 0) endRun();
        updateHud();
        break;
      }
    }
    state.hazards = state.hazards.filter((hazard) => hazard.y < height + hazard.radius + 8);

    for (const crystal of state.crystals) {
      crystal.y += crystal.speed * dt;
      crystal.phase += dt * 3;
      if (distance(crystal.x, crystal.y, state.ship.x, state.ship.y) < crystal.radius + 14) {
        crystal.collected = true;
        state.shards += 1;
        state.score += 85;
        burst(crystal.x, crystal.y, "#e2c879", 12);
        playTone(620 + Math.min(state.shards * 18, 270), 0.16, "sine", 0.04);
      }
    }
    state.crystals = state.crystals.filter((crystal) => !crystal.collected && crystal.y < height + 24);

    for (const particle of state.particles) {
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
      particle.vx *= Math.max(0, 1 - dt * 1.7);
      particle.vy *= Math.max(0, 1 - dt * 1.7);
      particle.life -= dt;
    }
    state.particles = state.particles.filter((particle) => particle.life > 0);
    state.stars.forEach((star) => {
      star.y += star.drift * dt;
      if (star.y > height) {
        star.y = 0;
        star.x = Math.random() * width;
      }
    });

    updateHud();
  }

  function distance(x1, y1, x2, y2) {
    return Math.hypot(x1 - x2, y1 - y2);
  }

  function drawBackground(time) {
    ctx.fillStyle = "#0b1421";
    ctx.fillRect(0, 0, width, height);
    const glow = ctx.createRadialGradient(width * 0.55, height * 0.55, 0, width * 0.55, height * 0.55, Math.max(width, height) * 0.68);
    glow.addColorStop(0, "rgba(43, 82, 78, 0.24)");
    glow.addColorStop(0.48, "rgba(22, 48, 57, 0.13)");
    glow.addColorStop(1, "rgba(8, 13, 24, 0)");
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, width, height);

    ctx.save();
    for (const star of state.stars) {
      const shimmer = 0.75 + Math.sin(time * 1.4 + star.x) * 0.25;
      ctx.globalAlpha = star.alpha * shimmer;
      ctx.fillStyle = "#d9e7d8";
      ctx.beginPath();
      ctx.arc(star.x, star.y, star.radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    ctx.save();
    ctx.strokeStyle = "rgba(162, 240, 197, 0.045)";
    ctx.lineWidth = 1;
    const gridSize = 50;
    const offset = (time * 12) % gridSize;
    for (let y = -gridSize + offset; y < height; y += gridSize) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawHazard(hazard) {
    ctx.save();
    ctx.translate(hazard.x, hazard.y);
    ctx.rotate(hazard.rotation);
    ctx.shadowColor = "rgba(226, 200, 121, .12)";
    ctx.shadowBlur = 14;
    ctx.fillStyle = hazard.color;
    ctx.strokeStyle = "rgba(232, 207, 164, .52)";
    ctx.lineWidth = 1.15;
    ctx.beginPath();
    hazard.points.forEach((point, index) => {
      const x = Math.cos(point.angle) * point.radius;
      const y = Math.sin(point.angle) * point.radius;
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.strokeStyle = "rgba(34, 47, 51, .7)";
    ctx.beginPath();
    ctx.moveTo(-hazard.radius * 0.28, -hazard.radius * 0.12);
    ctx.lineTo(hazard.radius * 0.2, hazard.radius * 0.18);
    ctx.stroke();
    ctx.restore();
  }

  function drawCrystal(crystal, time) {
    const pulse = 1 + Math.sin(crystal.phase + time) * 0.12;
    const radius = crystal.radius * pulse;
    ctx.save();
    ctx.translate(crystal.x, crystal.y);
    ctx.rotate(Math.sin(crystal.phase) * 0.22);
    ctx.shadowColor = "rgba(226, 200, 121, .8)";
    ctx.shadowBlur = 18;
    ctx.fillStyle = "rgba(226, 200, 121, .14)";
    ctx.strokeStyle = "#efd997";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(0, -radius);
    ctx.lineTo(radius * 0.76, -radius * 0.12);
    ctx.lineTo(radius * 0.48, radius);
    ctx.lineTo(-radius * 0.54, radius * 0.74);
    ctx.lineTo(-radius * 0.84, -radius * 0.15);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.strokeStyle = "rgba(255, 244, 201, .76)";
    ctx.beginPath();
    ctx.moveTo(0, -radius * 0.72);
    ctx.lineTo(0, radius * 0.55);
    ctx.stroke();
    ctx.restore();
  }

  function drawShip(time) {
    if (state.invulnerable > 0 && Math.floor(time * 16) % 2 === 0) return;
    ctx.save();
    ctx.translate(state.ship.x, state.ship.y);
    ctx.rotate(state.ship.angle + Math.PI / 2);
    const flameLength = 9 + Math.sin(time * 26) * 3;
    ctx.shadowColor = "rgba(162, 240, 197, .75)";
    ctx.shadowBlur = 20;
    ctx.fillStyle = "rgba(226, 200, 121, .82)";
    ctx.beginPath();
    ctx.moveTo(-4, 11);
    ctx.lineTo(0, flameLength + 13);
    ctx.lineTo(4, 11);
    ctx.closePath();
    ctx.fill();
    ctx.shadowColor = "rgba(162, 240, 197, .9)";
    ctx.shadowBlur = 18;
    ctx.fillStyle = "#a2f0c5";
    ctx.strokeStyle = "#e4ffeb";
    ctx.lineWidth = 1.1;
    ctx.beginPath();
    ctx.moveTo(0, -16);
    ctx.lineTo(11, 12);
    ctx.lineTo(0, 7);
    ctx.lineTo(-11, 12);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.fillStyle = "#263d3b";
    ctx.beginPath();
    ctx.ellipse(0, -3, 3, 5.2, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function drawParticles() {
    for (const particle of state.particles) {
      ctx.globalAlpha = Math.max(0, particle.life / particle.maxLife);
      ctx.fillStyle = particle.color;
      ctx.beginPath();
      ctx.arc(particle.x, particle.y, particle.radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function render(now) {
    const time = now / 1000;
    drawBackground(time);
    for (const crystal of state.crystals) drawCrystal(crystal, time);
    for (const hazard of state.hazards) drawHazard(hazard);
    drawParticles();
    if (state.status === "playing" || state.status === "paused") drawShip(time);

    if (state.hitFlash > 0) {
      ctx.fillStyle = `rgba(239, 146, 123, ${state.hitFlash * 0.28})`;
      ctx.fillRect(0, 0, width, height);
    }

    if (state.status === "ready") {
      ctx.save();
      ctx.globalAlpha = 0.58;
      drawShip(time);
      ctx.restore();
    }
  }

  function animationFrame(now) {
    const dt = Math.min((now - lastFrame) / 1000, 0.04);
    lastFrame = now;
    if (state.status === "playing") update(dt);
    render(now);
    window.requestAnimationFrame(animationFrame);
  }

  ui.startButton?.addEventListener("click", beginRun);
  ui.restartButton?.addEventListener("click", beginRun);
  ui.resumeButton?.addEventListener("click", resumeRun);
  ui.pauseButton?.addEventListener("click", () => {
    if (state.status === "paused") resumeRun();
    else pauseRun();
  });

  ui.soundButton?.addEventListener("click", () => {
    state.soundOn = !state.soundOn;
    if (ui.soundButton instanceof HTMLButtonElement) {
      ui.soundButton.setAttribute("aria-pressed", String(state.soundOn));
      ui.soundButton.setAttribute("aria-label", state.soundOn ? "خاموش کردن صدا" : "روشن کردن صدا");
    }
    if (state.soundOn) {
      unlockAudio();
      playTone(520, 0.11, "sine", 0.025);
    }
  });

  frame.addEventListener("pointermove", (event) => {
    if (event.target instanceof Element && event.target.closest(".nudge-pad")) return;
    moveTargetFromPointer(event);
  });
  frame.addEventListener("pointerdown", (event) => {
    if (event.target instanceof Element && event.target.closest(".nudge-pad")) return;
    state.pointerActive = true;
    moveTargetFromPointer(event);
  });
  frame.addEventListener("pointerup", () => {
    state.pointerActive = false;
  });
  frame.addEventListener("pointercancel", () => {
    state.pointerActive = false;
  });
  frame.addEventListener("pointerleave", () => {
    state.pointerActive = false;
  });

  document.querySelectorAll("[data-nudge]").forEach((button) => {
    const direction = button.getAttribute("data-nudge");
    if (!direction) return;
    const press = (event) => {
      event.preventDefault();
      state.pressedNudges.add(direction);
      if (typeof button.setPointerCapture === "function" && event.pointerId !== undefined) {
        try {
          button.setPointerCapture(event.pointerId);
        } catch {
          // The touch direction remains available if capture is unsupported.
        }
      }
    };
    const release = () => state.pressedNudges.delete(direction);
    button.addEventListener("pointerdown", press);
    button.addEventListener("pointerup", release);
    button.addEventListener("pointercancel", release);
    button.addEventListener("lostpointercapture", release);
    button.addEventListener("contextmenu", (event) => event.preventDefault());
  });

  document.addEventListener("keydown", (event) => {
    const key = event.key.toLowerCase();
    if (["arrowleft", "arrowright", "arrowup", "arrowdown", " "].includes(key)) event.preventDefault();
    if (["arrowleft", "arrowright", "arrowup", "arrowdown", "w", "a", "s", "d"].includes(key)) {
      state.keys.add(key);
    }
    if (key === " " || key === "escape") {
      if (state.status === "playing") pauseRun();
      else if (state.status === "paused") resumeRun();
    }
  });
  document.addEventListener("keyup", (event) => state.keys.delete(event.key.toLowerCase()));
  window.addEventListener("blur", () => {
    state.keys.clear();
    state.pressedNudges.clear();
  });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) pauseRun();
  });

  const resizeObserver = new ResizeObserver(resizeCanvas);
  resizeObserver.observe(frame);
  resizeCanvas();
  state.ship.x = width * 0.5;
  state.ship.y = height * 0.73;
  state.ship.targetX = state.ship.x;
  state.ship.targetY = state.ship.y;
  showStatus("ready");
  window.requestAnimationFrame(animationFrame);
})();
