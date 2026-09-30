// SightShift interactive demo.
//
// A small simulation of the Mac app's focus logic running in the browser: where you look is
// your pointer (or, in camera mode, your head), and keyboard focus follows the same rules the
// app uses. A target must be looked at for the full delay, glances are ignored, focus holds
// while you type, typing straight through a turn cancels the move, and looking at the phone
// is ignored.

const MEDIAPIPE = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1";
const FACE_MODEL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
const contains = (r, p) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
const inset = (r, m) => ({ x: r.x + m, y: r.y + m, w: Math.max(0, r.w - 2 * m), h: Math.max(0, r.h - 2 * m) });
const center = (r) => ({ x: r.x + r.w / 2, y: r.y + r.h / 2 });
const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** The 1€ filter: steady when still, quick when moving. */
class OneEuro {
  constructor(minCutoff = 1.2, beta = 0.02) {
    this.minCutoff = minCutoff;
    this.beta = beta;
    this.x = null;
    this.dx = 0;
    this.t = 0;
  }

  static alpha(cutoff, dt) {
    const tau = 1 / (2 * Math.PI * cutoff);
    return 1 / (1 + tau / dt);
  }

  filter(x, t) {
    if (this.x === null || t - this.t > 600) {
      this.x = x;
      this.dx = 0;
      this.t = t;
      return x;
    }
    const dt = Math.max(1, t - this.t) / 1000;
    const dx = (x - this.x) / dt;
    this.dx += OneEuro.alpha(1, dt) * (dx - this.dx);
    this.x += OneEuro.alpha(this.minCutoff + this.beta * Math.abs(this.dx), dt) * (x - this.x);
    this.t = t;
    return this.x;
  }
}

class Demo {
  constructor(root) {
    this.root = root;
    this.q = (selector) => root.querySelector(selector);
    this.targets = [...root.querySelectorAll("[data-target]")].map((el) => ({
      id: el.dataset.target,
      name: el.dataset.name,
      el,
      body: el.querySelector("[data-body]"),
      typed: el.querySelector("[data-typed]"),
      rect: { x: 0, y: 0, w: 0, h: 0 },
    }));
    for (const target of this.targets) target.initial = target.body.innerHTML;
    this.phone = this.q("[data-away]");
    this.phoneRect = { x: 0, y: 0, w: 0, h: 0 };
    this.els = {
      reticle: this.q("[data-reticle]"),
      dwell: this.q("[data-dwell]"),
      beam: this.q("[data-beam]"),
      beamPath: this.q("[data-beam-path]"),
      beamGlow: this.q("[data-beam-glow]"),
      beamGradient: this.q("[data-beam-gradient]"),
      hudGaze: this.q("[data-hud-gaze]"),
      hudFocus: this.q("[data-hud-focus]"),
      hudHold: this.q("[data-hud-hold]"),
      mode: this.q("[data-mode]"),
      log: this.q("[data-log]"),
      hint: this.q("[data-hint]"),
      keyboard: this.q("[data-keyboard]"),
      cam: this.q("[data-cam]"),
      video: this.q("[data-video]"),
      calibDot: this.q("[data-calib-dot]"),
      prompt: this.q("[data-prompt]"),
      delay: document.querySelector("[data-delay]"),
      delayOut: document.querySelector("[data-delay-out]"),
      typingGuard: document.querySelector("[data-typing-guard]"),
      cameraButton: document.querySelector("[data-camera]"),
      cameraNote: document.querySelector("[data-camera-note]"),
      replay: document.querySelector("[data-replay]"),
    };

    this.settings = { delay: 300, waitWhileTyping: true, typingPause: 2000, pointerPause: 1500, burstGap: 800 };
    this.source = "tour";
    this.aim = { x: 0, y: 0 };
    this.gaze = { x: 0, y: 0 };
    this.aimValid = true;
    this.stable = null;
    this.pending = null;
    this.pendingSince = 0;
    this.pendingLastSeen = 0;
    this.focus = null;
    this.move = null;
    this.excursion = null;
    this.keys = [];
    this.lastKey = -Infinity;
    this.lastPointer = -Infinity;
    this.lastLogged = "";
    this.started = performance.now();
    this.visible = true;
    this.running = false;
    this.tourToken = 0;
    this.motion = null;
    this.camera = null;
    this.interacted = false;

    this.layout();
    const start = this.targetById("editor-left");
    this.setFocus(start.id, performance.now(), null, { silent: true });
    this.stable = start.id;
    this.aim = center(start.rect);
    this.gaze = { ...this.aim };

    this.bind();
    this.run();
    if (reducedMotion) {
      this.setSource("pointer");
    } else {
      this.startTour();
    }
  }

  // ---------- Geometry ----------

  layout() {
    const base = this.root.getBoundingClientRect();
    const relative = (el) => {
      const r = el.getBoundingClientRect();
      return { x: r.left - base.left, y: r.top - base.top, w: r.width, h: r.height };
    };
    this.size = { w: base.width, h: base.height };
    for (const target of this.targets) target.rect = relative(target.el);
    this.phoneRect = relative(this.phone);
    this.els.beam.setAttribute("viewBox", `0 0 ${base.width} ${base.height}`);
  }

  targetById(id) {
    return this.targets.find((target) => target.id === id);
  }

  nameOf(id) {
    if (id === "away") return "your phone";
    return this.targetById(id)?.name ?? "—";
  }

  /** What the gaze point is on, with margins so edges and dividers don't flicker. */
  select(point) {
    const current = this.stable && this.stable !== "away" ? this.targetById(this.stable) : null;
    if (current && contains(inset(current.rect, -8), point)) return current.id;
    for (const target of this.targets) {
      const margin = clamp(Math.min(target.rect.w, target.rect.h) * 0.1, 4, 26);
      if (contains(inset(target.rect, margin), point)) return target.id;
    }
    if (contains(inset(this.phoneRect, -12), point)) return "away";
    return null;
  }

  // ---------- Events ----------

  bind() {
    new ResizeObserver(() => this.layout()).observe(this.root);
    document.fonts?.ready.then(() => this.layout());

    new IntersectionObserver((entries) => {
      this.visible = entries[0].isIntersecting;
      if (this.visible) this.run();
    }, { threshold: 0.05 }).observe(this.root);

    const pointerPoint = (event) => {
      const base = this.root.getBoundingClientRect();
      return { x: event.clientX - base.left, y: event.clientY - base.top };
    };

    this.root.addEventListener("pointerenter", (event) => {
      if (event.pointerType === "mouse") this.root.focus({ preventScroll: true });
    });
    this.root.addEventListener("pointermove", (event) => {
      if (this.source === "camera") return;
      if (event.pointerType !== "mouse" && event.buttons === 0) return;
      this.takeControl("pointer");
      this.aim = pointerPoint(event);
      this.aimValid = true;
    });
    this.root.addEventListener("pointerdown", (event) => {
      this.root.focus({ preventScroll: true });
      if (this.source === "camera") return;
      this.takeControl("pointer");
      this.aim = pointerPoint(event);
      this.aimValid = true;
    });
    this.root.addEventListener("pointerleave", (event) => {
      if (event.pointerType !== "mouse") return;
      if (this.source === "pointer") this.aimValid = false;
      if (document.activeElement === this.root) this.root.blur();
      this.scheduleTourResume();
    });
    window.addEventListener("pointermove", () => {
      this.lastPointer = performance.now();
    }, { passive: true });

    this.root.addEventListener("keydown", (event) => this.onKey(event));

    const updateDelay = () => {
      this.settings.delay = Number(this.els.delay.value);
      this.els.delayOut.textContent = `${this.settings.delay} ms`;
      const fill = ((this.settings.delay - Number(this.els.delay.min)) / (Number(this.els.delay.max) - Number(this.els.delay.min))) * 100;
      this.els.delay.style.setProperty("--fill", `${fill}%`);
    };
    this.els.delay.addEventListener("input", updateDelay);
    updateDelay();
    this.els.typingGuard.addEventListener("change", () => {
      this.settings.waitWhileTyping = this.els.typingGuard.checked;
    });
    this.els.cameraButton.addEventListener("click", () => {
      if (this.camera) this.stopCamera();
      else this.startCamera();
    });
    this.els.replay.addEventListener("click", () => {
      if (this.camera) this.stopCamera();
      this.reset();
      this.startTour();
    });
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) this.run();
    });
  }

  onKey(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const now = performance.now();
    const order = this.targets.map((target) => target.id);
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      event.preventDefault();
      if (this.source === "camera") return;
      this.takeControl("keys");
      const from = order.indexOf(this.stable === "away" || !this.stable ? this.focus : this.stable);
      const next = clamp(from + (event.key === "ArrowLeft" ? -1 : 1), 0, order.length - 1);
      this.aim = center(this.targetById(order[next]).rect);
      this.aimValid = true;
      return;
    }
    if (event.key === "ArrowDown" && this.source !== "camera") {
      event.preventDefault();
      this.takeControl("keys");
      this.aim = center(this.phoneRect);
      this.aimValid = true;
      return;
    }
    if (event.key === "ArrowUp" && this.source !== "camera") {
      event.preventDefault();
      this.takeControl("keys");
      this.aim = center(this.targetById(this.focus).rect);
      this.aimValid = true;
      return;
    }
    if (event.key === "Escape") {
      this.root.blur();
      return;
    }
    if (event.key.length === 1 || event.key === "Backspace" || event.key === "Enter") {
      event.preventDefault();
      if (this.source === "tour") this.takeControl("keys");
      this.type(event.key, now);
    }
  }

  /** The visitor takes over from the tour. */
  takeControl(source) {
    if (!this.interacted) {
      this.interacted = true;
      this.els.log.setAttribute("aria-live", "polite");
    }
    clearTimeout(this.resumeTimer);
    if (this.source === "tour") this.stopTour();
    if (this.source !== "camera") this.setSource(source);
  }

  setSource(source) {
    this.source = source;
    this.root.classList.toggle("is-pointer", source === "pointer");
    this.els.mode.textContent = { tour: "Tour", pointer: "Pointer", keys: "Keyboard", camera: "Camera" }[source];
    this.els.hint.style.opacity = this.interacted ? "0" : "1";
  }

  scheduleTourResume() {
    clearTimeout(this.resumeTimer);
    if (this.source === "camera" || reducedMotion) return;
    this.resumeTimer = setTimeout(() => {
      if (this.source !== "camera" && document.activeElement !== this.root) {
        this.reset();
        this.startTour();
      }
    }, 14000);
  }

  // ---------- Typing ----------

  type(key, now, fromTour = false) {
    const target = this.targetById(this.focus);
    if (!target) return;
    if (!fromTour || this.source === "tour") {
      this.keys.push(now);
      this.lastKey = now;
      if (this.keys.length > 60) this.keys.splice(0, this.keys.length - 60);
    }
    this.els.keyboard.classList.add("is-typing");
    clearTimeout(this.keyboardTimer);
    this.keyboardTimer = setTimeout(() => this.els.keyboard.classList.remove("is-typing"), 140);

    const typed = target.typed;
    if (key === "Backspace") {
      typed.textContent = typed.textContent.slice(0, -1);
    } else if (key === "Enter") {
      this.commitLine(target);
    } else {
      typed.textContent = (typed.textContent + key).slice(-48);
    }
  }

  commitLine(target) {
    const text = target.typed.textContent;
    target.typed.textContent = "";
    if (target.id === "docs") {
      if (text.trim()) this.log(`Searched Docs for “${text.trim()}”`, "skip");
      return;
    }
    const typedLine = target.typed.closest(".ln");
    const line = document.createElement("div");
    line.className = "ln";
    if (target.id === "terminal") {
      line.innerHTML = `<span class="prompt">~/code/app ❯</span> `;
      line.append(text);
      typedLine.before(line);
      if (text.trim()) {
        const output = document.createElement("div");
        output.className = text.trim() === "npm test" ? "ln ok" : "ln dim";
        output.textContent = text.trim() === "npm test" ? "✓ 42 tests passed" : "done";
        typedLine.before(output);
      }
    } else {
      line.append(text);
      typedLine.before(line);
    }
    const lines = target.body.querySelectorAll(".ln");
    for (let i = 0; i < lines.length - 7; i += 1) lines[i].remove();
  }

  // ---------- The focus logic ----------

  run() {
    if (this.running) return;
    this.running = true;
    const frame = (now) => {
      if (!this.visible || document.hidden) {
        this.running = false;
        return;
      }
      this.tick(now);
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }

  tick(now) {
    if (this.motion) {
      const t = clamp((now - this.motion.start) / this.motion.duration, 0, 1);
      const k = ease(t);
      this.aim = {
        x: this.motion.from.x + (this.motion.to.x - this.motion.from.x) * k,
        y: this.motion.from.y + (this.motion.to.y - this.motion.from.y) * k,
      };
      if (t >= 1) this.motion = null;
    }
    const follow = this.source === "tour" ? 1 : this.source === "camera" ? 0.5 : 0.35;
    this.gaze.x += (this.aim.x - this.gaze.x) * follow;
    this.gaze.y += (this.aim.y - this.gaze.y) * follow;

    const candidate = this.aimValid ? this.select(this.gaze) : null;
    const transition = this.dwell(candidate, now);
    if (transition) this.onTransition(transition, now);
    const hold = this.decide(now);
    this.render(now, candidate, hold);
  }

  /** A candidate only becomes where you're looking after it has lasted the full delay. */
  dwell(candidate, now) {
    const gap = 250;
    if (candidate === null) {
      if (this.pending && now - this.pendingLastSeen > gap) this.dropPending();
      return null;
    }
    if (candidate === this.stable) {
      // Back where you were: whatever you looked at on the way was a glance.
      this.dropPending();
      if (this.excursion && this.excursion.lasted > 60) {
        this.log(`Glance at ${this.nameOf(this.excursion.target)} ignored · ${Math.round(this.excursion.lasted)} ms`, "skip");
      }
      this.excursion = null;
      return null;
    }
    if (candidate !== this.pending || now - this.pendingLastSeen > gap) {
      this.dropPending();
      this.pending = candidate;
      this.pendingSince = now;
    }
    this.pendingLastSeen = now;
    if (now - this.pendingSince < this.settings.delay) return null;
    const transition = { target: candidate, arrivedAt: this.pendingSince, settledAt: now };
    this.stable = candidate;
    this.pending = null;
    this.excursion = null;
    return transition;
  }

  /** Forgets the target being dwelled on, remembering the longest look of this excursion. */
  dropPending() {
    if (this.pending && this.pending !== "away") {
      const lasted = this.pendingLastSeen - this.pendingSince;
      if (!this.excursion || lasted > this.excursion.lasted) this.excursion = { target: this.pending, lasted };
    }
    this.pending = null;
  }

  onTransition(transition, now) {
    if (transition.target === "away") {
      this.move = null;
      this.log("Looking at your phone · ignored", "warn");
      return;
    }
    if (transition.target === this.focus) {
      this.move = null;
      return;
    }
    this.move = transition;
    this.log(`Looking at ${this.nameOf(transition.target)}`);
  }

  /** Moves focus once a settled gaze change is allowed to happen. Returns what's holding it. */
  decide(now) {
    const move = this.move;
    if (!move) return null;
    if (move.target !== this.stable || move.target === this.focus) {
      this.move = null;
      return null;
    }
    if (this.pending && this.pending !== move.target) return null;

    if (this.settings.waitWhileTyping) {
      const before = this.keys.filter((t) => t <= move.settledAt).pop();
      const after = this.keys.find((t) => t > move.settledAt);
      if (before !== undefined && after !== undefined && after - before < this.settings.burstGap) {
        this.log(`Stayed on ${this.nameOf(this.focus)} · you kept typing while reading ${this.nameOf(move.target)}`, "warn");
        this.move = null;
        return null;
      }
    }
    if (this.source === "camera" && now - this.lastPointer < this.settings.pointerPause) {
      return { kind: "mouse", remaining: this.settings.pointerPause - (now - this.lastPointer) };
    }
    if (this.settings.waitWhileTyping && now - this.lastKey < this.settings.typingPause) {
      return { kind: "typing", remaining: this.settings.typingPause - (now - this.lastKey) };
    }
    this.setFocus(move.target, now, move);
    this.move = null;
    return null;
  }

  setFocus(id, now, move, { silent = false } = {}) {
    this.focus = id;
    for (const target of this.targets) {
      const focused = target.id === id;
      target.el.classList.toggle("is-focused", focused);
      if (focused && !silent) {
        target.el.classList.remove("just-focused");
        void target.el.offsetWidth;
        target.el.classList.add("just-focused");
      }
    }
    if (!silent) {
      const after = move ? ` · ${Math.round(now - move.arrivedAt)} ms after you looked` : "";
      this.log(`Focused ${this.nameOf(id)}${after}`, "ok");
    }
  }

  // ---------- Rendering ----------

  render(now, candidate, hold) {
    const { x, y } = this.gaze;
    this.els.reticle.style.left = `${x}px`;
    this.els.reticle.style.top = `${y}px`;

    const dwelling = this.pending && this.pending !== "away" ? clamp((now - this.pendingSince) / this.settings.delay, 0, 1) : 0;
    this.els.dwell.setAttribute("stroke-dasharray", `${(dwelling * 100).toFixed(1)} 100`);

    const origin = { x: this.size.w / 2, y: this.size.h * 1.12 };
    const dx = x - origin.x;
    const dy = y - origin.y;
    const length = Math.hypot(dx, dy) || 1;
    const nx = -dy / length;
    const ny = dx / length;
    const base = this.size.w * 0.05;
    const tip = Math.max(10, this.size.w * 0.022);
    this.els.beamPath.setAttribute(
      "d",
      `M${origin.x + nx * base},${origin.y + ny * base} L${x + nx * tip},${y + ny * tip} L${x - nx * tip},${y - ny * tip} L${origin.x - nx * base},${origin.y - ny * base}Z`
    );
    this.els.beamGradient.setAttribute("x1", origin.x);
    this.els.beamGradient.setAttribute("y1", origin.y);
    this.els.beamGradient.setAttribute("x2", x);
    this.els.beamGradient.setAttribute("y2", y);
    this.els.beamGlow.setAttribute("cx", x);
    this.els.beamGlow.setAttribute("cy", y);
    this.els.beamGlow.setAttribute("r", Math.max(40, this.size.w * 0.07));
    this.els.beam.style.opacity = this.aimValid ? "1" : "0.25";

    const looking = this.pending ?? this.stable;
    for (const target of this.targets) target.el.classList.toggle("is-gazed", target.id === looking && this.aimValid);
    const away = this.aimValid && (candidate === "away" || looking === "away");
    this.phone.classList.toggle("is-gazed", away);
    this.root.classList.toggle("is-away", away);

    let gazeText = "—";
    if (!this.aimValid) gazeText = "off the desk";
    else if (this.pending === "away" || this.stable === "away" && !this.pending) gazeText = "your phone · ignored";
    else if (this.pending) gazeText = `${this.nameOf(this.pending)} · ${Math.round(dwelling * this.settings.delay)}/${this.settings.delay} ms`;
    else if (this.stable) gazeText = this.nameOf(this.stable);
    this.setText(this.els.hudGaze, gazeText);
    this.setText(this.els.hudFocus, this.nameOf(this.focus));
    const holdText = hold ? `${hold.kind === "typing" ? "you're typing" : "mouse in use"} · ${(hold.remaining / 1000).toFixed(1)} s` : "—";
    this.setText(this.els.hudHold, holdText);
    this.els.hudHold.classList.toggle("hold", Boolean(hold));
  }

  setText(el, text) {
    if (el.textContent !== text) el.textContent = text;
  }

  log(text, kind = "") {
    if (text === this.lastLogged) return;
    this.lastLogged = text;
    const item = document.createElement("li");
    const time = document.createElement("time");
    time.textContent = `+${((performance.now() - this.started) / 1000).toFixed(1)}s`;
    const span = document.createElement("span");
    span.className = kind;
    span.textContent = text;
    item.append(time, span);
    this.els.log.prepend(item);
    while (this.els.log.children.length > 5) this.els.log.lastElementChild.remove();
  }

  reset() {
    this.stopTour();
    for (const target of this.targets) target.body.innerHTML = target.initial;
    for (const target of this.targets) target.typed = target.el.querySelector("[data-typed]");
    this.keys = [];
    this.lastKey = -Infinity;
    this.move = null;
    this.pending = null;
    this.excursion = null;
    this.lastLogged = "";
    this.layout();
    const start = this.targetById("editor-left");
    this.setFocus(start.id, performance.now(), null, { silent: true });
    this.stable = start.id;
    this.aim = center(start.rect);
    this.aimValid = true;
  }

  // ---------- The guided tour ----------

  startTour() {
    this.setSource("tour");
    const token = ++this.tourToken;
    const alive = () => token === this.tourToken && this.source === "tour";
    const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const wait = async (ms) => {
      await sleep(ms);
      while (alive() && (!this.visible || document.hidden)) await sleep(250);
    };
    const point = (id, dx = 0, dy = 0) => {
      const rect = id === "away" ? this.phoneRect : this.targetById(id).rect;
      const c = center(rect);
      return { x: c.x + rect.w * dx, y: c.y + rect.h * dy };
    };
    const lookAt = async (to, duration = 650) => {
      this.aimValid = true;
      this.motion = { from: { ...this.gaze }, to, start: performance.now(), duration };
      await wait(duration);
    };
    const typeText = async (text, every = 75) => {
      for (const char of text) {
        if (!alive()) return;
        this.type(char, performance.now(), true);
        await wait(every + Math.random() * 40);
      }
    };
    const enter = () => alive() && this.type("Enter", performance.now(), true);

    const script = async () => {
      await wait(900);
      while (alive()) {
        await typeText("follow(gaze)");
        if (!alive()) return;
        await wait(700);
        await lookAt(point("terminal", 0.05, 0.08), 700);
        await wait(2600);
        if (!alive()) return;
        await typeText("npm test");
        enter();
        // Look away straight after typing: focus waits for the typing pause.
        await wait(300);
        await lookAt(point("docs", -0.05, 0.05), 650);
        await wait(2800);
        if (!alive()) return;
        await typeText("hysteresis");
        enter();
        await wait(2400);
        // A quick glance is ignored.
        await lookAt(point("editor-right", 0.3, 0), 240);
        await lookAt(point("docs"), 240);
        await wait(1400);
        if (!alive()) return;
        await lookAt(point("away"), 700);
        await wait(1500);
        await lookAt(point("editor-right", 0, 0.1), 700);
        await wait(2700);
        if (!alive()) return;
        // Reading the docs while typing here: focus stays on the editor.
        const reading = typeText("see docs for details", 90);
        await wait(500);
        await lookAt(point("docs", 0, -0.05), 600);
        await reading;
        await wait(2600);
        await lookAt(point("editor-left", 0.08, 0.12), 700);
        await wait(3000);
        if (!alive()) return;
        this.reset();
        this.setSource("tour");
        await wait(1200);
      }
    };
    script();
  }

  stopTour() {
    this.tourToken += 1;
    this.motion = null;
  }

  // ---------- Camera mode ----------

  note(text, state = "") {
    this.els.cameraNote.textContent = text;
    this.els.cameraNote.dataset.state = state;
  }

  prompt(title, body = "") {
    const card = this.els.prompt;
    if (!title) {
      card.classList.remove("is-visible");
      return;
    }
    card.innerHTML = "";
    const strong = document.createElement("strong");
    strong.textContent = title;
    card.append(strong);
    if (body) card.append(body);
    card.classList.add("is-visible");
  }

  async startCamera() {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.note("This browser can't use the camera here. Try a recent Chrome, Edge, Safari or Firefox.", "error");
      return;
    }
    const button = this.els.cameraButton;
    button.disabled = true;
    this.els.replay.disabled = true;
    this.takeControl("pointer");
    let stream;
    try {
      this.note("Asking for your camera…");
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: { ideal: 640 }, height: { ideal: 480 } },
        audio: false,
      });
      this.els.video.srcObject = stream;
      await this.els.video.play();
      this.root.classList.add("is-camera");
      this.prompt("Loading the face tracker…", "It runs right here in your browser.");
      this.note("Loading MediaPipe's face tracker (about 15 MB the first time). Video stays on your device.");
      const vision = await import(`${MEDIAPIPE}/vision_bundle.mjs`);
      const files = await vision.FilesetResolver.forVisionTasks(`${MEDIAPIPE}/wasm`);
      const create = (delegate) => vision.FaceLandmarker.createFromOptions(files, {
        baseOptions: { modelAssetPath: FACE_MODEL, delegate },
        runningMode: "VIDEO",
        numFaces: 1,
        outputFacialTransformationMatrixes: true,
      });
      let landmarker;
      try {
        landmarker = await create("GPU");
      } catch {
        landmarker = await create("CPU");
      }
      this.camera = {
        stream,
        landmarker,
        yaw: new OneEuro(1.0, 0.03),
        pitch: new OneEuro(1.0, 0.03),
        pose: null,
        seenAt: 0,
        lastDetect: 0,
        map: null,
      };
      this.setSource("camera");
      button.textContent = "Stop camera";
      button.disabled = false;
      this.note("Camera on. Everything is processed in this tab and nothing is uploaded.");
      this.cameraLoop();
      await this.calibrate();
    } catch (error) {
      stream?.getTracks().forEach((track) => track.stop());
      this.teardownCamera();
      const denied = error && (error.name === "NotAllowedError" || error.name === "SecurityError");
      this.note(
        denied
          ? "Camera access was blocked. You can still try the demo with your pointer."
          : "The face tracker couldn't start in this browser. The pointer demo still works.",
        "error"
      );
    }
  }

  cameraLoop() {
    const camera = this.camera;
    if (!camera) return;
    const video = this.els.video;
    const now = performance.now();
    if (video.readyState >= 2 && now - camera.lastDetect > 45) {
      camera.lastDetect = now;
      try {
        const result = camera.landmarker.detectForVideo(video, now);
        const matrix = result.facialTransformationMatrixes?.[0]?.data;
        if (matrix) {
          // The face's forward axis: which way the head is turned. Calibration takes care of
          // signs and scale, so the exact axis convention doesn't matter.
          const yaw = (Math.atan2(matrix[8], matrix[10]) * 180) / Math.PI;
          const pitch = (Math.atan2(-matrix[9], Math.hypot(matrix[8], matrix[10])) * 180) / Math.PI;
          camera.pose = { yaw: camera.yaw.filter(yaw, now), pitch: camera.pitch.filter(pitch, now) };
          camera.seenAt = now;
          if (camera.map) {
            const { a, b, yMid, pitchMid, k } = camera.map;
            this.aim = {
              x: clamp(a + b * camera.pose.yaw, 0, this.size.w),
              y: clamp(yMid + k * (camera.pose.pitch - pitchMid), 0, this.size.h),
            };
            this.aimValid = true;
          }
        } else if (now - camera.seenAt > 500) {
          this.aimValid = false;
        }
      } catch {
        // A dropped frame; try the next one.
      }
    }
    camera.raf = requestAnimationFrame(() => this.cameraLoop());
  }

  async calibrate() {
    const camera = this.camera;
    const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const middle = (() => {
      const a = this.targetById("editor-left").rect;
      const b = this.targetById("editor-right").rect;
      return { x: (a.x + b.x + b.w) / 2, y: (a.y + b.y + b.h) / 2 };
    })();
    const steps = [
      { point: center(this.targetById("terminal").rect), title: "Look at the dot on the left screen" },
      { point: middle, title: "Now the middle screen" },
      { point: center(this.targetById("docs").rect), title: "And the right screen" },
      { point: center(this.phoneRect), title: "Last one: glance at the phone" },
    ];
    const results = [];
    this.aimValid = false;
    for (const step of steps) {
      if (this.camera !== camera) return;
      this.els.calibDot.style.left = `${step.point.x}px`;
      this.els.calibDot.style.top = `${step.point.y}px`;
      this.els.calibDot.classList.add("is-visible");
      this.prompt(step.title, "Turn your head toward it naturally.");
      await wait(900);
      const samples = [];
      const started = performance.now();
      while (samples.length < 14 && performance.now() - started < 6000) {
        if (this.camera !== camera) return;
        if (camera.pose && performance.now() - camera.seenAt < 200) samples.push({ ...camera.pose });
        await wait(60);
      }
      if (samples.length < 5) {
        this.els.calibDot.classList.remove("is-visible");
        this.prompt("Can't see your face", "Make sure the camera has a clear view of you, then try again.");
        this.note("Couldn't see your face during calibration.", "error");
        await wait(2600);
        this.stopCamera();
        return;
      }
      const mean = (key) => samples.reduce((sum, s) => sum + s[key], 0) / samples.length;
      results.push({ point: step.point, yaw: mean("yaw"), pitch: mean("pitch") });
    }
    this.els.calibDot.classList.remove("is-visible");

    // Horizontal: least squares through the three screens. Vertical: screens versus phone.
    const screens = results.slice(0, 3);
    const my = screens.reduce((s, r) => s + r.yaw, 0) / 3;
    const mx = screens.reduce((s, r) => s + r.point.x, 0) / 3;
    const cov = screens.reduce((s, r) => s + (r.yaw - my) * (r.point.x - mx), 0);
    const variance = screens.reduce((s, r) => s + (r.yaw - my) ** 2, 0);
    const turnedEnough = variance > 12;
    const b = turnedEnough ? cov / variance : (screens[2].yaw >= screens[0].yaw ? 1 : -1) * this.size.w * 0.018;
    const a = mx - b * my;
    const phone = results[3];
    const pitchMid = screens.reduce((s, r) => s + r.pitch, 0) / 3;
    const yMid = screens.reduce((s, r) => s + r.point.y, 0) / 3;
    const k = Math.abs(phone.pitch - pitchMid) > 3 ? (phone.point.y - yMid) / (phone.pitch - pitchMid) : this.size.h * 0.02;
    camera.map = { a, b, yMid, pitchMid, k };

    this.prompt(
      turnedEnough ? "Calibrated" : "Calibrated, roughly",
      turnedEnough ? "Turn your head to look around, then type." : "Try turning your head a little more toward each screen."
    );
    await wait(2200);
    if (this.camera === camera) this.prompt(null);
  }

  stopCamera() {
    this.teardownCamera();
    this.note("Camera off. You can keep trying the demo with your pointer.");
    this.setSource("pointer");
  }

  teardownCamera() {
    const camera = this.camera;
    this.camera = null;
    if (camera) {
      cancelAnimationFrame(camera.raf);
      camera.stream.getTracks().forEach((track) => track.stop());
      try {
        camera.landmarker.close();
      } catch {
        // Already closed.
      }
    }
    this.els.video.srcObject = null;
    this.root.classList.remove("is-camera");
    this.els.calibDot.classList.remove("is-visible");
    this.prompt(null);
    this.els.cameraButton.textContent = "Use my camera";
    this.els.cameraButton.disabled = false;
    this.els.replay.disabled = false;
    this.aimValid = true;
  }
}

const root = document.querySelector("[data-demo]");
if (root) new Demo(root);
