/* =============================================================================
   Waddly promo — the code-drawn macOS desktop.

   Wallpaper, menu bar, Dock and the pointer are all drawn from scratch with
   CSS and SVG: no Apple artwork, wallpaper, icon or trademark is used, so the
   film can be published without a third-party licence.
   ============================================================================= */

window.Desktop = (function () {
    const SVG_NS = "http://www.w3.org/2000/svg";

    function el(tag, className, parent) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (parent) parent.appendChild(node);
        return node;
    }

    function svg(markup, parent, className) {
        const wrap = el("div", className, parent);
        wrap.innerHTML = markup;
        const node = wrap.firstElementChild;
        node.setAttribute("xmlns", SVG_NS);
        return node;
    }

    /* --- generic app icons for the Dock -------------------------------- */

    const DOCK_ICONS = [
        { from: "#7fb4ff", to: "#2f6fe0", art: '<circle cx="23" cy="23" r="9" fill="#fff" opacity=".92"/>' },
        { from: "#ffd08a", to: "#f07a3c", art: '<path d="M17 14 L34 23 L17 32 Z" fill="#fff" opacity=".92"/>' },
        { from: "#a4f0c8", to: "#17a06a", art: '<rect x="15" y="15" width="16" height="16" rx="4" fill="#fff" opacity=".9"/>' },
        {
            from: "#cbb2ff",
            to: "#6b3ce0",
            art:
                '<rect x="14" y="14" width="18" height="4" rx="2" fill="#fff" opacity=".9"/>' +
                '<rect x="14" y="21" width="13" height="4" rx="2" fill="#fff" opacity=".7"/>' +
                '<rect x="14" y="28" width="18" height="4" rx="2" fill="#fff" opacity=".9"/>',
        },
        {
            from: "#ffc2dd",
            to: "#e0447e",
            art:
                '<path d="M29 13 v16 a5 5 0 1 1 -4 -4 V20 l-9 2 v13 a5 5 0 1 1 -4 -4 V18 Z" fill="#fff" opacity=".9"/>',
        },
        {
            from: "#cfe0f2",
            to: "#7f93ad",
            art:
                '<circle cx="23" cy="23" r="8.5" fill="none" stroke="#fff" stroke-width="3" opacity=".85"/>' +
                '<circle cx="23" cy="23" r="2.6" fill="#fff" opacity=".9"/>',
        },
    ];

    function dockItem(parent, icon, size) {
        const item = el("div", "dock-item", parent);
        item.style.width = size + "px";
        item.style.height = size + "px";
        item.style.borderRadius = Math.round(size * 0.24) + "px";
        if (icon.src) {
            const img = el("img", null, item);
            img.src = icon.src;
        } else {
            item.style.background = `linear-gradient(160deg, ${icon.from} 0%, ${icon.to} 100%)`;
            svg(
                `<svg viewBox="0 0 46 46" width="${size}" height="${size}">${icon.art}</svg>`,
                item
            );
        }
        return item;
    }

    /* --- build ---------------------------------------------------------- */

    function build(worldEl, screenEl, opts) {
        const refs = {};

        /* wallpaper */
        el("div", "wallpaper", worldEl);
        refs.aurora = el("div", "aurora", worldEl);
        el("div", "grain", worldEl);
        el("div", "desk-sheen", worldEl);

        /* menu bar */
        const bar = el("div", "menubar", worldEl);
        const left = el("div", "mb-group", bar);
        refs.halo = el("div", "mb-halo", bar);
        const waddly = el("div", "mb-waddly", left);
        /* Template-style status-item glyph, drawn here so the promo carries no
           traced third-party asset. */
        svg(
            `<svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true">` +
                `<circle cx="12.6" cy="3.1" r="2.1" fill="#fff"/>` +
                `<path d="M5.4 11.2c0-3.2 3.1-5.6 6.8-5.6s6.8 2.4 6.8 5.6c0 1-.8 1.7-1.8 1.7H7.2c-1 0-1.8-.7-1.8-1.7Z" fill="#fff"/>` +
                `<path d="M12 8.4c3.8 0 6.8 3.2 6.8 7.3 0 3.5-2.7 6.1-6.8 6.1s-6.8-2.6-6.8-6.1c0-4.1 3-7.3 6.8-7.3Z" fill="#fff"/>` +
                `<ellipse cx="8.5" cy="21.4" rx="2.5" ry="1.3" fill="#fff"/>` +
                `<ellipse cx="15.5" cy="21.4" rx="2.5" ry="1.3" fill="#fff"/></svg>`,
            waddly
        );
        refs.menuName = el("span", "mb-item", left);
        refs.menuName.textContent = "Waddly";
        refs.menuName.style.fontWeight = "600";
        const menuExtra = el("span", "mb-item", left);
        menuExtra.textContent = opts.menu || "";
        refs.menuExtra = menuExtra;

        const right = el("div", "mb-group", bar);
        svg(
            `<svg class="mb-glyph" width="17" height="17" viewBox="0 0 17 17">` +
                `<rect x="1.4" y="4.4" width="14.2" height="2.6" rx="1.3" fill="#fff" opacity=".85"/>` +
                `<circle cx="5.4" cy="5.7" r="2.1" fill="#fff"/>` +
                `<rect x="1.4" y="10" width="14.2" height="2.6" rx="1.3" fill="#fff" opacity=".85"/>` +
                `<circle cx="11.6" cy="11.3" r="2.1" fill="#fff"/></svg>`,
            right
        );
        svg(
            `<svg class="mb-glyph" width="18" height="14" viewBox="0 0 18 14" fill="none" stroke="#fff" stroke-linecap="round">` +
                `<path d="M1.2 5.2a11 11 0 0 1 15.6 0" stroke-width="1.7" opacity=".85"/>` +
                `<path d="M4.2 8.2a7 7 0 0 1 9.6 0" stroke-width="1.7" opacity=".85"/>` +
                `<circle cx="9" cy="11.6" r="1.5" fill="#fff" stroke="none"/></svg>`,
            right
        );
        const battery = el("div", "mb-battery", right);
        el("i", null, battery);
        refs.clock = el("span", "mb-clock", right);
        refs.clock.textContent = opts.clock;

        /* dock */
        const dock = el("div", "dock", worldEl);
        refs.dock = dock;
        refs.dockItems = DOCK_ICONS.map((icon) => dockItem(dock, icon, 46));
        el("div", "dock-sep", dock);
        const waddlyDock = dockItem(dock, { src: "assets/brand/app-icon.png" }, 46);
        refs.dockWaddly = waddlyDock;
        const dot = el("div", "dock-dot", waddlyDock);
        refs.dockDot = dot;

        /* pointer */
        refs.cursor = el("div", "cursor", screenEl);
        refs.cursor.innerHTML =
            `<svg width="30" height="40" viewBox="0 0 30 40">` +
            `<path d="M2.4 1.8 L2.4 30.6 L9.8 23.6 L14.6 36.4 L19.8 34.2 L15 21.8 L25.4 21 Z" ` +
            `fill="#ffffff" stroke="rgba(8,16,32,0.66)" stroke-width="2.6" stroke-linejoin="round"/></svg>`;
        refs.clickRing = el("div", "click-ring", screenEl);

        return refs;
    }

    return { build, el, svg };
})();
