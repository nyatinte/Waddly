/* =============================================================================
   Waddly promo — the 30 second film.

   One file, two languages. Nothing below knows which language it is in: the
   words come from window.LOCALES[lang] (scripts/locales/), the timings come
   from the beat table here. A translation can therefore never drift out of
   sync with the picture.

     0.0 –  2.5  cold open   : the pet hops out of the Dock onto the desktop
     2.5 –  8.4  typing      : a full keyboard sits at the bottom, the pet types
     8.4 – 17.0  your image  : a 3x3 sheet is drawn, dragged in, and lands as 9 frames
    16.45 – 17.65 try on      : cat, chick, penguin — the picker ring lands on the penguin
    17.6 – 22.5  options     : the three sizes, then the three modes, side by side
    22.5 – 26.2  freedom     : grab the pet, drag it anywhere, let it nap
    26.2 – 30.0  enter       : type, press Enter, hold on the reaction

   Every visual is a pure function of the timeline time, so a seek to any frame
   renders identically on every pass.
   ============================================================================= */

window.Story = (function () {
    /* =====================================================================
       Language selection. `lang` is declared in index.html's
       data-composition-variables (default "ja") and overridden at render time
       with --variables '{"lang":"en"}'.

       The words themselves live in scripts/locales/<lang>.js; nothing below
       this point reads the language again.
       ===================================================================== */

    function readLang() {
        const pick = (source) => {
            if (!source || typeof source !== "object") return null;
            const value = source.lang;
            return value === undefined || value === null ? null : String(value);
        };
        try {
            /* the producer injects this before any page script runs */
            const injected = pick(window.__hfVariables);
            if (injected) return injected;
        } catch (error) {
            /* no injected payload: fall through */
        }
        try {
            const hf = window.__hyperframes;
            if (hf && typeof hf.getVariables === "function") {
                const scoped = pick(hf.getVariables());
                if (scoped) return scoped;
            }
        } catch (error) {
            /* runtime not up yet: fall through */
        }
        try {
            const declared = JSON.parse(
                document.documentElement.getAttribute("data-composition-variables") || "[]"
            );
            const entry = (declared || []).find((d) => d && d.id === "lang");
            if (entry && entry.default) return String(entry.default);
        } catch (error) {
            /* malformed declaration: fall back to Japanese */
        }
        return "ja";
    }

    /* The language is chosen with --variables '{"lang":"en"}'; the default is
       Japanese. When this file has nothing to install it leaves whatever the
       previous story put on window.Story alone. */
    const LOCALES = window.LOCALES || {};
    const L = LOCALES[readLang()] || LOCALES.ja;
    if (!L) return window.Story;

    const W = window.W;
    const { clamp, clamp01, lerp, ease, track } = W;

    const DURATION = 30;
    const S = 1920;
    const S2 = 1080;

    /* -------------------------------------------------- the characters ---- */

    const SETS = window.PET_SETS || [];
    const byId = (id) => SETS.find((s) => s.id === id);
    /* the penguin ships with the app; the cat is the sheet the user registers,
       and the pet becomes it part-way through the film */
    const FIRST = byId("nyatinte-bot") || SETS[0];
    const SECOND = byId("cat") || SETS[1] || SETS[0];
    const THIRD = byId("chick") || null;
    const FIRST_IX = Math.max(0, SETS.indexOf(FIRST));
    const SECOND_IX = SETS.indexOf(SECOND) >= 0 ? SETS.indexOf(SECOND) : FIRST_IX;
    const THIRD_IX = SETS.indexOf(THIRD) >= 0 ? SETS.indexOf(THIRD) : FIRST_IX;

    const sheetSrc = (set) => `assets/pets/${set.id}-3x3.png`;
    /* the penguin artwork sits a little larger inside its cell than the sheets
       drawn for the cat, so the swap does not change the pet's apparent size */
    const FIT = { "nyatinte-bot": 1.0, cat: 1.08, chick: 1.07 };
    const fitOf = (set) => FIT[set.id] || 1;

    /* --------------------------------------------------------------- beats */

    const B = {
        fadeIn: [0.0, 0.65],
        petIn: [0.70, 1.50],
        /* it lands beside the Dock and hops to its spot — the first thing the
           film teaches is that it is alive */
        hop: [1.50, 2.42],

        camPush: [2.45, 3.30],
        kbRise: [2.95, 3.65],
        typeA: [3.25, 7.20],
        kbSink: [7.35, 8.00],
        camWide: [7.55, 8.35],

        aiIn: [7.65, 8.55],
        prompt: [8.55, 10.10],
        generating: [10.10, 11.35],
        winIn: [11.35, 12.20],
        dragOut: [12.20, 13.35],
        sheetDrop: 13.35,
        gridDraw: [13.35, 14.10],
        sweep: [14.10, 15.50],
        settle: [15.50, 16.35],
        winOut: [16.35, 17.00],

        /* The pet tries on the characters it just registered — a few quick
           transformations — then comes straight back to the penguin, which is
           the character the film is about. */
        morphA: 16.45,
        morphB: 17.05,
        morphBack: 17.65,

        /* the status showcase: sizes, then the modes the app ships with */
        camGallery: [17.55, 18.15],
        galA: [18.00, 18.70],
        galSwap: [19.80, 20.40],
        galOut: [21.90, 22.50],

        cursorIn: [22.55, 23.25],
        grab: 23.27,
        dragEnd: 24.75,
        drop: 24.75,
        doze: [24.90, 26.15],
        camSleep: [25.85, 26.15],
        wake: 26.20,

        typeB: [26.25, 27.50],
        heroIn: [26.60, 27.35],
        press: 27.55,

        clearStage: [28.05, 28.55],
        lockup: [27.65, 29.40],
    };

    /* ------------------------------------------------- deterministic input */

    /* The penguin is what the film is about. The sheets the user registers are
       tried on for a moment — cat, then chick — and then handed straight back. */
    const MORPHS = [
        { at: B.morphA, set: SECOND_IX },
        { at: B.morphB, set: THIRD_IX },
        { at: B.morphBack, set: FIRST_IX },
    ];

    function setIndexAt(t) {
        let ix = FIRST_IX;
        for (const m of MORPHS) if (t >= m.at) ix = m.set;
        return ix;
    }

    /* the most recent swap, so the flash and the sparks fire again each time */
    function morphAt(t) {
        let at = -Infinity;
        for (const m of MORPHS) if (t >= m.at && m.at > at) at = m.at;
        return at;
    }

    function schedule(seed, start, end, cfg) {
        const r = W.rng(seed);
        const out = [];
        let t = start;
        while (t < end) {
            const burst = Math.round(lerp(cfg.burstMin, cfg.burstMax, r()));
            for (let i = 0; i < burst && t < end; i += 1) {
                out.push(Number(t.toFixed(4)));
                t += lerp(cfg.gapMin, cfg.gapMax, r());
            }
            t += lerp(cfg.pauseMin, cfg.pauseMax, r());
        }
        return out;
    }

    const keysA = schedule(0x51ed, B.typeA[0], B.typeA[1], {
        burstMin: 4,
        burstMax: 9,
        gapMin: 0.085,
        gapMax: 0.2,
        pauseMin: 0.26,
        pauseMax: 0.6,
    });
    const keysB = schedule(0x9a13, B.typeB[0], B.typeB[1], {
        burstMin: 6,
        burstMax: 12,
        gapMin: 0.055,
        gapMax: 0.105,
        pauseMin: 0.15,
        pauseMax: 0.3,
    });
    const keyTimes = keysA.concat(keysB).sort((a, b) => a - b);

    const actor = W.createActor({
        keyTimes,
        /* the app holds the typing pose for 2.5 s after the last key, so the pet
           is still mid-type when Enter lands */
        typingWindows: [
            [B.typeA[0], B.typeA[1]],
            [B.typeB[0], B.press],
        ],
        blinks: [2.05, 8.20, 16.40, 18.55, 19.85, 22.10, 25.40],
        sleepWindow: [B.doze[0] + 0.75, B.wake],
        enterAt: B.press,
        motion: W.CFG.motionStrong,
    });

    /* ------------------------------------------------------------ geometry */

    const PET = { size: 320 };
    const POS = {
        /* right on the Waddly Dock icon — the app is where it comes from */
        spawn: { x: 1150, y: 830 },
        home: { x: 1430, y: 620 },
        drop: { x: 700, y: 600 },
    };
    /* Waddly's setup window (right) and the AI chat window (left) */
    const WIN = { w: 700, h: 460, x: 940, y: 300 };
    const AI = { w: 470, h: 340, x: 290, y: 300 };
    const SHEET = { size: 180, x: 940, y: 325 };
    /* the nine frames land as a 3x3 grid inside the drop zone, mirroring the
       sheet they were cut from */
    const SET = { slot: 62, gap: 9, cx: SHEET.x, cy: SHEET.y, count: 9 };
    /* where the AI chat's generated sheet sits — the pointer picks it up there */
    const AI_SHEET = { x: 193, y: 327 };
    /* the flying cells are children of .sheet, so their transform is local to it */
    const SHEET_ORIGIN = { x: SHEET.x - SHEET.size / 3, y: SHEET.y - SHEET.size / 3 };
    const HERO = { x: 400, y: 560, size: 300 };
    const GALLERY = { groundY: 780, box: 320, xs: [640, 1035, 1430] };
    const SIZES = [180, 240, 320];
    /* a dot under each sample that grows with it — small / medium / large,
       read off the picture instead of a label */
    const SIZE_DOTS = [12, 19, 27];
    const MODE_SPRITES = ["idle-1", "typing-1", "sleep-1"];
    const MODE_GLYPHS = ["breath", "keyboard", "sleep"];
    /* where the measuring bracket and the size dots sit, in world coords */
    const GAL_ROW = { bracket: 802, dot: 822, glyph: 868 };

    function slotCenter(i) {
        const col = i % 3;
        const row = Math.floor(i / 3);
        return {
            x: SET.cx + (col - 1) * (SET.slot + SET.gap),
            y: SET.cy + (row - 1) * (SET.slot + SET.gap),
        };
    }

    function sheetCellCenter(row, col) {
        const cell = SHEET.size / 3;
        return {
            x: SHEET.x - SHEET.size / 2 + cell * (col + 0.5),
            y: SHEET.y - SHEET.size / 2 + cell * (row + 0.5),
        };
    }

    /* ------------------------------------------------------------ camera */

    const CAM = [
        /* t,     cx,   cy,   z,    ease */
        [0.00, 960, 540, 1.00, "linear"],
        [2.45, 960, 540, 1.00, "linear"],
        [3.30, 1265, 730, 1.45, "inOutCubic"],
        [7.20, 1290, 736, 1.48, "inOutSine"],
        [7.55, 1290, 736, 1.48, "linear"],
        [8.35, 960, 540, 1.00, "inOutCubic"],
        [17.55, 960, 540, 1.00, "linear"],
        [18.15, 1075, 640, 1.08, "inOutCubic"],
        [21.90, 1075, 640, 1.08, "linear"],
        [22.50, 1010, 578, 1.06, "inOutSine"],
        [23.27, 1300, 630, 1.20, "inOutCubic"],
        [24.75, 880, 604, 1.14, "inOutCubic"],
        [25.30, 826, 602, 1.28, "inOutSine"],
        [25.85, 762, 600, 1.40, "inOutSine"],
        [26.15, 700, 592, 1.70, "inOutCubic"],
        [26.60, 700, 594, 1.70, "linear"],
        [27.35, 700, 655, 1.50, "inOutCubic"],
        [28.05, 700, 655, 1.50, "linear"],
        [30.00, 700, 651, 1.53, "inOutSine"],
    ];

    function cameraAt(t) {
        return {
            x: track(t, CAM.map((k) => [k[0], k[1], k[4]])),
            y: track(t, CAM.map((k) => [k[0], k[2], k[4]])),
            z: track(t, CAM.map((k) => [k[0], k[3], k[4]])),
        };
    }

    function project(wx, wy, cam) {
        return { x: (wx - cam.x) * cam.z + S / 2, y: (wy - cam.y) * cam.z + S2 / 2 };
    }

    /* ------------------------------------------------------- pet position */

    const dragPts = {
        x: [
            [0, POS.spawn.x, "linear"],
            [B.hop[0], POS.spawn.x, "linear"],
            [B.hop[1], POS.home.x, "outCubic"],
            [B.grab, POS.home.x, "linear"],
            [B.dragEnd, POS.drop.x, "inOutCubic"],
            [DURATION, POS.drop.x, "linear"],
        ],
        y: [
            [0, POS.spawn.y, "linear"],
            [B.hop[0], POS.spawn.y, "linear"],
            [B.hop[1], POS.home.y, "outCubic"],
            [B.grab, POS.home.y, "linear"],
            [B.grab + 0.28, POS.home.y - 110, "outCubic"],
            [B.dragEnd - 0.3, POS.drop.y - 122, "inOutSine"],
            [B.dragEnd, POS.drop.y, "inCubic"],
            [DURATION, POS.drop.y, "linear"],
        ],
    };

    /* four little hops between the Dock and its spot */
    const HOPS = 4;

    function petHop(t) {
        const [a, b] = B.hop;
        if (t <= a || t >= b) return 0;
        const u = (t - a) / (b - a);
        return -112 * Math.abs(Math.sin(Math.PI * u * HOPS)) * (1 - 0.22 * u);
    }

    /* anticipation and landing, so a hop reads as a hop */
    function hopSquash(t) {
        const [a, b] = B.hop;
        if (t <= a || t >= b) return { x: 1, y: 1 };
        const u = (t - a) / (b - a);
        const p = Math.pow(1 - Math.abs(Math.sin(Math.PI * u * HOPS)), 5);
        return { x: 1 + 0.13 * p, y: 1 - 0.13 * p };
    }

    function petLift(t) {
        if (t < B.grab) return 0;
        if (t < B.dragEnd) return ease.outCubic(clamp01((t - B.grab) / 0.25));
        if (t > B.wake && t < B.wake + 0.45) {
            return -34 * Math.sin(Math.PI * clamp01((t - B.wake) / 0.45));
        }
        return 0;
    }

    function petSquash(t) {
        if (t >= B.drop && t < B.drop + 0.5) {
            const u = (t - B.drop) / 0.5;
            const p = Math.sin(Math.PI * u) * Math.pow(1 - u, 0.6);
            return { x: 1 + 0.16 * p, y: 1 - 0.18 * p };
        }
        if (t >= B.grab && t < B.dragEnd) {
            const u = clamp01((t - B.grab) / 0.3);
            const hold = 1 - clamp01((t - (B.dragEnd - 0.35)) / 0.35);
            const p = ease.outBack(u) * hold;
            return { x: 1 - 0.05 * p, y: 1 + 0.07 * p };
        }
        return { x: 1, y: 1 };
    }

    function petTilt(t) {
        if (t < B.grab || t > B.dragEnd + 0.5) return 0;
        const moving = t > B.grab && t < B.dragEnd - 0.2;
        const target = moving ? -7 : 0;
        const u = clamp01((t - B.grab) / 0.35);
        return target * ease.outCubic(u) * (t > B.dragEnd ? Math.max(0, 1 - (t - B.dragEnd) / 0.5) : 1);
    }

    /* --------------------------------------------------------- pictograms

       One 24x24 grid, one stroke weight, one accent colour: the whole set
       reads as a family. Nothing here is a word. */

    const G = window.G;
    const ICONS = G.ICONS;
    const GRID_CHIP = G.GRID_CHIP;
    const DROP_GLYPH = G.DROP_GLYPH;

    /* the try-on picker: every character on offer, and the ring that picks one */
    const CHIPS = { top: 840, size: 96, xs: [762, 960, 1158] };
    const CHIP_SETS = [SECOND, THIRD, FIRST];
    const CHIP_IX = [SECOND_IX, THIRD_IX, FIRST_IX];
    const CHIP_AT = [B.morphA, B.morphB, B.morphBack];

    /* the chapters, named by a pictogram instead of a line of prose */
    const CHAPTERS = [
        { at: [3.30, 7.35], key: "keyboard" },
        { at: [8.30, 16.95], key: "image" },
        { at: [17.85, 22.30], key: "sliders" },
        { at: [22.70, 26.35], key: "hand" },
        { at: [26.40, 28.20], key: "return" },
    ];

    /* ------------------------------------------------------------------ copy

       Only the windows live here; the words come from the locale file. The two
       lists are read together by index, so adding a caption means adding one
       window here and one line in each locale. */

    const CAPTION_AT = [
        [1.45, 2.80],
        [3.55, 6.95],
        [15.15, 17.10],
        [18.35, 21.90],
        [24.95, 26.30],
    ];

    /* ------------------------------------------------------------ keyboard */

    /* A macOS-layout board. `w` is a flex weight; every row totals 15 so the
       letter keys line up column-wise. */
    const KB_ROWS = [
        [
            { t: "esc", w: 1.5, small: true },
            ...Array.from({ length: 12 }, (_, i) => ({ t: `F${i + 1}`, w: 1, small: true })),
            { t: "", w: 1.5, lock: true },
        ],
        [
            { t: "`", w: 1, pool: true },
            { t: "1", w: 1, pool: true },
            { t: "2", w: 1, pool: true },
            { t: "3", w: 1, pool: true },
            { t: "4", w: 1, pool: true },
            { t: "5", w: 1, pool: true },
            { t: "6", w: 1, pool: true },
            { t: "7", w: 1, pool: true },
            { t: "8", w: 1, pool: true },
            { t: "9", w: 1, pool: true },
            { t: "0", w: 1, pool: true },
            { t: "-", w: 1, pool: true },
            { t: "=", w: 1, pool: true },
            { t: "delete", w: 2, small: true, subRight: true },
        ],
        [
            { t: "tab", w: 1.5, small: true },
            ...["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"].map((t) => ({
                t,
                w: 1,
                pool: true,
            })),
            { t: "[", w: 1, pool: true },
            { t: "]", w: 1, pool: true },
            { t: "\\", w: 1.5, pool: true },
        ],
        [
            { t: "caps lock", w: 1.75, small: true },
            ...["A", "S", "D", "F", "G", "H", "J", "K", "L"].map((t) => ({ t, w: 1, pool: true })),
            { t: ";", w: 1, pool: true },
            { t: "'", w: 1, pool: true },
            { t: "return", w: 2.25, small: true, subRight: true },
        ],
        [
            { t: "shift", w: 2.25, small: true },
            ...["Z", "X", "C", "V", "B", "N", "M"].map((t) => ({ t, w: 1, pool: true })),
            { t: ",", w: 1, pool: true },
            { t: ".", w: 1, pool: true },
            { t: "/", w: 1, pool: true },
            { t: "shift", w: 2.75, small: true, subRight: true },
        ],
        [
            { t: "fn", w: 1, small: true },
            { t: "control", w: 1, small: true },
            { t: "option", w: 1, small: true },
            { t: "command", w: 1.25, small: true },
            { t: "", w: 4.5, space: true },
            { t: "command", w: 1.25, small: true },
            { t: "option", w: 1, small: true },
            { t: "◀", w: 1 },
            { t: "▲", w: 1 },
            { t: "▼", w: 1 },
            { t: "▶", w: 1 },
        ],
    ];

    const LOCK_GLYPH =
        `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#8b95a6" ` +
        `stroke-width="2.4" stroke-linecap="round"><rect x="4" y="10" width="16" height="11" rx="2.5"/>` +
        `<path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>`;

    /* ------------------------------------------------------------ runtime */

    const R = {};
    const particles = [];
    const sparks = [];
    const dust = [];
    const arrive = [];
    const morph = [];

    function el(tag, cls, parent) {
        return window.Desktop.el(tag, cls, parent);
    }

    function init() {
        const world = document.getElementById("world");
        const screen = document.getElementById("screen");

        Object.assign(R, window.Desktop.build(world, screen, { clock: "13:48", menu: L.menu }));
        R.world = world;
        R.screen = screen;
        /* the menu bar keeps the product name only: "ファイル" is a word */
        if (R.menuExtra) {
            if (L.menu) R.menuExtra.textContent = L.menu;
            else R.menuExtra.remove();
        }

        /* --- keyboard (screen space, bottom-anchored) ---------------------- */
        const kb = el("div", "keyboard", screen);
        R.kb = kb;
        const kbInner = el("div", "kb-persp", kb);
        el("div", "kb-plate", kbInner);
        R.kbSpill = el("div", "kb-spill", kbInner);
        const rowsEl = el("div", "kb-rows", kbInner);
        R.keys = [];
        R.pool = [];
        KB_ROWS.forEach((rowSpec) => {
            const row = el("div", "kb-row", rowsEl);
            rowSpec.forEach((spec) => {
                const cls =
                    "key" +
                    (spec.small ? " small" : "") +
                    (spec.subRight ? " sub-right" : "") +
                    (spec.lock ? " lock" : "");
                const key = el("div", cls, row);
                key.style.flex = `${spec.w} 1 0`;
                if (spec.lock) {
                    el("div", "glyph", key).innerHTML = LOCK_GLYPH;
                } else if (spec.small) {
                    el("span", "sub", key).textContent = spec.t;
                } else if (spec.t) {
                    el("div", "glyph", key).textContent = spec.t;
                }
                if (spec.pool) R.pool.push(R.keys.length);
                R.keys.push({ el: key });
            });
        });
        /* a deterministic "finger path" so the lit keys look like real typing */
        const pathRng = W.rng(0x5eed);
        R.typingPath = keyTimes.map(() => R.pool[Math.floor(pathRng() * R.pool.length)]);

        /* --- main pet ------------------------------------------------------ */
        R.petGlow = el("div", "pet-glow", world);
        const pet = el("div", "pet", world);
        pet.style.left = "0px";
        pet.style.top = "0px";
        pet.style.width = PET.size + "px";
        pet.style.height = PET.size + "px";
        R.pet = pet;
        /* one element, one sprite set per character — the swap is a hard swap */
        R.sets = SETS.map((set) => {
            const map = {};
            W.SPRITES.forEach((name) => {
                const img = el("img", null, pet);
                img.src = `${set.base}/${name}.png`;
                map[name] = img;
            });
            return { id: set.id, sprites: map, fit: fitOf(set) };
        });
        R.activeSet = FIRST_IX;
        R.currentSprite = null;
        R.shadow = el("div", "pet-shadow", world);
        R.zzz = [0, 1, 2].map(() => {
            const z = el("div", "zzz", world);
            z.textContent = "z";
            return z;
        });

        /* --- the AI chat window -------------------------------------------- */
        const ai = el("div", "ai-window", world);
        ai.style.left = AI.x + "px";
        ai.style.top = AI.y + "px";
        R.ai = ai;
        /* the chat offers two generated sheets; the cat is the one carried in */
        const sheetThumb = (set) =>
            `<span class="ai-sheet" style="background-image:url('${sheetSrc(set)}')"></span>`;
        ai.innerHTML =
            `<div class="ai-titlebar"><span class="ai-dots"><i></i><i></i><i></i></span>` +
            `<span class="ai-title">` +
            `<svg class="ai-spark" viewBox="0 0 24 24" fill="none" stroke="#8fd0ff" stroke-width="2" ` +
            `stroke-linecap="round" stroke-linejoin="round">` +
            `<path d="M12 3.5 13.9 9 19.5 11 13.9 13 12 18.5 10.1 13 4.5 11 10.1 9Z"/>` +
            `<path d="M18.5 3.5v3M17 5h3"/></svg>` +
            `</span></div>` +
            `<div class="ai-body">` +
            `<div class="ai-row user"><div class="ai-bubble user req">` +
            `<span class="ai-photo" style="background-image:url('${FIRST.base}/idle-1.png')"></span>` +
            `<svg class="ai-arrow" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.2" ` +
            `stroke-linecap="round" stroke-linejoin="round">` +
            `<path d="M4.5 12h13.5"/><path d="M13 6.6 18.4 12 13 17.4"/></svg>` +
            `<span class="ai-grid">${GRID_CHIP}</span>` +
            `</div></div>` +
            `<div class="ai-row"><div class="ai-bubble bot">` +
            `<span class="ai-avatar">` +
            `<svg width="14" height="14" viewBox="0 0 24 24" fill="#fff">` +
            `<path d="M12 3.5 13.9 9 19.5 11 13.9 13 12 18.5 10.1 13 4.5 11 10.1 9Z"/></svg>` +
            `</span>` +
            `<span class="ai-gen"><i></i><i></i><i></i></span>` +
            sheetThumb(SECOND) +
            (THIRD ? sheetThumb(THIRD) : "") +
            `</div></div>` +
            `</div>`;
        R.aiReq = ai.querySelector(".ai-bubble.user");
        R.aiPhoto = ai.querySelector(".ai-photo");
        R.aiArrow = ai.querySelector(".ai-arrow");
        R.aiGridChip = ai.querySelector(".ai-grid");
        R.aiBot = ai.querySelector(".ai-bubble.bot");
        R.aiGen = ai.querySelector(".ai-gen");
        R.aiSheets = Array.from(ai.querySelectorAll(".ai-sheet"));

        /* --- the app's setup window ----------------------------------------- */
        const win = el("div", "setup-window", world);
        win.style.left = WIN.x + "px";
        win.style.top = WIN.y + "px";
        R.win = win;
        win.innerHTML =
            `<div class="sw-titlebar"><span class="sw-dots"><i></i><i></i><i></i></span>` +
            `<span class="sw-brand"><img src="assets/brand/app-icon.png" alt="">Waddly</span></div>` +
            `<div class="sw-body"><div class="sw-steps"><i></i><i class="on"></i><i></i></div></div>` +
            `<div class="sw-drop"><span class="drop-glyph">${DROP_GLYPH}` +
            (L.dropHint ? `<span class="drop-hint">${L.dropHint}</span>` : "") +
            `</span></div>`;
        R.drop = win.querySelector(".sw-drop");
        R.dropGlyph = win.querySelector(".drop-glyph");

        /* the sheet being registered — and the character it turns the pet into */
        const sheet = el("div", "sheet", world);
        sheet.style.left = SHEET.x - SHEET.size / 2 + "px";
        sheet.style.top = SHEET.y - SHEET.size / 2 + "px";
        sheet.style.backgroundImage = `url("${sheetSrc(SECOND)}")`;
        R.sheet = sheet;
        const grid = el("div", "sheet-grid", sheet);
        grid.innerHTML =
            `<svg width="${SHEET.size}" height="${SHEET.size}" viewBox="0 0 ${SHEET.size} ${SHEET.size}">` +
            [1, 2]
                .map((i) => {
                    const p = (SHEET.size / 3) * i;
                    return (
                        `<line class="gv" x1="${p}" y1="0" x2="${p}" y2="${SHEET.size}"/>` +
                        `<line class="gh" x1="0" y1="${p}" x2="${SHEET.size}" y2="${p}"/>`
                    );
                })
                .join("") +
            `</svg>`;
        R.gridLines = Array.from(grid.querySelectorAll("line"));

        R.cells = [];
        for (let row = 0; row < 3; row += 1) {
            for (let col = 0; col < 3; col += 1) {
                const c = el("div", "cell", sheet);
                c.style.backgroundImage = `url("${sheetSrc(SECOND)}")`;
                c.style.backgroundPosition = `${col * 50}% ${row * 50}%`;
                R.cells.push({ el: c, row, col, order: row * 3 + col });
            }
        }

        R.slots = [];
        for (let i = 0; i < SET.count; i += 1) {
            const slot = el("div", "slot", world);
            const pos = slotCenter(i);
            slot.style.left = pos.x - SET.slot / 2 + "px";
            slot.style.top = pos.y - SET.slot / 2 + "px";
            const img = el("img", null, slot);
            img.src = `${SECOND.base}/${W.SPRITES[i]}.png`;
            R.slots.push(slot);
        }
        const hint = el("div", "slot-hint", world);
        hint.style.width = (3 * SET.slot + 2 * SET.gap) + "px";
        hint.style.left = SET.cx - (3 * SET.slot + 2 * SET.gap) / 2 + "px";
        hint.style.top = SET.cy + (SET.slot + SET.gap) + 8 + "px";
        R.slotHint = hint;

        /* the sheet once the pointer carries it into the app */
        R.png = el("div", "png-file", world);
        R.png.style.backgroundImage = `url("${sheetSrc(SECOND)}")`;

        /* --- gallery: three sizes, then three modes ------------------------- */
        R.gallery = GALLERY.xs.map((x, i) => {
            const node = el("div", "gallery-pet", world);
            node.style.left = x - GALLERY.box / 2 + "px";
            node.style.top = GALLERY.groundY - GALLERY.box + "px";
            const base = el("img", null, node);
            base.src = `${FIRST.base}/idle-1.png`;
            const alt = el("img", null, node);
            alt.src = `${FIRST.base}/${MODE_SPRITES[i]}.png`;
            return { node, base, alt };
        });
        /* the modes: one glyph per sample, no label */
        const galleryGlyph = (key, i) => {
            const node = el("div", "gallery-glyph", world);
            node.innerHTML = ICONS[key];
            node.style.left = GALLERY.xs[i] - 200 + "px";
            node.style.width = "400px";
            node.style.top = GAL_ROW.glyph + "px";
            node.style.height = "84px";
            const svg = node.querySelector("svg");
            svg.setAttribute("width", "76");
            svg.setAttribute("height", "76");
            return node;
        };
        R.galModes = MODE_GLYPHS.map(galleryGlyph);

        /* the sizes: a measuring bracket, and a dot that grows with each sample */
        const span = 130;
        R.sizeBracket = el("div", "size-bracket", world);
        R.sizeBracket.innerHTML =
            `<svg width="1920" height="1080" viewBox="0 0 1920 1080">` +
            `<path d="M${GALLERY.xs[0] - span} ${GAL_ROW.bracket} H${GALLERY.xs[2] + span} ` +
            `M${GALLERY.xs[0] - span} ${GAL_ROW.bracket - 13} V${GAL_ROW.bracket + 13} ` +
            `M${GALLERY.xs[2] + span} ${GAL_ROW.bracket - 13} V${GAL_ROW.bracket + 13} ` +
            GALLERY.xs
                .map((x) => `M${x} ${GAL_ROW.bracket - 11} V${GAL_ROW.bracket + 11}`)
                .join(" ") +
            `"/></svg>`;
        R.sizeBracketPath = R.sizeBracket.querySelector("path");

        R.sizeDots = SIZE_DOTS.map((size, i) => {
            const node = el("div", "size-dot", world);
            node.style.width = size + "px";
            node.style.height = size + "px";
            node.style.left = GALLERY.xs[i] - size / 2 + "px";
            node.style.top = GAL_ROW.dot + "px";
            return node;
        });

        /* --- hero Return key (US layout: one wide key, legend lower right) ----- */
        R.hero = el("div", "hero-key", world);
        R.hero.innerHTML = `<div class="hero-glow"></div><span class="rk-label">return</span>`;
        R.heroGlow = R.hero.querySelector(".hero-glow");

        /* --- particles -------------------------------------------------------- */
        W.burst(0x2f19, 34, {
            minSpeed: 90, maxSpeed: 520, minSize: 0.5, maxSize: 1.9,
            spread: 0.14, minLife: 0.6, maxLife: 1.5,
        }).forEach((p) => particles.push({ p, el: el("div", "particle", world) }));
        W.burst(0x77c1, 18, {
            minSpeed: 200, maxSpeed: 620, minSize: 1, maxSize: 2.1,
            spread: 0.1, minLife: 0.5, maxLife: 1.1,
        }).forEach((p) => sparks.push({ p, el: el("div", "spark", world) }));
        W.burst(0x1c4d, 14, {
            minSpeed: 60, maxSpeed: 260, minSize: 0.7, maxSize: 1.5,
            spread: 0.08, minLife: 0.5, maxLife: 0.9,
        }).forEach((p) => dust.push({ p, el: el("div", "dust", world) }));
        /* sparkles for the pet's entrance */
        W.burst(0x3ab7, 16, {
            minSpeed: 40, maxSpeed: 190, minSize: 0.6, maxSize: 1.4,
            spread: 0.3, minLife: 0.6, maxLife: 1.1,
        }).forEach((p) => arrive.push({ p, el: el("div", "particle", world) }));
        /* the sparks thrown off when the registered sheet becomes the pet */
        W.burst(0x5f2c, 26, {
            minSpeed: 120, maxSpeed: 620, minSize: 0.7, maxSize: 1.9,
            spread: 0.22, minLife: 0.45, maxLife: 1.0,
        }).forEach((p) => morph.push({ p, el: el("div", "particle", world) }));

        /* --- screen fx (scrim sits under the captions and the lockup) --------- */
        R.scrim = el("div", null, screen);
        R.scrim.style.cssText =
            "position:absolute;inset:0;opacity:0;will-change:opacity;" +
            "background:linear-gradient(180deg, rgba(3,7,18,0) 38%, rgba(3,7,18,0.72) 100%);";

        /* the silent cut's own furniture ------------------------------- */

        /* one pictogram per beat, in the same corner every time */
        R.chapters = CHAPTERS.map((chapter) => {
            const node = el("div", "chapter", screen);
            node.innerHTML = ICONS[chapter.key];
            return node;
        });

        /* one line of copy per beat, under the pictogram */
        R.captions = L.captions.map((text) => {
            const node = el("div", "caption right", screen);
            node.innerHTML = `<span class="plate">${text}</span>`;
            return node;
        });

        /* keyboard -> pet: the wire the key presses travel along */
        R.trace = el("div", "trace", screen);
        R.trace.innerHTML =
            `<svg width="1920" height="1080" viewBox="0 0 1920 1080">` +
            `<path class="wire" d=""/><circle class="pulse" r="7" cx="-40" cy="-40"/></svg>`;
        R.traceWire = R.trace.querySelector(".wire");
        R.tracePulse = R.trace.querySelector(".pulse");

        /* the try-on picker, screen space so the camera cannot move it */
        const chipRow = el("div", "chip-row", screen);
        chipRow.style.top = CHIPS.top + "px";
        R.chips = CHIP_SETS.map((set, i) => {
            const node = el("div", "chip", chipRow);
            node.style.left = CHIPS.xs[i] - CHIPS.size / 2 + "px";
            const img = el("img", null, node);
            img.src = `${set.base}/idle-1.png`;
            const ring = el("div", "ring", node);
            return { node, ring };
        });

        /* --- end lockup -------------------------------------------------------- */
        const lock = el("div", "lockup", screen);
        lock.innerHTML =
            `<div class="lockup-mark">` +
            `<img class="lockup-icon" src="assets/brand/app-icon.png" alt="">` +
            `<div class="lockup-name">Waddly</div>` +
            `</div>` +
            `<div class="lockup-diagram">` +
            `<span class="ld-ic">${ICONS.keyboard}</span>` +
            `<svg class="ld-arrow" viewBox="0 0 48 22" fill="none" ` +
            `stroke="rgba(214,236,255,0.9)" stroke-width="2.6" stroke-linecap="round" ` +
            `stroke-linejoin="round"><path d="M3 11h39"/><path d="M34.5 4.8 41 11l-6.5 6.2"/></svg>` +
            `<img class="ld-pet" src="${FIRST.base}/typing-1.png" alt="">` +
            `</div>` +
            (L.tagline ? `<div class="lockup-tag">${L.tagline}</div>` : "") +
            `<div class="lockup-meta"><span>${L.meta[0]}</span><span class="sep"></span>` +
            `<span>${L.meta[1]}</span></div>` +
            `<div class="lockup-link">` +
            `<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#8fd0ff" ` +
            `stroke-width="2" stroke-linecap="round" stroke-linejoin="round">` +
            `<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/>` +
            `<path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/></svg>` +
            `<span>github.com/<b>nyatinte/Waddly</b></span>` +
            `</div>`;
        R.lockup = lock;
        R.lockupIcon = lock.querySelector(".lockup-icon");
        R.lockupName = lock.querySelector(".lockup-name");
        R.lockupDiagram = lock.querySelector(".lockup-diagram");
        R.lockupPet = lock.querySelector(".ld-pet");
        R.lockupTag = lock.querySelector(".lockup-tag");
        R.lockupMeta = lock.querySelector(".lockup-meta");
        R.lockupLink = lock.querySelector(".lockup-link");

        R.flash = el("div", "flash", screen);
        R.bloom = el("div", "bloom", screen);
        R.vignette = el("div", "vignette", screen);
        R.fade = el("div", null, screen);
        R.fade.style.cssText = "position:absolute;inset:0;background:#000;opacity:1;will-change:opacity;";

        /* the app icon the pet walked out of */
        R.dockPulse = el("div", "dock-pulse", R.dockWaddly);

        return R;
    }

    /* ------------------------------------------------------------- render */

    function render(t) {
        const cam = cameraAt(t);

        R.world.style.transform =
            `translate3d(${(S / 2 - cam.x * cam.z).toFixed(3)}px, ${(S2 / 2 - cam.y * cam.z).toFixed(3)}px, 0) ` +
            `scale(${cam.z.toFixed(5)})`;

        R.fade.style.opacity = String(
            1 - ease.inOutCubic(clamp01((t - B.fadeIn[0]) / (B.fadeIn[1] - B.fadeIn[0])))
        );

        /* ---- main pet ------------------------------------------------------ */
        const pose = actor.pose(t);
        /* the registered sheets are tried on, then the penguin comes back */
        const setIndex = setIndexAt(t);
        if (R.activeSet !== setIndex || R.currentSprite !== pose.sprite) {
            /* a hard swap: exactly one source frame is ever visible */
            R.sets.forEach((s) => W.SPRITES.forEach((n) => s.sprites[n].classList.remove("on")));
            R.sets[setIndex].sprites[pose.sprite].classList.add("on");
            R.activeSet = setIndex;
            R.currentSprite = pose.sprite;
        }
        const fit = R.sets[setIndex].fit;
        const px = track(t, dragPts.x);
        const py = track(t, dragPts.y) - petLift(t) - petHop(t);
        const sq = petSquash(t);
        const hq = hopSquash(t);
        const squash = { x: sq.x * hq.x, y: sq.y * hq.y };
        const tilt = petTilt(t);
        const popU = clamp01((t - (B.settle[0] + 0.7)) / 0.55);
        const pop = popU > 0 && popU < 1 ? 1 + 0.13 * Math.sin(Math.PI * popU) : 1;
        /* the pop when the character changes */
        const morphT = morphAt(t);
        const tfU = clamp01((t - morphT) / 0.5);
        const tfPop = morphT > -Infinity ? 1 + 0.17 * Math.sin(Math.PI * tfU) : 1;

        /* entrance: materialise with a sparkle and a springy pop */
        const enterU = clamp01((t - B.petIn[0]) / (B.petIn[1] - B.petIn[0]));
        const enterScale = track(enterU, [
            [0, 0.0, "outCubic"],
            [0.52, 1.16, "outCubic"],
            [0.78, 0.95, "inOutQuad"],
            [1, 1, "outCubic"],
        ]);
        const enterAlpha = clamp01(enterU * 2.6);

        const lifted = t >= B.grab && t < B.dragEnd + 0.45;
        const liftAmount = lifted ? clamp01((B.dragEnd + 0.45 - t) / 0.45) : 0;

        R.pet.style.transform =
            `translate3d(${(px - PET.size / 2).toFixed(3)}px, ${(py - PET.size / 2).toFixed(3)}px, 0) ` +
            `scale(${(pose.scale * squash.x * pop * enterScale * tfPop * fit).toFixed(4)}, ` +
            `${(pose.scale * squash.y * pop * enterScale * tfPop * fit).toFixed(4)}) ` +
            `translateY(${pose.offsetY.toFixed(3)}px) rotate(${tilt.toFixed(3)}deg)`;

        R.shadow.style.transform =
            `translate3d(${px.toFixed(2)}px, ${(py + 148).toFixed(2)}px, 0) ` +
            `scale(${((1 - 0.28 * liftAmount) * enterScale).toFixed(3)})`;

        R.petGlow.style.opacity = String(Math.sin(Math.PI * clamp01(enterU)) * 0.95);
        R.petGlow.style.transform =
            `translate3d(${px.toFixed(2)}px, ${(py + 20).toFixed(2)}px, 0) ` +
            `scale(${(0.55 + 0.85 * ease.outCubic(enterU)).toFixed(3)})`;

        arrive.forEach(({ p, el: node }) => {
            const u = (t - B.petIn[0] - p.delay * 0.5) / p.life;
            if (!(u > 0 && u < 1)) {
                node.style.opacity = "0";
                return;
            }
            const dist = p.speed * ease.outCubic(u);
            node.style.opacity = String(clamp01(Math.sin(Math.PI * u)) * 0.9);
            node.style.transform =
                `translate3d(${(px + Math.cos(p.angle) * dist).toFixed(2)}px, ` +
                `${(py + Math.sin(p.angle) * dist - 60 * u).toFixed(2)}px, 0) ` +
                `scale(${(p.size * (0.5 + u)).toFixed(3)})`;
        });

        /* sparks thrown off by the character change */
        morph.forEach(({ p, el: node }) => {
            const u = (t - morphT - p.delay) / p.life;
            if (morphT === -Infinity || !(u > 0 && u < 1)) {
                node.style.opacity = "0";
                return;
            }
            const dist = p.speed * ease.outCubic(u);
            node.style.opacity = String(clamp01(Math.sin(Math.PI * u)) * 0.95);
            node.style.transform =
                `translate3d(${(px + Math.cos(p.angle) * dist).toFixed(2)}px, ` +
                `${(py - 40 + Math.sin(p.angle) * dist).toFixed(2)}px, 0) ` +
                `scale(${((1 - u) * p.size + 0.25).toFixed(3)})`;
        });

        const zzzOn = pose.sleeping && pose.zzz !== undefined;
        R.zzz.forEach((node, i) => {
            if (!zzzOn) {
                node.style.opacity = "0";
                return;
            }
            const u = ((t - B.doze[0]) / 2.4 + i * 0.33) % 1;
            node.style.opacity = String(0.92 * Math.sin(Math.PI * u));
            node.style.fontSize = `${28 + 16 * u}px`;
            node.style.transform =
                `translate3d(${(px + 96 + 58 * u).toFixed(2)}px, ${(py - 92 - 98 * u).toFixed(2)}px, 0) ` +
                `rotate(${(-6 + 10 * u).toFixed(2)}deg)`;
        });

        /* ---- keyboard ------------------------------------------------------ */
        const kbIn = track(t, [
            [0, 0, "linear"],
            [B.kbRise[0], 0, "linear"],
            [B.kbRise[1], 1, "outBack"],
            [B.kbSink[0], 1, "linear"],
            [B.kbSink[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]);
        const kbOpacity = clamp01(track(t, [
            [0, 0, "linear"],
            [B.kbRise[0], 0, "linear"],
            [B.kbRise[0] + 0.3, 1, "outCubic"],
            [B.kbSink[0], 1, "linear"],
            [B.kbSink[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]));
        R.kb.style.opacity = String(kbOpacity);
        R.kb.style.display = kbOpacity > 0.01 ? "block" : "none";
        R.kb.style.transform =
            `translate3d(0px, ${((1 - kbIn) * 220).toFixed(2)}px, 0) scale(${(0.94 + 0.06 * kbIn).toFixed(4)})`;

        const litState = [];
        keyTimes.forEach((kt, i) => {
            const u = (t - kt) / 0.22;
            if (u < 0 || u > 1) return;
            const idx = R.typingPath[i];
            litState[idx] = Math.max(litState[idx] || 0, 1 - u);
        });
        R.keys.forEach((k, i) => {
            const v = litState[i] || 0;
            k.el.classList.toggle("lit", v > 0.16);
            k.el.style.transform = `translateY(${(v * 3).toFixed(2)}px)`;
        });
        R.kbSpill.style.opacity = String(0.5 * Math.min(1, litState.reduce((a, b) => a + b, 0)));

        /* ---- AI chat: prompt, generate, then hand the sheet over ------------- */
        const aiU = track(t, [
            [0, 0, "linear"],
            [B.aiIn[0], 0, "linear"],
            [B.aiIn[1], 1, "outBack"],
            [B.winOut[0], 1, "linear"],
            [B.winOut[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]);
        const aiOpacity = clamp01(track(t, [
            [0, 0, "linear"],
            [B.aiIn[0], 0, "linear"],
            [B.aiIn[0] + 0.3, 1, "outCubic"],
            [B.winOut[0], 1, "linear"],
            [B.winOut[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]));
        R.ai.style.opacity = String(aiOpacity);
        R.ai.style.transform =
            `translate3d(0px, ${(70 * (1 - aiU)).toFixed(2)}px, 0) scale(${(0.92 + 0.08 * aiU).toFixed(4)})`;

        /* the request assembles itself: the picture, an arrow, the 3x3 sheet.
           That is the whole prompt — no words in either language. */
        const reqU = clamp01((t - B.prompt[0]) / (B.prompt[1] - B.prompt[0]));
        const chip = (node, from) => {
            const u = clamp01((reqU - from) / 0.42);
            node.style.opacity = String(u);
            node.style.transform = `scale(${(0.62 + 0.38 * ease.outBack(u)).toFixed(4)})`;
        };
        R.aiReq.style.opacity = String(clamp01((t - B.prompt[0]) * 5));
        chip(R.aiPhoto, 0.0);
        chip(R.aiArrow, 0.36);
        chip(R.aiGridChip, 0.64);

        /* generating… then the sheet appears */
        const genU = clamp01((t - B.generating[0]) / (B.generating[1] - B.generating[0]));
        R.aiGen.style.display = t >= B.generating[0] && genU < 0.62 ? "flex" : "none";
        R.aiGen.querySelectorAll("i").forEach((dot, i) => {
            const phase = (genU * 3.2 - i * 0.22) % 1;
            dot.style.opacity = String(0.25 + 0.75 * Math.max(0, Math.sin(Math.PI * clamp01(phase))));
        });
        const sheetInU = clamp01((genU - 0.62) / 0.38);
        R.aiSheets.forEach((node, i) => {
            const u = clamp01((sheetInU - i * 0.12) / 0.7);
            node.style.opacity = String(u);
            node.style.transform = `scale(${(0.86 + 0.14 * ease.outBack(u)).toFixed(4)})`;
        });
        /* the reply bubble only exists once the assistant starts working */
        R.aiBot.style.opacity = String(clamp01((t - B.generating[0]) * 5));
        R.aiBot.style.transform = `translate3d(0, ${((1 - clamp01((t - B.generating[0]) * 5)) * 8).toFixed(2)}px, 0)`;

        /* ---- Waddly setup window + dropping the sheet in ---------------------- */
        const winU = track(t, [
            [0, 0, "linear"],
            [B.winIn[0], 0, "linear"],
            [B.winIn[1], 1, "outBack"],
            [B.winOut[0], 1, "linear"],
            [B.winOut[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]);
        const winOpacity = clamp01(track(t, [
            [0, 0, "linear"],
            [B.winIn[0], 0, "linear"],
            [B.winIn[0] + 0.3, 1, "outCubic"],
            [B.winOut[0], 1, "linear"],
            [B.winOut[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]));
        R.win.style.opacity = String(winOpacity);
        R.win.style.transform =
            `translate3d(0px, ${(70 * (1 - winU)).toFixed(2)}px, 0) scale(${(0.92 + 0.08 * winU).toFixed(4)})`;

        /* the pointer's world position */
        /* the pointer picks the sheet up in the chat, then carries it right */
        const cursorX = track(t, [
            [0, AI_SHEET.x - 84, "linear"],
            [B.dragOut[0] - 0.25, AI_SHEET.x - 84, "linear"],
            [B.dragOut[0], AI_SHEET.x, "outCubic"],
            [B.dragOut[0] + 0.25, AI_SHEET.x, "linear"],
            [B.dragOut[1], SHEET.x, "inOutCubic"],
            [B.dragOut[1] + 0.4, SHEET.x, "linear"],
            [B.cursorIn[0], 1900, "linear"],
            [B.cursorIn[1] - 0.05, POS.home.x + 10, "inOutCubic"],
            [B.grab, POS.home.x + 10, "linear"],
            [B.dragEnd, POS.drop.x + 8, "inOutCubic"],
            [DURATION, POS.drop.x + 8, "linear"],
        ]);
        const cursorY = track(t, [
            [0, AI_SHEET.y + 58, "linear"],
            [B.dragOut[0] - 0.25, AI_SHEET.y + 58, "linear"],
            [B.dragOut[0], AI_SHEET.y, "outCubic"],
            [B.dragOut[0] + 0.25, AI_SHEET.y, "linear"],
            [B.dragOut[1], SHEET.y, "inOutCubic"],
            [B.dragOut[1] + 0.4, SHEET.y, "linear"],
            [B.cursorIn[0], 200, "linear"],
            [B.cursorIn[1] - 0.05, POS.home.y + 118, "inOutCubic"],
            [B.grab, POS.home.y + 118, "linear"],
            [B.dragEnd, POS.drop.y + 118, "inOutCubic"],
            [DURATION, POS.drop.y + 118, "linear"],
        ]);

        /* the sheet detaches from the chat and is carried into the app */
        const carryU = clamp01(track(t, [
            [0, 0, "linear"],
            [B.dragOut[0], 0, "linear"],
            [B.dragOut[0] + 0.25, 1, "outCubic"],
            [B.sheetDrop - 0.06, 1, "linear"],
            [B.sheetDrop, 0, "inQuad"],
            [DURATION, 0, "linear"],
        ]));
        R.png.style.opacity = String(carryU);
        R.png.style.display = carryU > 0.01 ? "block" : "none";
        R.png.style.transform =
            `translate3d(${(cursorX + 40).toFixed(2)}px, ${(cursorY + 40).toFixed(2)}px, 0) ` +
            `rotate(${(2.5 * Math.sin(t * 1.7)).toFixed(2)}deg) scale(${(0.92 + 0.08 * carryU).toFixed(3)})`;
        /* the in-chat copy hides while it is being carried */
        R.aiSheets.forEach((node, i) => {
            const u = clamp01((sheetInU - i * 0.12) / 0.7);
            node.style.opacity = String(u * (1 - carryU));
        });

        const dropHot = t >= B.dragOut[1] - 0.4 && t < B.sheetDrop + 0.25;
        R.drop.classList.toggle("hot", dropHot);

        const sheetU = track(t, [
            [0, 0, "linear"],
            [B.sheetDrop, 0, "linear"],
            [B.gridDraw[1], 1, "outBack"],
            [B.winOut[0], 1, "linear"],
            [B.winOut[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]);
        const sheetOpacity = clamp01(track(t, [
            [0, 0, "linear"],
            [B.sheetDrop, 0, "linear"],
            [B.sheetDrop + 0.22, 1, "outCubic"],
            [B.winOut[0], 1, "linear"],
            [B.winOut[1], 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]));
        R.sheet.style.opacity = String(sheetOpacity);
        R.sheet.style.transform = `scale(${(0.86 + 0.14 * sheetU).toFixed(4)})`;
        R.dropGlyph.style.opacity = String(1 - sheetOpacity);

        const gridU = clamp01((t - B.gridDraw[0]) / (B.gridDraw[1] - B.gridDraw[0]));
        R.gridLines.forEach((line, i) => {
            line.style.strokeDashoffset = String(
                SHEET.size * (1 - ease.inOutCubic(clamp01((gridU - i * 0.12) / 0.6)))
            );
        });

        const cellFlight = 0.62;
        R.cells.forEach((cell) => {
            const start = B.sweep[0] + cell.order * 0.135;
            const u = clamp01((t - start) / cellFlight);
            if (u <= 0) {
                cell.el.style.opacity = "0";
                return;
            }
            const from = sheetCellCenter(cell.row, cell.col);
            const to = slotCenter(cell.order);
            const e = ease.inOutQuart(u);
            const cx = lerp(from.x, to.x, e);
            const cy = lerp(from.y, to.y, e) - 60 * Math.sin(Math.PI * u);
            const scale = lerp(1, SET.slot / (SHEET.size / 3), e) * (1 + 0.12 * Math.sin(Math.PI * u));
            cell.el.style.transform =
                `translate3d(${(cx - SHEET_ORIGIN.x).toFixed(2)}px, ${(cy - SHEET_ORIGIN.y).toFixed(2)}px, 0) ` +
                `scale(${scale.toFixed(4)})`;
            cell.el.style.opacity = String((1 - clamp01((u - 0.86) / 0.14)) * winOpacity);
        });

        R.slots.forEach((slot, i) => {
            const arriveAt = B.sweep[0] + i * 0.135 + cellFlight * 0.86;
            const u = clamp01((t - arriveAt) / 0.22);
            const out = clamp01((t - B.winOut[0]) / (B.winOut[1] - B.winOut[0]));
            slot.style.opacity = String(u * (1 - out));
            slot.style.transform = `scale(${(0.7 + 0.3 * ease.outBack(u)).toFixed(4)})`;
            const pulse = t > B.settle[0] + i * 0.06 && t < B.settle[0] + i * 0.06 + 0.36;
            slot.classList.toggle("lit", pulse);
            slot.querySelector("img").style.opacity = String(u);
        });

        const hintU = clamp01((t - B.settle[0] - 0.1) / 0.9);
        R.slotHint.style.opacity = String(
            Math.sin(Math.PI * hintU) * (1 - clamp01((t - B.winOut[0]) / 0.3))
        );

        /* ---- gallery: sizes, then modes ------------------------------------- */
        const galOut = clamp01((t - B.galOut[0]) / (B.galOut[1] - B.galOut[0]));
        const swap = ease.inOutCubic(clamp01((t - B.galSwap[0]) / (B.galSwap[1] - B.galSwap[0])));
        /* on the way out the samples return to the idle pose first, so the
           rightmost one lands exactly on the pet that takes over */
        const swapBack = swap * (1 - ease.inOutCubic(clamp01((t - B.galOut[0]) / 0.2)));
        R.gallery.forEach((g, i) => {
            const appear = clamp01((t - B.galA[0] - i * 0.11) / 0.5);
            /* the size reverts with the pose, so the rightmost sample is back at
               320 px and lands pixel-for-pixel on the pet that takes over */
            const size = lerp(SIZES[i], 240, swapBack);
            let scale = (size / GALLERY.box) * (0.88 + 0.12 * ease.outBack(appear));
            /* the status samples move the way the pet does: the typing one
               bounces, the sleeping one breathes */
            if (swap > 0.35) {
                const u = clamp01((swap - 0.35) / 0.65);
                if (i === 1) scale *= 1 + 0.012 * u * Math.sin(t * 11.0);
                if (i === 2) scale *= 1 + 0.018 * u * (0.5 - 0.5 * Math.cos(t * 2.1));
            }
            g.node.style.opacity = String(ease.outCubic(appear) * (1 - ease.inCubic(galOut)));
            g.node.style.transform = `scale(${scale.toFixed(4)})`;
            g.base.style.opacity = String(1 - swapBack);
            g.alt.style.opacity = String(swapBack);
        });
        const petHandover =
            ease.outCubic(clamp01((t - B.galA[0] - 0.3) / 0.4)) *
            (1 - ease.inCubic(clamp01((t - B.galOut[0] - 0.14) / 0.42)));
        R.pet.style.opacity = String(enterAlpha * (1 - petHandover));
        R.shadow.style.opacity = String((0.72 - 0.34 * liftAmount) * enterAlpha * (1 - petHandover));
        /* the ruler draws itself across the three samples */
        const rulerU = ease.inOutCubic(clamp01((t - B.galA[0] - 0.2) / 0.9));
        R.sizeBracket.style.opacity = String((1 - swap) * (1 - ease.inCubic(galOut)));
        R.sizeBracketPath.style.strokeDashoffset = String(1400 * (1 - rulerU));
        R.sizeDots.forEach((node, i) => {
            const appear = ease.outCubic(clamp01((t - B.galA[0] - i * 0.11 - 0.34) / 0.4));
            node.style.opacity = String(appear * (1 - swap) * (1 - ease.inCubic(galOut)));
            node.style.transform = `scale(${(0.45 + 0.55 * ease.outBack(appear)).toFixed(4)})`;
        });
        const modeOut = clamp01((t - B.galOut[0]) / 0.15);
        R.galModes.forEach((node, i) => {
            const u = clamp01((swap - i * 0.09) / 0.62);
            node.style.opacity = String(u * (1 - ease.inCubic(modeOut)));
            node.style.transform =
                `translate3d(0, ${((1 - u) * 14).toFixed(2)}px, 0) ` +
                `scale(${(0.86 + 0.14 * ease.outBack(u)).toFixed(4)})`;
        });

        /* ---- cursor ---------------------------------------------------------- */
        const cursorOpacity = clamp01(track(t, [
            [0, 0, "linear"],
            [B.dragOut[0] - 0.25, 0, "linear"],
            [B.dragOut[0] + 0.25, 1, "outCubic"],
            [B.sheetDrop, 1, "linear"],
            [B.sheetDrop + 0.45, 0, "inCubic"],
            [B.cursorIn[0], 0, "linear"],
            [B.cursorIn[0] + 0.4, 1, "outCubic"],
            [B.dragEnd + 1.3, 1, "linear"],
            [B.dragEnd + 1.9, 0, "inCubic"],
            [DURATION, 0, "linear"],
        ]));
        const curScreen = project(cursorX, cursorY, cam);
        R.cursor.style.opacity = String(cursorOpacity);
        R.cursor.style.display = cursorOpacity > 0.01 ? "block" : "none";
        R.cursor.style.transform = `translate3d(${curScreen.x.toFixed(2)}px, ${curScreen.y.toFixed(2)}px, 0)`;

        R.clickRing.style.opacity = "0";
        const ringU = (t - B.grab) / 0.42;
        if (ringU >= 0 && ringU < 1) {
            R.clickRing.style.opacity = String(0.85 * (1 - ringU));
            R.clickRing.style.transform =
                `translate3d(${curScreen.x.toFixed(2)}px, ${curScreen.y.toFixed(2)}px, 0) ` +
                `scale(${(0.4 + 1.5 * ease.outCubic(ringU)).toFixed(3)})`;
        }

        /* ---- hero enter key (self-pressing, no pointer) ---------------------- */
        const heroEnter = track(t, [
            [0, 0, "linear"],
            [B.heroIn[0], 0, "linear"],
            [B.heroIn[1], 1, "outBack"],
            [DURATION, 1, "linear"],
        ]);
        const heroExit = clamp01((t - B.clearStage[0]) / (B.clearStage[1] - B.clearStage[0]));
        const heroOpacity = clamp01(track(t, [
            [0, 0, "linear"],
            [B.heroIn[0], 0, "linear"],
            [B.heroIn[0] + 0.25, 1, "outCubic"],
            [B.clearStage[0], 1, "linear"],
            [B.clearStage[1], 0, "inQuad"],
            [DURATION, 0, "linear"],
        ]));
        const pressU = clamp01((t - B.press) / 0.16);
        const heroDrop = -16 * ease.outCubic(pressU);
        const heroScale =
            (0.62 + 0.38 * heroEnter - 0.05 * pressU) * (1 - 0.3 * ease.inQuad(heroExit));
        R.hero.style.opacity = String(heroOpacity);
        R.hero.style.transform =
            `translate3d(${HERO.x}px, ${(HERO.y - 360 * (1 - heroEnter) + heroDrop).toFixed(2)}px, 0) ` +
            `scale(${heroScale.toFixed(4)})`;
        R.hero.classList.toggle("pressed", pressU > 0 && pressU < 1);
        R.heroGlow.style.opacity = String(
            clamp01(track(t, [
                [0, 0, "linear"],
                [B.heroIn[1], 0.25, "outCubic"],
                [B.press, 0.55, "linear"],
                [B.press + 0.15, 1, "outQuad"],
                [B.clearStage[1], 0, "inQuad"],
                [DURATION, 0, "linear"],
            ]))
        );

        /* ---- impact: the Return slam and the character changes ---------------- */
        const flashAmt = t >= B.press ? Math.pow(1 - clamp01((t - B.press) / 0.42), 2.2) : 0;
        const tfFlash = morphT > -Infinity ? Math.pow(1 - clamp01((t - morphT) / 0.42), 2.0) : 0;
        R.flash.style.opacity = String(0.85 * Math.max(flashAmt, 0.95 * tfFlash));
        const bloomU = clamp01((t - B.press) / 2.2);
        const slamBloom = t >= B.press ? Math.pow(1 - bloomU, 1.6) : 0;
        const tfBloom = morphT > -Infinity ? Math.pow(1 - clamp01((t - morphT) / 0.9), 1.6) : 0;
        const bloomAmt = Math.max(slamBloom, tfBloom);
        R.bloom.style.opacity = String(0.9 * bloomAmt);
        R.bloom.style.transform = `scale(${(0.25 + 1.5 * (1 - bloomAmt)).toFixed(4)})`;

        const shakeAmt = t >= B.press && t < B.press + 0.34 ? Math.pow(1 - (t - B.press) / 0.34, 2) : 0;
        R.world.style.transform +=
            ` translate3d(${(shakeAmt * 13 * Math.sin((t - B.press) * 118)).toFixed(2)}px, ` +
            `${(shakeAmt * 11 * Math.cos((t - B.press) * 96)).toFixed(2)}px, 0)`;

        const originX = px;
        const originY = py - 40;
        particles.forEach(({ p, el: node }) => {
            const u = (t - B.press - p.delay) / p.life;
            if (!(u > 0 && u < 1)) {
                node.style.opacity = "0";
                return;
            }
            const dist = p.speed * ease.outCubic(u);
            node.style.opacity = String(clamp01(Math.sin(Math.PI * Math.min(1, u * 1.35))) * 0.95);
            node.style.transform =
                `translate3d(${(originX + Math.cos(p.angle) * dist).toFixed(2)}px, ` +
                `${(originY + Math.sin(p.angle) * dist + 240 * u * u).toFixed(2)}px, 0) ` +
                `scale(${((1 - u) * p.size + 0.2).toFixed(3)})`;
        });
        sparks.forEach(({ p, el: node }) => {
            const u = (t - B.press - p.delay) / p.life;
            if (!(u > 0 && u < 1)) {
                node.style.opacity = "0";
                return;
            }
            const dist = p.speed * ease.outQuart(u);
            node.style.opacity = String(clamp01(Math.sin(Math.PI * u)) * 0.9);
            node.style.transform =
                `translate3d(${(originX + Math.cos(p.angle) * dist).toFixed(2)}px, ` +
                `${(originY + Math.sin(p.angle) * dist).toFixed(2)}px, 0) ` +
                `rotate(${((p.angle * 180) / Math.PI).toFixed(1)}deg) scaleY(${(p.size * (1 - 0.5 * u)).toFixed(3)})`;
        });
        dust.forEach(({ p, el: node }) => {
            const u = (t - B.drop - p.delay) / p.life;
            if (!(u > 0 && u < 1)) {
                node.style.opacity = "0";
                return;
            }
            const dist = p.speed * ease.outCubic(u);
            node.style.opacity = String(clamp01(Math.sin(Math.PI * u)) * 0.6);
            node.style.transform =
                `translate3d(${(POS.drop.x + Math.cos(p.angle) * dist).toFixed(2)}px, ` +
                `${(POS.drop.y + 150 + Math.sin(p.angle) * dist * 0.35).toFixed(2)}px, 0) ` +
                `scale(${(p.size * (0.6 + u)).toFixed(3)})`;
        });

        /* ---- chapter pictograms ------------------------------------------------ */
        CHAPTERS.forEach((chapter, i) => {
            const node = R.chapters[i];
            const [a, b] = chapter.at;
            const inU = clamp01((t - a) / 0.42);
            const outU = clamp01((t - (b - 0.34)) / 0.34);
            const visible = t >= a && t <= b;
            node.style.opacity = visible ? String(ease.outCubic(inU) * (1 - ease.inCubic(outU))) : "0";
            node.style.transform =
                `translate3d(${((1 - ease.outBack(inU)) * 26).toFixed(2)}px, 0, 0) ` +
                `scale(${(0.84 + 0.16 * ease.outBack(inU)).toFixed(4)})`;
        });

        /* ---- the copy, right under the pictogram ------------------------------- */
        CAPTION_AT.forEach((window, i) => {
            const node = R.captions[i];
            const [a, b] = window;
            const inU = clamp01((t - a) / 0.4);
            const outU = clamp01((t - (b - 0.34)) / 0.34);
            const visible = t >= a && t <= b;
            node.style.opacity = visible ? String(ease.outCubic(inU) * (1 - ease.inCubic(outU))) : "0";
            node.style.transform = `translate3d(0, ${((1 - ease.outCubic(inU)) * -14).toFixed(2)}px, 0)`;
        });

        /* ---- the wire from the keyboard to the pet ----------------------------- */
        const wireU = clamp01(
            track(t, [
                [0, 0, "linear"],
                [B.kbRise[0], 0, "linear"],
                [B.kbRise[1] + 0.35, 1, "outCubic"],
                [B.typeA[1], 1, "linear"],
                [B.kbSink[0], 0, "inCubic"],
                [DURATION, 0, "linear"],
            ])
        );
        R.trace.style.opacity = String(wireU * 0.9);
        R.tracePulse.style.opacity = "0";
        if (wireU > 0.01) {
            /* anchored just above the keyboard, landing on the pet */
            const ax = 960;
            const ay = 704;
            const petOnScreen = project(px, py - 30, cam);
            const bx = petOnScreen.x;
            const by = petOnScreen.y;
            const mx = (ax + bx) / 2 + 54;
            const my = Math.min(ay, by) - 130;
            R.traceWire.setAttribute(
                "d",
                `M${ax} ${ay} Q${mx.toFixed(1)} ${my.toFixed(1)} ${bx.toFixed(1)} ${by.toFixed(1)}`
            );
            /* a pulse rides the wire on every key press */
            let lastKey = -Infinity;
            for (const keyTime of keyTimes) {
                if (keyTime <= t && keyTime > lastKey) lastKey = keyTime;
            }
            const flight = t - lastKey;
            if (flight >= 0 && flight < 0.46) {
                const u = ease.outCubic(clamp01(flight / 0.4));
                const iu = 1 - u;
                const qx = iu * iu * ax + 2 * iu * u * mx + u * u * bx;
                const qy = iu * iu * ay + 2 * iu * u * my + u * u * by;
                R.tracePulse.setAttribute("cx", qx.toFixed(1));
                R.tracePulse.setAttribute("cy", qy.toFixed(1));
                R.tracePulse.setAttribute("r", (6.5 - 3.2 * u).toFixed(2));
                R.tracePulse.style.opacity = String(Math.sin(Math.PI * clamp01(u)) * 0.95);
            }
        }

        /* ---- the try-on picker -------------------------------------------------- */
        const chipsU = clamp01(
            track(t, [
                [0, 0, "linear"],
                [B.morphA - 0.3, 0, "linear"],
                [B.morphA, 1, "outCubic"],
                [B.morphBack + 0.4, 1, "linear"],
                [B.morphBack + 0.75, 0, "inCubic"],
                [DURATION, 0, "linear"],
            ])
        );
        R.chips.forEach((chip, i) => {
            const appear = clamp01((t - (B.morphA - 0.3) - i * 0.1) / 0.4);
            const picked = setIndexAt(t) === CHIP_IX[i];
            chip.node.style.opacity = String(chipsU * ease.outCubic(appear));
            chip.node.style.transform = `scale(${(0.72 + 0.28 * ease.outBack(appear)).toFixed(4)})`;
            const ringU = picked ? clamp01((t - CHIP_AT[i]) / 0.3) : 0;
            chip.ring.style.opacity = String(ringU * chipsU);
            chip.ring.style.transform = `scale(${(0.84 + 0.16 * ease.outBack(ringU)).toFixed(4)})`;
        });

        /* ---- end lockup -------------------------------------------------------- */
        const iconU = clamp01((t - B.lockup[0]) / 0.4);
        const nameU = clamp01((t - B.lockup[0] - 0.08) / 0.4);
        const tagU = clamp01((t - B.lockup[0] - 0.18) / 0.4);
        const metaU = clamp01((t - B.lockup[0] - 0.26) / 0.4);
        const linkU = clamp01((t - B.lockup[0] - 0.34) / 0.4);
        R.lockup.style.opacity = t >= B.lockup[0] ? "1" : "0";
        R.lockupIcon.style.opacity = String(ease.outCubic(iconU));
        R.lockupIcon.style.transform = `scale(${(0.7 + 0.3 * ease.outBack(iconU)).toFixed(4)})`;
        R.lockupName.style.opacity = String(ease.outCubic(nameU));
        R.lockupName.style.transform = `translate3d(0, ${((1 - ease.outCubic(nameU)) * 22).toFixed(2)}px, 0)`;
        R.lockupDiagram.style.opacity = String(ease.outCubic(tagU));
        R.lockupDiagram.style.transform = `translate3d(0, ${((1 - ease.outCubic(tagU)) * 18).toFixed(2)}px, 0)`;
        if (R.lockupTag) {
            R.lockupTag.style.opacity = String(ease.outCubic(tagU));
            R.lockupTag.style.transform = `translate3d(0, ${((1 - ease.outCubic(tagU)) * 16).toFixed(2)}px, 0)`;
        }
        /* the tagline, said by the picture: it bounces while you type */
        const petBeat = Math.abs(Math.sin(t * 6.6));
        R.lockupPet.style.transform =
            `translate3d(0, ${(-8 * petBeat).toFixed(2)}px, 0) ` +
            `scale(${(1 + 0.08 * petBeat).toFixed(3)}, ${(1 - 0.06 * petBeat).toFixed(3)})`;
        R.lockupMeta.style.opacity = String(ease.outCubic(metaU) * 0.95);
        R.lockupLink.style.opacity = String(ease.outCubic(linkU));
        R.lockupLink.style.transform = `translate3d(0, ${((1 - ease.outCubic(linkU)) * 16).toFixed(2)}px, 0)`;

        R.scrim.style.opacity = String(clamp01((t - B.clearStage[0] - 0.1) / 0.8) * 0.92);

        /* ---- desktop ambience ---------------------------------------------------- */
        R.aurora.style.transform =
            `translate3d(${(Math.sin(t * 0.11) * 60).toFixed(2)}px, ${(Math.cos(t * 0.08) * 40).toFixed(2)}px, 0) ` +
            `rotate(${(t * 1.4).toFixed(2)}deg)`;
        R.aurora.style.opacity = String(0.55 + 0.12 * Math.sin(t * 0.5));
        R.halo.style.opacity = String(
            clamp01(
                track(t, [
                    [0, 0.18, "linear"],
                    [B.typeA[1], 0.45, "inOutSine"],
                    [B.typeB[1], 0.95, "inOutSine"],
                    [B.press + 0.4, 0.35, "inOutSine"],
                    [DURATION, 0.25, "inOutSine"],
                ])
            )
        );
        R.dockDot.style.opacity = "0.9";
        /* the ring that says "this app is where it came from" */
        const dockU = clamp01((t - B.petIn[0]) / 1.15);
        const dockOn = t >= B.petIn[0] && dockU < 1;
        R.dockPulse.style.opacity = dockOn ? String((1 - dockU) * 0.9) : "0";
        R.dockPulse.style.transform = `scale(${(0.7 + 0.95 * dockU).toFixed(3)})`;
        R.dock.style.transform = `translate(-50%, ${clamp((cam.z - 1.0) * 950, 0, 420).toFixed(1)}px)`;
    }

    return { init, render, duration: DURATION, beats: B, keyTimes };
})();
