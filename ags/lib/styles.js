import { dependencies, sh } from "../utils/dots.js";
import options from "./options.js";

const SCSS_PATH = `${App.configDir}/styles/main.scss`;
const SCSS_COLORS_PATH = `${App.configDir}/styles/_colors.scss`;
const CSS_PATH = `${App.configDir}/style.css`;

const generateStyles = async () => {
  if (
    !options.getOption("matugen-enabled") ||
    !options.getOption("matugen-command") ||
    !dependencies(options.getOption("matugen-command"))
  )
    return;

  const matugenColors = await sh([
    options.getOption("matugen-command"),
    "--dry-run",
    "-j",
    "hex",
    "image",
    options.getOption("wallpaper"),
  ]).catch(() => {});
  if (!matugenColors) return;

  const colors =
    JSON.parse(matugenColors).colors[options.getOption("theme-mode")];
  const scssColors = Object.keys(colors)
    .map((key) => `$${key}: ${colors[key]};`)
    .join("\n");

  Utils.writeFileSync(scssColors, SCSS_COLORS_PATH);

  try {
    await Utils.execAsync(`sass ${SCSS_PATH} ${CSS_PATH}`);
  } catch (err) {
    console.error(`[ERROR GENERATING STYLES] ${err}`);
  }
};

const InitializeStyles = () => {
  options.registerKey(
    "matugen-enabled",
    true,
    (value) => typeof value === "boolean"
  );
  options.registerKey(
    "matugen-command",
    "matugen",
    (value) => typeof value === "string"
  );
  options.registerKey(
    "theme-mode",
    "dark",
    (value) => value === "dark" || value === "light"
  );

  App.applyCss(CSS_PATH);
  options.connect("wallpaper", generateStyles);
  options.connect("theme-mode", generateStyles);
  generateStyles().catch((err) =>
    console.error(`[ERROR GENERATING STYLES] ${err}`)
  );

  Utils.monitorFile(CSS_PATH, function () {
    App.resetCss();
    App.applyCss(CSS_PATH);
    console.log("[LOG] Styles loaded");
  });
};

export default InitializeStyles;
