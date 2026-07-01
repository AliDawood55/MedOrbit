const dictionaries = {};
let currentLang = localStorage.getItem("medorbit.lang") || "en";

export function getLang() {
  return currentLang;
}

export function t(key) {
  return dictionaries[currentLang]?.[key] ?? key;
}

async function loadDictionary(lang) {
  if (!dictionaries[lang]) {
    const res = await fetch(`i18n/${lang}.json`);
    dictionaries[lang] = await res.json();
  }
}

export function applyTranslations() {
  document.documentElement.lang = currentLang;
  document.documentElement.dir = currentLang === "ar" ? "rtl" : "ltr";
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  document.querySelectorAll("[data-i18n-placeholder]").forEach((el) => {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
  const toggle = document.getElementById("lang-toggle");
  if (toggle) toggle.textContent = currentLang === "ar" ? "English" : "العربية";
}

export async function setLang(lang) {
  await loadDictionary(lang);
  currentLang = lang;
  localStorage.setItem("medorbit.lang", lang);
  applyTranslations();
  document.dispatchEvent(new CustomEvent("langchange", { detail: { lang } }));
}

export async function initI18n() {
  await loadDictionary(currentLang);
  applyTranslations();
}
