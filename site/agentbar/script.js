const copyButtons = document.querySelectorAll("[data-copy]");

const copyText = async (value) => {
  try {
    await navigator.clipboard.writeText(value);
    return true;
  } catch {
    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.append(textarea);
    textarea.select();
    const copied = document.execCommand("copy");
    textarea.remove();
    return copied;
  }
};

for (const button of copyButtons) {
  button.addEventListener("click", async () => {
    const value = button.getAttribute("data-copy");
    await copyText(value);
    button.classList.add("copied");
    setTimeout(() => button.classList.remove("copied"), 1400);
  });
}

const header = document.querySelector(".site-header");
const updateHeader = () => {
  header.dataset.elevated = String(window.scrollY > 20);
};

updateHeader();
window.addEventListener("scroll", updateHeader, { passive: true });
