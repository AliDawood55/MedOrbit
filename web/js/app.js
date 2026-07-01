import { initI18n, setLang, getLang, t } from "./i18n.js";
import { api } from "./api.js";

const views = ["home", "doctors", "login", "register"];

function showView(name) {
  views.forEach((v) => {
    document.getElementById(`view-${v}`).classList.toggle("hidden", v !== name);
  });
  if (name === "doctors") loadDoctors();
}

function route() {
  const hash = location.hash.replace("#", "") || "home";
  showView(views.includes(hash) ? hash : "home");
}

async function loadDoctors() {
  const list = document.getElementById("doctor-list");
  const empty = document.getElementById("doctors-empty");
  try {
    const search = document.getElementById("doctor-search").value;
    const specialtyId = document.getElementById("specialty-filter").value;
    const params = {};
    if (search) params.search = search;
    if (specialtyId) params.specialtyId = specialtyId;
    const { doctors } = await api.listDoctors(params);
    list.innerHTML = "";
    empty.classList.toggle("hidden", doctors.length > 0);
    const lang = getLang();
    doctors.forEach((d) => {
      const card = document.createElement("div");
      card.className = "card";
      const specialty = lang === "ar" ? d.specialty_ar : d.specialty_en;
      card.innerHTML = `
        <h3></h3>
        <p class="specialty"></p>
        <p class="meta">★ ${d.avg_rating} (${d.rating_count}) · ${d.years_of_experience} ${t("doctors.experience")}</p>
        <p class="meta">${t("doctors.fee")}: ${d.consultation_fee}</p>`;
      card.querySelector("h3").textContent = d.full_name;
      card.querySelector(".specialty").textContent = specialty || "";
      list.appendChild(card);
    });
  } catch {
    empty.textContent = t("error.generic");
    empty.classList.remove("hidden");
  }
}

async function loadSpecialties() {
  const select = document.getElementById("specialty-filter");
  select.innerHTML = `<option value="">${t("doctors.allSpecialties")}</option>`;
  try {
    const specialties = await api.listSpecialties();
    const lang = getLang();
    specialties.forEach((s) => {
      const opt = document.createElement("option");
      opt.value = s.id;
      opt.textContent = lang === "ar" ? s.name_ar : s.name_en;
      select.appendChild(opt);
    });
  } catch {
    // gateway not reachable; filter stays empty
  }
}

function setupForms() {
  document.getElementById("login-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const errEl = document.getElementById("login-error");
    errEl.classList.add("hidden");
    const data = Object.fromEntries(new FormData(e.target));
    try {
      const res = await api.login(data);
      localStorage.setItem("medorbit.accessToken", res.accessToken);
      localStorage.setItem("medorbit.refreshToken", res.refreshToken);
      location.hash = "#home";
    } catch (err) {
      errEl.textContent = err.body?.error || t("error.generic");
      errEl.classList.remove("hidden");
    }
  });

  document.getElementById("register-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const errEl = document.getElementById("register-error");
    const okEl = document.getElementById("register-success");
    errEl.classList.add("hidden");
    okEl.classList.add("hidden");
    const data = Object.fromEntries(new FormData(e.target));
    data.preferredLanguage = getLang();
    try {
      await api.register(data);
      okEl.textContent = t("register.success");
      okEl.classList.remove("hidden");
      e.target.reset();
    } catch (err) {
      errEl.textContent = (err.body?.errors || [err.body?.error || t("error.generic")]).join("; ");
      errEl.classList.remove("hidden");
    }
  });
}

async function main() {
  await initI18n();
  await loadSpecialties();

  document.getElementById("lang-toggle").addEventListener("click", async () => {
    await setLang(getLang() === "ar" ? "en" : "ar");
    await loadSpecialties();
    if (!document.getElementById("view-doctors").classList.contains("hidden")) loadDoctors();
  });

  document.getElementById("doctor-search").addEventListener("input", debounce(loadDoctors, 300));
  document.getElementById("specialty-filter").addEventListener("change", loadDoctors);

  setupForms();
  window.addEventListener("hashchange", route);
  route();
}

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

main();
