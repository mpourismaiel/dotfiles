(async () => {
  Hudkit.on("composited-changed", (haveTransparency) => {
    if (!haveTransparency) {
      console.log("Lost transparency support!  Closing.");
      window.close();
    }
  });
})();
