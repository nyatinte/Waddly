/* Waddly promo — timeline wiring.
   The runtime seeks this single paused timeline; every visual is derived from
   its playhead, so any frame renders identically on every pass. */

(function () {
    function boot() {
        const story = window.Story;
        const root = document.getElementById("root");
        const id = (root && root.dataset.compositionId) || "waddly";
        story.init();

        window.__timelines = window.__timelines || {};
        const tl = gsap.timeline({ paused: true });
        const state = { t: 0 };

        tl.to(
            state,
            {
                t: story.duration,
                duration: story.duration,
                ease: "none",
                onUpdate: () => paint(),
            },
            0
        );

        let painting = false;
        function paint() {
            if (painting) return;
            painting = true;
            try {
                story.render(tl.time());
            } catch (error) {
                show(error);
            } finally {
                painting = false;
            }
        }

        tl.eventCallback("onUpdate", paint);
        window.__timelines[id] = tl;

        story.render(0);
        tl.seek(0);
    }

    function start() {
        try {
            boot();
        } catch (error) {
            document.title = "BOOT ERROR: " + (error && error.message);
            show(error);
            throw error;
        }
    }

    /* A throw during a seek is otherwise invisible: the frame simply keeps
       whatever state it had. Put it on the page so a render cannot ship a
       half-painted frame without anyone noticing. */
    function show(error) {
        let node = document.getElementById("boot-error");
        if (!node) {
            node = document.createElement("pre");
            node.id = "boot-error";
            node.style.cssText =
                "position:fixed;left:20px;top:120px;z-index:9999;max-width:1200px;margin:0;" +
                "padding:16px 20px;background:rgba(130,0,0,0.94);color:#fff;" +
                "font:14px/1.45 monospace;white-space:pre-wrap;border-radius:10px;";
            document.body.appendChild(node);
        }
        node.textContent = "render error: " + (error && error.message) + "\n\n" + (error && error.stack);
    }

    if (document.fonts && document.fonts.load) {
        Promise.all([
            document.fonts.load('400 32px "Noto Sans JP"'),
            document.fonts.load('600 34px "Noto Sans JP"'),
            document.fonts.load('800 88px "Noto Sans JP"'),
        ]).then(start, start);
    } else {
        start();
    }
})();
