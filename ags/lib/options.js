class Options {
  #configPath = `${App.configDir}/config.json`;
  #loadedOptions = {};
  #pendingConnects = {};
  #options = {};

  get options() {
    return this.options;
  }

  constructor() {
    this.#loadedOptions = this.loadOptions();
  }

  loadOptions() {
    try {
      const data = Utils.readFile(this.#configPath);
      return JSON.parse(data);
    } catch (error) {
      console.error(`[ERROR LOADING OPTIONS] ${error}`);
      Utils.writeFile("{}", this.#configPath);
      return {};
    }
  }

  registerKey(key, defaultValue = null, validator = () => true) {
    if (this.#options[key]) {
      throw new Error(`Option ${key} already exists`);
    }

    const data = this.#loadedOptions[key] || defaultValue;
    const isValid = validator(data);
    if (!isValid) {
      throw new Error(`Invalid value for option ${key}`);
    }

    const value = Variable(data);
    this.#options[key] = {
      value,
      validator,
    };

    value.connect("changed", ({ value }) => this.saveOptions(key, value));
    if (this.#pendingConnects[key]) {
      this.#pendingConnects[key].forEach((callback) =>
        value.connect("changed", callback)
      );
      delete this.#pendingConnects[key];
    }
  }

  updateOption(key, value) {
    const option = this.#options[key];
    if (!option) {
      throw new Error(`Option ${key} does not exist`);
    }

    const isValid = option.validator(value);
    if (!isValid) {
      throw new Error(`Invalid value for option ${key}`);
    }

    option.value.setValue(value);
  }

  getOptionVariable(key) {
    const option = this.#options[key];
    if (!option) {
      return null;
    }

    return option.value;
  }

  getOption(key) {
    return this.getOptionVariable(key)?.value || null;
  }

  connect(key, callback) {
    const option = this.#options[key];
    if (!option) {
      if (!this.#pendingConnects[key]) {
        this.#pendingConnects[key] = [];
      }

      this.#pendingConnects[key].push(callback);
      return;
    }

    option.value.connect("changed", callback);
  }

  saveOptions(key, value) {
    const data = Object.keys(this.#options).reduce((acc, key) => {
      acc[key] = this.#options[key].value.value;
      return acc;
    }, {});
    Utils.writeFile(JSON.stringify(data), this.#configPath);
  }
}

const options = new Options();

export const InitializeGlobalDefaults = () => {
  options.registerKey("transition", 200, (value) => typeof value === "number");
};

export default options;
