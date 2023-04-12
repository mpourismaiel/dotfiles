chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
  var tabsList = document.getElementById("tabs-list");

  tabs.forEach(function (tab) {
    var listItem = document.createElement("li");
    var link = document.createElement("a");

    link.textContent = tab.title;
    link.setAttribute("href", tab.url);
    link.setAttribute("target", "_blank");

    listItem.appendChild(link);
    tabsList.appendChild(listItem);
  });
});
