export function dependencies(...bins) {
  const missing = bins.filter((bin) => {
    return !Utils.exec(`which ${bin}`);
  });

  if (missing.length > 0)
    console.warn("missing dependencies:", missing.join(", "));

  return missing.length === 0;
}

export async function sh(cmd) {
  return Utils.execAsync(cmd).catch((err) => {
    console.error(typeof cmd === "string" ? cmd : cmd.join(" "), err);
    return "";
  });
}
