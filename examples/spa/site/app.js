function render() { document.getElementById("route").textContent = "Rota: " + location.pathname; }
document.addEventListener("click", (event) => { const link = event.target.closest("a"); if (!link || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button) return; event.preventDefault(); history.pushState({}, "", link.href); render(); });
window.addEventListener("popstate", render); render();
