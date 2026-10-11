/* Prints a composition's key schedule as JSON so the mixer can place one click
   per key press. Loads the real engine and story with a stub window — nothing
   here touches the DOM, so the schedule is exactly what renders.

   node tools/extract-keys.cjs [scripts/story.js] [lang] */

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..", "..");
const storyPath = process.argv[2] || "scripts/story.js";
const lang = process.argv[3] || "ja";

/* the story picks its copy from `lang`, so the stub has to answer for it */
global.window = { __hfVariables: { lang } };
global.document = { documentElement: { getAttribute: () => null } };

eval(fs.readFileSync(path.join(root, "scripts", "engine.js"), "utf8"));
eval(fs.readFileSync(path.join(root, "scripts", "graphics.js"), "utf8"));
for (const name of ["ja", "en"]) {
    eval(fs.readFileSync(path.join(root, "scripts", "locales", `${name}.js`), "utf8"));
}
window.PET_SETS = [
    { id: "nyatinte-bot", base: "assets/frames/nyatinte-bot" },
    { id: "cat", base: "assets/frames/cat" },
    { id: "chick", base: "assets/frames/chick" },
];
eval(fs.readFileSync(path.join(root, storyPath), "utf8"));

const story = window.Story;
if (!story) {
    throw new Error(`${storyPath} did not install a story for lang "${lang}"`);
}
process.stdout.write(JSON.stringify(story.keyTimes.map((t) => Number(t.toFixed(4)))));
