const Fuse = require("fuse.js");
const { formValues, preventDefault } = require("./forms");
const { getBookmarks, subscribeBookmarks } = require("./bookmarks");
const { getShortcuts, subscribeShortcuts } = require("./shortcuts");

const searchEverythingContainer = document.querySelector("#search-everything");

const searchInput = document.querySelector("#search-form input[name=search]");
const searchForm = document.querySelector("#search-form");

const getSearchOptions = () =>
  searchEverythingContainer.querySelectorAll(".search-option");

const updateSearchData = () => {
  const bookmarks = flattenData(getBookmarks());
  const shortcuts = flattenData(getShortcuts());

  searchEverythingContainer.innerHTML = [...bookmarks, ...shortcuts]
    .map(
      (data) =>
        `<div class="search-option" data-value="${data.link}" data-title="${data.title}"><h3>${data.title}</h3><h4>${data.link}</h4></div>`
    )
    .join("");

  Array.from(getSearchOptions()).forEach((option) => {
    // when option is hovered, remove hover from all other options and add hover to this option
    option.addEventListener("mouseenter", () => {
      Array.from(getSearchOptions()).forEach((option) =>
        option.classList.remove("hover")
      );
      option.classList.add("hover");
    });

    // when option is clicked, fill the input with the link and submit the form
    option.addEventListener("click", (e) => {
      searchInput.value = option.dataset.value;
      const event = new Event("change", { bubbles: true });
      searchInput.dispatchEvent(event);
      searchForm.dispatchEvent(new Event("submit"));
    });
  });
};

const flattenData = (data) => {
  return data.reduce((result, data) => {
    if (!data.link) {
      return result;
    }

    if (data.children) {
      return [...result, data, ...flattenData(data.children)];
    } else {
      return [...result, data];
    }
  }, []);
};

searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    searchInput.value = "";
    searchInput.focus();
    searchEverythingContainer.classList.remove("show");
    Array.from(getSearchOptions()).forEach((option) =>
      option.classList.remove("hover")
    );
  }

  const options = Array.from(getSearchOptions()).filter(
    (option) => !option.classList.contains("hide")
  );
  if (e.key === "ArrowDown") {
    e.preventDefault();
    if (options.length === 0) {
      return;
    }

    // find the first option that is hovered, hover the next one. if next one doesn't exist, hover the first one
    const hoveredOption = options.find((option) =>
      option.classList.contains("hover")
    );
    if (hoveredOption) {
      const hoveredOptionIndex = options.indexOf(hoveredOption);
      const nextOption = options[hoveredOptionIndex + 1];
      if (nextOption) {
        hoveredOption.classList.remove("hover");
        nextOption.classList.add("hover");
      } else {
        hoveredOption.classList.remove("hover");
        options[0].classList.add("hover");
      }
    } else {
      options[0].classList.add("hover");
    }

    // scroll to the hovered option
    const newHoveredOption = options.find((option) =>
      option.classList.contains("hover")
    );
    if (newHoveredOption) {
      newHoveredOption.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    if (options.length === 0) {
      return;
    }

    // find the first option that is hovered, hover the previous one. if previous one doesn't exist, hover the last one
    const hoveredOption = options.find((option) =>
      option.classList.contains("hover")
    );
    if (hoveredOption) {
      const hoveredOptionIndex = options.indexOf(hoveredOption);
      const previousOption = options[hoveredOptionIndex - 1];
      if (previousOption) {
        hoveredOption.classList.remove("hover");
        previousOption.classList.add("hover");
      } else {
        hoveredOption.classList.remove("hover");
        options[options.length - 1].classList.add("hover");
      }
    } else {
      options[options.length - 1].classList.add("hover");
    }

    // scroll to the hovered option
    const newHoveredOption = options.find((option) =>
      option.classList.contains("hover")
    );
    if (newHoveredOption) {
      newHoveredOption.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
  } else if (e.key === "Enter") {
    if (options.length === 0) {
      return;
    }
    const hoveredOption = options.find((option) =>
      option.classList.contains("hover")
    );
    if (hoveredOption) {
      hoveredOption.click();
    }
  }
});

const debounce = (fn, delay) => {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
};

searchInput.addEventListener(
  "input",
  debounce((e) => {
    const query = e.target.value;
    if (!query) {
      searchEverythingContainer.classList.remove("show");
      return;
    }

    Array.from(getSearchOptions()).forEach((option) =>
      option.classList.remove("hover")
    );

    const options = Array.from(getSearchOptions()).map((option) => ({
      title: option.dataset.title,
      link: option.dataset.value,
      option,
    }));

    const results = searchOptions(query, options);
    Array.from(getSearchOptions()).forEach((option) =>
      results.some(
        (result) =>
          result.title === option.dataset.title &&
          result.link === option.dataset.value
      )
        ? option.classList.remove("hide")
        : option.classList.add("hide")
    );

    if (query && results.length > 0) {
      searchEverythingContainer.classList.add("show");
    }
  }, 200)
);

function searchOptions(query, data) {
  // const options = {
  //   keys: [
  //     { name: "title", weight: 0.7 },
  //     { name: "link", weight: 0.3 },
  //   ],
  //   threshold: 0.5,
  //   shouldSort: true,
  //   includeMatches: true,
  //   ignoreLocation: true,
  //   ignoreFieldNorm: true,
  // };

  // const fuse = new Fuse(data, options);
  // const results = fuse.search(query);

  const results = data.filter((item) => {
    const title = item.title.toLowerCase();
    const link = item.link.toLowerCase();

    if (!link) {
      return false;
    }

    const q = query.toLowerCase();
    return title.includes(q) || link.includes(q);
  });

  const uniqueResults = [];
  results.forEach((result) => {
    if (
      !uniqueResults.some(
        (uniqueResult) =>
          uniqueResult.title === result.title &&
          uniqueResult.link === result.link
      )
    ) {
      uniqueResults.push(result);
    }
  });

  return uniqueResults.slice(0, 10);
}

const search = () => {
  let query = formValues["search-form"].values.search;
  if (!query) {
    return;
  }

  if (isUrl(query)) {
    if (!query.startsWith("http://") && !query.startsWith("https://")) {
      query = "http://" + query;
    }

    const url = new URL(query);
    window.location.href = url;
  } else {
    // search the query in google
    const url = new URL("https://www.google.com/search");
    url.searchParams.set("q", query);
    window.location.href = url;
  }
};

function isUrl(str) {
  // Regular expression to match URLs
  const urlRegex = /^(?:(?:https?|ftp):\/\/)?(?:www\.)?[^\s\/]+\.[^\s\/]+/;
  return urlRegex.test(str);
}

searchForm.addEventListener("submit", preventDefault(search));
searchInput.focus();

subscribeBookmarks(updateSearchData);
subscribeShortcuts(updateSearchData);
