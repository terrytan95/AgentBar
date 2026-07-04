const copyButtons = document.querySelectorAll("[data-copy]");

for (const button of copyButtons) {
  button.addEventListener("click", async () => {
    const value = button.getAttribute("data-copy");
    try {
      await navigator.clipboard.writeText(value);
      button.classList.add("copied");
      setTimeout(() => button.classList.remove("copied"), 1400);
    } catch {
      button.classList.remove("copied");
    }
  });
}

const header = document.querySelector(".site-header");
const updateHeader = () => {
  header.dataset.elevated = String(window.scrollY > 20);
};

updateHeader();
window.addEventListener("scroll", updateHeader, { passive: true });
