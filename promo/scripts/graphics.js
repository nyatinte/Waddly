/* =============================================================================
   Waddly promo — the pictogram set.

   Shared by every picture-led cut (silent / en / v2). One 24x24 grid, one
   stroke weight, one accent colour, so the whole family reads as one hand.

   Pure string builders: nothing here reads the DOM or the clock.
   ============================================================================= */

window.G = (function () {
    const ICON_ATTR =
        'viewBox="0 0 24 24" fill="none" stroke="#8fd0ff" stroke-width="1.7" ' +
        'stroke-linecap="round" stroke-linejoin="round"';
    const icon = (body, extra) => `<svg ${ICON_ATTR} ${extra || ""}>${body}</svg>`;

    const ICONS = {
        /* a keyboard: the app is listening to your typing */
        keyboard: icon(
            `<rect x="2.2" y="6.2" width="19.6" height="11.6" rx="2.6"/>` +
                `<path d="M6 9.7h.01M9 9.7h.01M12 9.7h.01M15 9.7h.01M18 9.7h.01"/>` +
                `<path d="M6 12.7h.01M9 12.7h.01M12 12.7h.01M15 12.7h.01M18 12.7h.01"/>` +
                `<path d="M8.4 15.6h7.2"/>`
        ),
        /* a picture going in: make the character yourself */
        image: icon(
            `<rect x="2.6" y="4.4" width="18.8" height="15.2" rx="2.8"/>` +
                `<circle cx="8.4" cy="9.6" r="1.6"/>` +
                `<path d="M3.4 17.4l4.9-4.6a1.8 1.8 0 0 1 2.4 0l3.5 3.3"/>` +
                `<path d="M13.1 15.2l1.8-1.7a1.8 1.8 0 0 1 2.4 0l3.2 3"/>`
        ),
        /* sliders: the sizes and the motions you get to choose */
        sliders: icon(
            `<path d="M4 7.2h16M4 12h16M4 16.8h16"/>` +
                `<circle cx="9.2" cy="7.2" r="2.4" fill="#8fd0ff" stroke="none"/>` +
                `<circle cx="15.2" cy="12" r="2.4" fill="#8fd0ff" stroke="none"/>` +
                `<circle cx="7.4" cy="16.8" r="2.4" fill="#8fd0ff" stroke="none"/>`
        ),
        /* an open hand: pick it up and put it anywhere */
        hand: icon(
            `<path d="M8.8 12.4V5.9a1.7 1.7 0 0 1 3.4 0v4.5"/>` +
                `<path d="M12.2 10.4V4.9a1.7 1.7 0 0 1 3.4 0v5.5"/>` +
                `<path d="M15.6 10.9V7.6a1.7 1.7 0 0 1 3.4 0v6.6c0 3.7-2.7 6.2-6.3 6.2h-1.1c-2.1 0-3.5-.8-4.5-2.4l-2.4-4a1.7 1.7 0 0 1 2.8-1.9l1.5 2.1"/>`
        ),
        /* the Return key: the app's signature move */
        return: icon(
            `<path d="M19.6 6.4v6.2a2.8 2.8 0 0 1-2.8 2.8H5.2"/>` +
                `<path d="M8.8 11.6 4.6 15.4l4.2 3.8"/>`
        ),
        /* a window: the editor the pet keeps you company in */
        window: icon(
            `<rect x="2.4" y="4.2" width="19.2" height="15.6" rx="2.8"/>` +
                `<path d="M2.4 8.8h19.2"/>` +
                `<path d="M5.6 6.5h.01M8 6.5h.01"/>` +
                `<path d="M8.2 12.6h7.6M8.2 15.8h4.6"/>`
        ),
        /* three characters in a row: the try-on carousel */
        characters: icon(
            `<circle cx="5.6" cy="9.4" r="2.6"/>` +
                `<circle cx="12" cy="9.4" r="2.6" fill="#8fd0ff" stroke="none"/>` +
                `<circle cx="18.4" cy="9.4" r="2.6"/>` +
                `<path d="M2.4 18.2c.7-2 1.8-3 3.2-3s2.5 1 3.2 3"/>` +
                `<path d="M8.8 18.2c.7-2 1.8-3 3.2-3s2.5 1 3.2 3"/>` +
                `<path d="M15.2 18.2c.7-2 1.8-3 3.2-3s2.5 1 3.2 3"/>`
        ),
        /* the three modes, used under the status samples */
        breath: icon(
            `<circle cx="12" cy="12" r="8.6"/>` +
                `<path d="M6.4 12c1.6 0 1.6-3.2 3.2-3.2s1.6 6.4 3.2 6.4 1.6-3.2 3.2-3.2 1.6 3.2 3.2 3.2"/>`,
            'stroke-width="1.5"'
        ),
        sleep: icon(
            `<path d="M5.4 7.6h6.2L5.4 13h6.2"/>` + `<path d="M13.4 13.4h4.4l-4.4 4.2h4.4"/>`,
            'stroke-width="1.9"'
        ),
    };

    /* a 3x3 sprite sheet, drawn as nine tiles */
    function gridGlyph(size, fill, opacity) {
        const step = size / 3;
        const pad = step * 0.13;
        const side = (step - pad * 2).toFixed(2);
        const radius = (step * 0.16).toFixed(2);
        let tiles = "";
        for (let row = 0; row < 3; row += 1) {
            for (let col = 0; col < 3; col += 1) {
                tiles +=
                    `<rect x="${(col * step + pad).toFixed(2)}" y="${(row * step + pad).toFixed(2)}" ` +
                    `width="${side}" height="${side}" rx="${radius}"/>`;
            }
        }
        return `<svg viewBox="0 0 ${size} ${size}" fill="${fill}" opacity="${opacity}">${tiles}</svg>`;
    }

    const GRID_CHIP = gridGlyph(48, "#ffffff", "0.94");

    /* the drop zone says it with an arrow falling into a 3x3 sheet */
    const DROP_GLYPH =
        `<svg viewBox="0 0 120 134" fill="none">` +
        `<path d="M60 4v20M50 16l10 10 10-10" stroke="rgba(255,255,255,0.62)" ` +
        `stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/>` +
        [0, 1, 2]
            .map((row) =>
                [0, 1, 2]
                    .map(
                        (col) =>
                            `<rect x="${17 + col * 30}" y="${40 + row * 30}" width="26" height="26" rx="6" ` +
                            `fill="rgba(255,255,255,0.13)" stroke="rgba(255,255,255,0.36)" stroke-width="1.7"/>`
                    )
                    .join("")
            )
            .join("") +
        `</svg>`;

    return { ICONS, GRID_CHIP, DROP_GLYPH, icon, gridGlyph };
})();
