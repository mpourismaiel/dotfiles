(() => {
  const tabs = document.querySelectorAll("[data-tab-container]");
  const forms = document.querySelectorAll("[data-form]");

  const timeState = document.querySelector("#greeting #time-state");
  const date = document.querySelector("#greeting #greeting-info #date");
  const time = document.querySelector("#greeting #greeting-info #time");
  const weather = document.querySelector("#greeting #greeting-info #weather");

  const shortcutsContainer = document.querySelector("#shortcuts");
  const shortcutTemplate = document.querySelector("#shortcut-template");
  const shortcutTemplateWithChildren = document.querySelector(
    "#shortcut-template-with-children"
  );

  const modalBackdrop = document.querySelector("#backdrop");
  const shortcutAddButton = document.querySelector("#shortcuts-add");
  const addShortcutModal = document.querySelector("#add-shortcut-modal");

  const addShortcutModalForm = document.querySelector("#add-shortcut-form");
  const addShortcutModalRelatedForm = document.querySelector(
    "#add-shortcut-form-related"
  );

  const shortcutsDefault = [
    {
      title: "Reddit",
      link: "reddit.com",
      icon: "./icons/reddit.png",
      children: [],
    },
    {
      title: "Github",
      link: "github.com",
      icon: "./icons/github.svg",
      children: [],
    },
    {
      title: "30nama",
      link: "30nama.com",
      icon: "./icons/30nama.ico",
      children: [],
    },
    {
      title: "Youtube",
      link: "youtube.com",
      icon: "./icons/youtube.png",
      children: [],
    },
  ];

  const tabListeners = {};
  Array.from(tabs || []).forEach((tabContainer) => {
    const tabButtons = Array.from(
      tabContainer.querySelectorAll(".tabs button") || []
    );
    const tabs = Array.from(tabContainer.querySelectorAll(".tab") || []);

    tabButtons.forEach((button) => {
      const tab = tabs.find((tab) => tab.dataset.tab === button.dataset.tab);
      if (!tab) {
        console.error("no related tab found", button.dataset.tab, tabContainer);
        return;
      }

      button.addEventListener("click", () => {
        tabButtons.forEach((button) => button.classList.remove("active"));
        button.classList.add("active");
        tabs.forEach((tab) => tab.classList.add("hide"));
        tab.classList.remove("hide");
        tabListeners[tabContainer.dataset.tabContainer]?.[
          button.dataset.tab
        ]?.();
      });
    });
  });

  const listenToTab = (id, tab, fn) => {
    if (!tabListeners[id]) {
      tabListeners[id] = {};
    }

    tabListeners[id][tab] = fn;
  };

  const formValues = {};
  Array.from(forms || []).forEach((form) => {
    const formName = form.id;

    formValues[formName] = { values: {} };
    form.querySelectorAll("input, textarea, select").forEach((input) => {
      formValues[formName].values[input.name] = input.value;
      input.addEventListener("change", (e) => {
        formValues[formName].values[input.name] = e.target.value;
      });
    });

    const defaultValues = { ...formValues[formName].values };
    formValues[formName].reset = () => {
      formValues[formName].values = { ...defaultValues };
    };
  });

  const store = (initial = {}, key) => {
    const subscribers = [];
    let data = initial;

    const memory = localStorage.getItem(key);
    try {
      data = JSON.parse(memory);
      if (!data) {
        throw new Error();
      }
    } catch (err) {
      data = initial;
      localStorage.setItem(key, JSON.stringify(data));
    }

    const emit = () => {
      subscribers.forEach((fn) => fn(data));
    };

    const set = (newData) => {
      data = newData;
      localStorage.setItem(key, JSON.stringify(data));
      emit();
    };

    const get = () => {
      return data;
    };

    const subscribe = (fn) => {
      subscribers.push(fn);
      fn(data);
    };

    return { set, get, subscribe };
  };

  const timeMessages = {
    "19-24": "Good night!",
    "24-3": "Nice night, isn't it?",
    "3-8": "You should be sleeping...",
    "8-12": "Good morning!",
    "12-15": "Lunch time!",
    "15-19": "Nice Evening",
  };

  const timeStates = Object.keys(timeMessages)
    .map((timeRange) => {
      let [start, end] = timeRange.split("-").map((d) => parseInt(d));
      start = start === 24 ? 0 : start;
      const arr = [];
      for (let i = start + 1; i <= end; i++) {
        arr.push(i === 24 ? 0 : i);
      }

      return [timeMessages[timeRange], arr];
    })
    .reduce((tmp, [message, hours]) => {
      hours.forEach((hour) => (tmp[hour] = message));
      return tmp;
    }, {});

  const setTimeState = () => {
    const date = new Date();
    const hour = date.getHours();

    timeState.innerText = timeStates[hour];
  };
  setTimeState();
  setInterval(setTimeState, 60000);

  const dateMap = {
    1: "1st",
    2: "2nd",
    3: "3rd",
  };
  const setDate = () => {
    const d = new Date();
    date.innerHTML = d
      .toLocaleDateString("en-US", {
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric",
      })
      .replace(/,\s\d+$/, "")
      .replace(/(\d+)$/, (substr) => {
        const ret = substr.padStart(2, "0");
        return (ret[0] + (dateMap[ret[1]] || ret[1] + "th")).replace(/^0/, "");
      });
  };

  const setTime = () => {
    const d = new Date();
    const hours = d.getHours().toString().padStart(2, "0");
    const minutes = d.getMinutes().toString().padStart(2, "0");
    time.innerHTML = `${hours}:${minutes}`;
  };

  setDate();
  setTime();
  setInterval(() => {
    setDate();
    setTime();
  }, 1000);

  const {
    get: getShortcuts,
    set: setShortcuts,
    subscribe: subscribeShortcuts,
  } = store(shortcutsDefault, "shortcuts");

  subscribeShortcuts((shortcuts) => {
    shortcutsContainer.innerHTML = "";
    shortcuts.forEach(({ title, link, icon, children }) => {
      if (children.length > 0) {
        shortcutsContainer.innerHTML += shortcutTemplateWithChildren.innerHTML
          .replace(/%title%/g, title)
          .replace(/%link%/g, link.replace(/^https?:\/\//, ""))
          .replace(/%icon%/g, icon)
          .replace(
            /%children%/g,
            children
              .map(
                (child) =>
                  `<a href="${child.link}"><img src="/icons/chevron-right.svg" class="icon" /><span>${child.title}</span></a>`
              )
              .join("")
          );
      } else {
        shortcutsContainer.innerHTML += shortcutTemplate.innerHTML
          .replace(/%title%/g, title)
          .replace(/%link%/g, link.replace(/^https?:\/\//, ""))
          .replace(/%icon%/g, icon);
      }
    });
  });

  const showModal = (modal) => () => {
    modalBackdrop.classList.remove("hide");
    modal.classList.remove("hide");
    modalBackdrop.addEventListener("click", hideModal(modal), { once: true });
  };

  const hideModal = (modal) => () => {
    modalBackdrop.classList.add("hide");
    modal.classList.add("hide");
  };

  const stopPropagation = (fn) => (e) => {
    e.stopPropagation();

    if (fn) {
      fn(e);
    }
  };

  const preventDefault = (fn) => (e) => {
    e.preventDefault();

    if (fn) {
      fn(e);
    }
  };

  shortcutAddButton.addEventListener("click", showModal(addShortcutModal));
  addShortcutModal.addEventListener("click", stopPropagation());

  listenToTab("add-shortcut", "link", () => {
    const shortcutsSelector = document.querySelector("#shortcut-related");
    shortcutsSelector.innerHTML = [
      '<option disabled value=""></option>',
      ...getShortcuts().map(
        ({ title, link }) => `<option value="${link}">${title}</option>`
      ),
    ];
    shortcutsSelector.value = "";
  });

  const addShortcut =
    (mode = "") =>
    () => {
      const formName =
        mode === "related" ? "add-shortcut-form-related" : "add-shortcut-form";

      const emptyFields = Object.keys(formValues[formName].values).filter(
        (key) => formValues[formName].values[key] === ""
      );
      if (emptyFields.length > 0) {
        emptyFields.forEach((field) => {
          const input = document.querySelector(
            `#${formName} [name="${field}"]`
          );
          input.classList.add("error");
        });
        return;
      }

      if (mode === "related") {
        const shortcuts = getShortcuts();
        const shortcut = shortcuts.find(
          (shortcut) =>
            shortcut.link ===
            formValues["add-shortcut-form-related"].values.parent
        );

        if (!shortcut) {
          throw new Error("Shortcut not found");
        }

        shortcut.children.push(formValues["add-shortcut-form-related"].values);
        setShortcuts(shortcuts);
      } else {
        setShortcuts([
          ...getShortcuts(),
          { ...formValues["add-shortcut-form"].values, children: [] },
        ]);
      }

      formValues["add-shortcut-form-related"].reset();
      formValues["add-shortcut-form"].reset();
      hideModal(addShortcutModal)();
    };

  addShortcutModalForm.addEventListener(
    "submit",
    preventDefault(addShortcut())
  );
  addShortcutModalRelatedForm.addEventListener(
    "submit",
    preventDefault(addShortcut("related"))
  );
})();
