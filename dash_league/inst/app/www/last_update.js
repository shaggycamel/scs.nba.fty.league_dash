(function () {
  function fmt(el) {
    var d = new Date(el.getAttribute("data-utc"));
    if (isNaN(d.getTime())) return;
    el.textContent =
      "Data updated: " +
      d.toLocaleString(undefined, {
        weekday: "short",
        day: "2-digit",
        month: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
        timeZoneName: "short",
      });
  }

  function scan() {
    document
      .querySelectorAll(".nav-last-update[data-utc]:not([data-fmt])")
      .forEach(function (el) {
        el.setAttribute("data-fmt", "1");
        fmt(el);
      });
  }

  document.addEventListener("DOMContentLoaded", scan);
  new MutationObserver(scan).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
})();
