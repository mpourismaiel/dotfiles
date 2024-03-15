class TodoList extends Service {
  static {
    Service.register(
      this,
      {
        "item-added": ["string", "int"],
        "item-removed": ["string", "int"],
        "item-updated": ["string", "int"],
        "plugin-added": ["string"],
      },
      {
        items: ["jsobject"],
        plugins: ["jsobject"],
      }
    );
  }

  #plugins = [];

  get items() {
    return this.#plugins.reduce((acc, plugin) => {
      acc[plugin.name].items();
      return acc;
    }, {});
  }

  registerPlugin(plugin) {
    plugin.connect("notify::item-added", (id) =>
      this.changed("item-added", plugin.name, id)
    );
    plugin.connect("notify::item-removed", (id) =>
      this.changed("item-removed", plugin.name, id)
    );
    plugin.connect("notify::item-updated", (id) =>
      this.changed("item-updated", plugin.name, id)
    );
    this.#plugins.push(plugin);
    this.changed("plugin-added", plugin.name);
    this.emit("plugins", this.#plugins);
  }
}
