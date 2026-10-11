/* =============================================================================
   Waddly promo — deterministic motion engine.

   Every visual is a pure function of the timeline time `t`. Nothing here reads
   the wall clock or Math.random(), so a seek to any frame renders identically
   every time (required for frame-accurate rendering).

   The pet's motion constants are ported from the app itself:
     Sources/WaddlyApp/PetAnimationController.swift
     Sources/WaddlyApp/AppModels.swift
   ============================================================================= */

window.W = (function () {
    /* ---------------------------------------------------------------- math */

    const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
    const clamp01 = (v) => clamp(v, 0, 1);
    const lerp = (a, b, u) => a + (b - a) * u;
    const TAU = Math.PI * 2;

    const ease = {
        linear: (u) => u,
        inQuad: (u) => u * u,
        outQuad: (u) => 1 - (1 - u) * (1 - u),
        inOutQuad: (u) => (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2),
        inCubic: (u) => u * u * u,
        outCubic: (u) => 1 - Math.pow(1 - u, 3),
        inOutCubic: (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2),
        inQuart: (u) => u * u * u * u,
        outQuart: (u) => 1 - Math.pow(1 - u, 4),
        inOutQuart: (u) => (u < 0.5 ? 8 * u * u * u * u : 1 - Math.pow(-2 * u + 2, 4) / 2),
        outQuint: (u) => 1 - Math.pow(1 - u, 5),
        inOutQuint: (u) => (u < 0.5 ? 16 * u * u * u * u * u : 1 - Math.pow(-2 * u + 2, 5) / 2),
        outExpo: (u) => (u >= 1 ? 1 : 1 - Math.pow(2, -10 * u)),
        inOutSine: (u) => -(Math.cos(Math.PI * u) - 1) / 2,
        outBack: (u) => {
            const c1 = 1.70158;
            const c3 = c1 + 1;
            return 1 + c3 * Math.pow(u - 1, 3) + c1 * Math.pow(u - 1, 2);
        },
        outElastic: (u) => {
            if (u === 0 || u === 1) return u;
            const c4 = TAU / 3;
            return Math.pow(2, -10 * u) * Math.sin((u * 10 - 0.75) * c4) + 1;
        },
        /* windowed pulse: 0 -> 1 -> 0 */
        pulse: (u) => Math.sin(Math.PI * clamp01(u)),
    };

    /* A keyframe track: [[time, value, easingIntoThisKey], ...]. */
    function track(t, pts, fallbackEase) {
        const first = pts[0];
        if (t <= first[0]) return first[1];
        for (let i = 1; i < pts.length; i += 1) {
            const [t1, v1, e1] = pts[i];
            if (t <= t1) {
                const [t0, v0] = pts[i - 1];
                const u = t1 === t0 ? 1 : (t - t0) / (t1 - t0);
                return lerp(v0, v1, ease[e1 || fallbackEase || "inOutCubic"](clamp01(u)));
            }
        }
        return pts[pts.length - 1][1];
    }

    /* Deterministic value source — used only to precompute static layouts. */
    function rng(seed) {
        let s = (seed >>> 0) || 1;
        return function next() {
            s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
            return s / 4294967296;
        };
    }

    /* ------------------------------------------------------------ pet model */

    /* Ported verbatim from PetAnimationController.swift */
    const CFG = {
        typingFrameInterval: 0.075, // lastInputTime - lastTypingFrameTime >= 0.075
        typingPhaseSeconds: 2.5, // PetPhase.after(elapsed)
        bounceDuration: 0.14,
        bounceKeyTimes: [0, 0.45, 1], // values [0, amplitude, 0]
        idleBreathScale: 1.01,
        idleBreathDuration: 3.2,
        blinkHold: 0.16,
        sleepBreathScale: 1.018,
        sleepBreathDuration: 1.5,
        sleepFrameInterval: 1.5,
        enterDuration: 0.58,
        enterScale: [1, 0.86, 1.12, 0.96, 1],
        enterShiftY: [0, 8, -5, 2, 0],
        enterKeyTimes: [0, 0.2, 0.48, 0.72, 1],
        motionStrong: 10, // TypingMotion.strong.amplitude
        motionWeak: 5, // TypingMotion.weak.amplitude
    };

    const SPRITES = [
        "idle-1",
        "idle-2",
        "typing-1",
        "typing-2",
        "typing-3",
        "typing-4",
        "enter-1",
        "sleep-1",
        "sleep-2",
    ];
    const IDLE = ["idle-1", "idle-2"];
    const TYPING = ["typing-1", "typing-2", "typing-3", "typing-4"];
    const SLEEP = ["sleep-1", "sleep-2"];

    /* Replays the app's keydown handler over a key schedule and returns the
       sprite index that is on screen at each key press. */
    function buildTypingFrames(keyTimes) {
        const out = [];
        let frame = 0;
        let lastFrameTime = -Infinity;
        for (const keyTime of keyTimes) {
            if (lastFrameTime === -Infinity || keyTime - lastFrameTime >= CFG.typingFrameInterval) {
                out.push({ t: keyTime, frame });
                frame += 1;
                lastFrameTime = keyTime;
            }
        }
        return out;
    }

    /* CAKeyframeAnimation(values: [0, amp, 0], keyTimes: [0, 0.45, 1]) with an
       easeOut timing function on the whole animation. */
    function bounceOffset(u) {
        if (u < 0) return 0;
        if (u >= 1) return 0;
        const [k0, k1] = CFG.bounceKeyTimes;
        if (u < k1) return ease.outQuad(clamp01((u - k0) / (k1 - k0)));
        return Math.pow(1 - (u - k1) / (1 - k1), 2);
    }

    /* ------------------------------------------------------------ pet actor */

    function createActor(plan) {
        const typingFrames = buildTypingFrames(plan.keyTimes);
        const planTypingStart = typingFrames.length ? typingFrames[0].t : Infinity;

        function lastKeyBefore(t) {
            let lo = 0;
            let hi = plan.keyTimes.length - 1;
            let found = -Infinity;
            while (lo <= hi) {
                const mid = (lo + hi) >> 1;
                if (plan.keyTimes[mid] <= t) {
                    found = plan.keyTimes[mid];
                    lo = mid + 1;
                } else {
                    hi = mid - 1;
                }
            }
            return found;
        }

        function typingFrameAt(t) {
            let sprite = 0;
            for (const entry of typingFrames) {
                if (entry.t <= t) sprite = entry.frame;
                else break;
            }
            return sprite;
        }

        function inWindow(t, w) {
            return t >= w[0] && t < w[1];
        }

        function pose(t) {
            const out = {
                sprite: "idle-1",
                scale: 1,
                scaleX: 1,
                scaleY: 1,
                offsetX: 0,
                offsetY: 0,
                rotation: 0,
                shadowScale: 1,
                shadowOpacity: 0.7,
                sleeping: false,
                zzz: 0,
            };

            /* --- Enter reaction: the signature beat. ---------------------- */
            const enterU = plan.enterAt === null ? -1 : (t - plan.enterAt) / CFG.enterDuration;
            if (enterU >= 0) {
                const k = CFG.enterKeyTimes;
                const s = track(enterU, [
                    [k[0], CFG.enterScale[0]],
                    [k[1], CFG.enterScale[1]],
                    [k[2], CFG.enterScale[2]],
                    [k[3], CFG.enterScale[3]],
                    [k[4], CFG.enterScale[4]],
                ]);
                const y = track(enterU, [
                    [k[0], CFG.enterShiftY[0]],
                    [k[1], CFG.enterShiftY[1]],
                    [k[2], CFG.enterShiftY[2]],
                    [k[3], CFG.enterShiftY[3]],
                    [k[4], CFG.enterShiftY[4]],
                ]);
                out.sprite = "enter-1";
                out.scale = s;
                out.offsetY = y;
                return out;
            }

            /* --- Sleeping ------------------------------------------------- */
            const sleep = plan.sleepWindow;
            if (sleep && t >= sleep[0] && t < sleep[1]) {
                const since = t - sleep[0];
                out.sleeping = true;
                out.sprite = SLEEP[Math.floor(since / CFG.sleepFrameInterval) % SLEEP.length];
                /* breathe(duration: 1.5, autoreverses) => 3.0s cycle */
                out.scale =
                    1 +
                    (CFG.sleepBreathScale - 1) *
                        (0.5 - 0.5 * Math.cos((TAU * since) / (CFG.sleepBreathDuration * 2)));
                out.zzz = since;
                return out;
            }

            /* --- Typing --------------------------------------------------- */
            const win = plan.typingWindows.find((w) => inWindow(t, w));
            if (win) {
                out.sprite = TYPING[typingFrameAt(t) % TYPING.length];
                const key = lastKeyBefore(t);
                if (key > -Infinity) {
                    const amp = plan.motion;
                    out.offsetY = amp * bounceOffset((t - key) / CFG.bounceDuration);
                }
                return out;
            }

            /* --- Idle: breathing + blinking ------------------------------- */
            const sinceIdle = t - planTypingStart;
            out.scale =
                1 +
                (CFG.idleBreathScale - 1) *
                    (0.5 - 0.5 * Math.cos((TAU * Math.max(0, t)) / (CFG.idleBreathDuration * 2)));
            let blinking = false;
            for (const b of plan.blinks) {
                if (t >= b && t < b + CFG.blinkHold) blinking = true;
            }
            out.sprite = blinking ? IDLE[1] : IDLE[0];
            void sinceIdle;
            return out;
        }

        return { pose, typingFrames };
    }

    /* -------------------------------------------------------- particles */

    function burst(seed, count, opts) {
        const r = rng(seed);
        const out = [];
        for (let i = 0; i < count; i += 1) {
            const angle = r() * TAU;
            const speed = lerp(opts.minSpeed, opts.maxSpeed, Math.pow(r(), 0.7));
            out.push({
                angle,
                speed,
                size: lerp(opts.minSize, opts.maxSize, r()),
                delay: r() * opts.spread,
                spin: lerp(-1, 1, r()),
                life: lerp(opts.minLife, opts.maxLife, r()),
            });
        }
        return out;
    }

    return { clamp, clamp01, lerp, TAU, ease, track, rng, CFG, SPRITES, IDLE, TYPING, SLEEP, createActor, bounceOffset, burst };
})();
