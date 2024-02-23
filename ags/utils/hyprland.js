const Hyprland = await Service.import("hyprland");

export const dispatch = (message) => {
  Hyprland.messageAsync(`dispatch ${message}`);
};
