(()=>{chrome.tabs.query({active:!0,currentWindow:!0},function(r){var a=document.getElementById("tabs-list");r.forEach(function(e){var n=document.createElement("li"),t=document.createElement("a");t.textContent=e.title,t.setAttribute("href",e.url),t.setAttribute("target","_blank"),n.appendChild(t),a.appendChild(n)})});})();
//# sourceMappingURL=popup.build.js.map
