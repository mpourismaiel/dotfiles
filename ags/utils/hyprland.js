const Hyprland = await Service.import("hyprland");

export const dispatch = (message) => {
  Hyprland.messageAsync(`dispatch ${message}`);
};

export const objToHyprlandConfig = (obj, indentLevel = 0) => {
  let config = "";
  const indent = "    ".repeat(indentLevel);

  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === "object" && value !== null) {
      config += `${indent}${key} {\n${objToHyprlandConfig(
        value,
        indentLevel + 1
      )}${indent}}\n`;
    } else {
      let formattedValue = value;
      if (Array.isArray(value)) {
        formattedValue = value.join(",");
      }

      config += `${indent}${key} = ${formattedValue}\n`;
    }
  }

  return config;
};

export const hyprlandConfigToObj = (configString) => {
  const lines = configString.trim().split("\n");
  const root = {};
  const stack = [root];
  let currentObject = root;

  lines.forEach((line) => {
    if (line.trim() === "") return;

    const nestedStartMatch = line.match(/^(\s*)(.+)\s*{/);
    const nestedEndMatch = line.match(/^(\s*)}/);
    const keyValueMatch = line.match(/^(\s*)(.+)\s*=\s*(.*)/);

    if (nestedStartMatch) {
      const newObject = {};
      currentObject[nestedStartMatch[2].trim()] = newObject;
      stack.push(newObject);
      currentObject = newObject;
    } else if (nestedEndMatch) {
      stack.pop();
      currentObject = stack[stack.length - 1];
    } else if (keyValueMatch) {
      let value = keyValueMatch[3];

      if (!isNaN(value)) {
        value = Number(value);
      } else if (value === "true" || value === "false") {
        value = value === "true";
      } else if (value.includes(",")) {
        value = value.split(",").map((v) => v.trim());
      }

      currentObject[keyValueMatch[2].trim()] = value;
    }
  });

  return root;
};
