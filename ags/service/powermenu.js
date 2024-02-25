import options from "../lib/options.js";

class PowerMenu extends Service {
  static {
    Service.register(
      this,
      {},
      {
        title: ["string"],
        cmd: ["string"],
      }
    );
  }

  #title = "";
  #cmd = "";

  get title() {
    return this.#title;
  }
  get cmd() {
    return this.#cmd;
  }

  action(action) {
    const sleep = options.getOptionVariable("sleep");
    const reboot = options.getOptionVariable("reboot");
    const logout = options.getOptionVariable("logout");
    const shutdown = options.getOptionVariable("shutdown");

    [this.#cmd, this.#title] = {
      sleep: [sleep.value, "Sleep"],
      reboot: [reboot.value, "Reboot"],
      logout: [logout.value, "Log Out"],
      shutdown: [shutdown.value, "Shutdown"],
    }[action];

    this.notify("cmd");
    this.notify("title");
    this.emit("changed");
    App.closeWindow("powermenu");
    App.openWindow("verification");
  }

  shutdown = () => {
    this.action("shutdown");
  };
}

const powermenu = new PowerMenu();
globalThis["powermenu"] = powermenu;
export default powermenu;
