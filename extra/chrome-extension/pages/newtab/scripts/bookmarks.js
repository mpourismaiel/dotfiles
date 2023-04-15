const store = require("./store");

const bookmarksContainer = document.querySelector("#bookmarks");
const bookmarksEmptyTemplate = document.querySelector(
  "#bookmarks-template-empty"
);
const bookmarkTemplate = document.querySelector("#bookmark-template");
const bookmarkTemplateWithChildren = document.querySelector(
  "#bookmark-template-with-children"
);

const {
  get: getBookmarks,
  set: setBookmarks,
  subscribe: subscribeBookmarks,
} = store([], "bookmarks");

setTimeout(() => {
  chrome.bookmarks.getTree(function (bookmarkTreeNodes) {
    let bookmarks = getAllBookmarks(bookmarkTreeNodes);
    // if first level of bookmarks all contain children and have no title, remove the first level and make concat their children into a new array
    if (bookmarks.every((bookmark) => bookmark.children && !bookmark.title)) {
      bookmarks = bookmarks.reduce((acc, bookmark) => {
        return [...acc, ...bookmark.children];
      }, []);
    }

    setBookmarks(bookmarks);
  });
}, 1000);

subscribeBookmarks(
  (bookmarks) => (bookmarksContainer.innerHTML = renderBookmarks(bookmarks))
);

function renderBookmarks(bookmarks) {
  if (!bookmarks) return "";

  if (bookmarks.length === 0) return bookmarksEmptyTemplate.innerHTML;

  return bookmarks
    .map((bookmark) => {
      if (bookmark.children === null) {
        return bookmarkTemplate.innerHTML
          .replace(/%title%/g, bookmark.title)
          .replace(/%link%/g, bookmark.link)
          .replace(/%icon%/g, bookmark.iconUrl);
      } else {
        return bookmarkTemplateWithChildren.innerHTML
          .replace(/%title%/g, bookmark.title)
          .replace(/%children%/g, renderBookmarks(bookmark.children));
      }
    })
    .join("");
}

function getAllBookmarks(nodes) {
  return nodes.map(function (node) {
    if (node.url) {
      return {
        id: node.id,
        title: node.title,
        link: node.url.startsWith("http") ? node.url : "http://" + node.url,
        iconUrl:
          "https://s2.googleusercontent.com/s2/favicons?domain=" + node.url,
        children: null,
      };
    } else if (node.children) {
      return {
        title: node.title,
        id: node.id,
        children: getAllBookmarks(node.children),
      };
    }
  });
}

module.exports = { getBookmarks, setBookmarks, subscribeBookmarks };
