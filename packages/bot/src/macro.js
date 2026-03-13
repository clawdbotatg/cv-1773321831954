import { config } from "./config.js";

// FRED API integration for macro data
const FRED_BASE_URL = "https://api.stlouisfed.org/fred/series/observations";

async function fetchFredSeries(seriesId, limit = 1) {
  if (!config.fredApiKey) return null;
  const url = `${FRED_BASE_URL}?series_id=${seriesId}&api_key=${config.fredApiKey}&file_type=json&sort_order=desc&limit=${limit}`;
  try {
    const res = await fetch(url);
    const data = await res.json();
    return data.observations?.[0];
  } catch (e) {
    console.error(`FRED fetch error for ${seriesId}:`, e.message);
    return null;
  }
}

export async function getCPI() {
  const obs = await fetchFredSeries("CPIAUCSL");
  return obs ? { value: obs.value, date: obs.date } : null;
}

export async function getFedFundsRate() {
  const obs = await fetchFredSeries("FEDFUNDS");
  return obs ? { value: obs.value, date: obs.date } : null;
}

export async function getM2MoneySupply() {
  const obs = await fetchFredSeries("M2SL");
  return obs ? { value: obs.value, date: obs.date } : null;
}

export async function getUSDebt() {
  const obs = await fetchFredSeries("GFDEBTN");
  return obs ? { value: obs.value, date: obs.date } : null;
}

export async function getAllMacroData() {
  const [cpi, ffr, m2, debt] = await Promise.all([
    getCPI(),
    getFedFundsRate(),
    getM2MoneySupply(),
    getUSDebt(),
  ]);
  return { cpi, fedFundsRate: ffr, m2MoneySupply: m2, usDebt: debt };
}

// FOMC Calendar (pre-loaded 2026 dates)
const FOMC_DATES_2026 = [
  "2026-01-27", "2026-01-28",
  "2026-03-17", "2026-03-18",
  "2026-05-05", "2026-05-06",
  "2026-06-16", "2026-06-17",
  "2026-07-28", "2026-07-29",
  "2026-09-15", "2026-09-16",
  "2026-11-03", "2026-11-04",
  "2026-12-15", "2026-12-16",
];

export function isFOMCDay() {
  const today = new Date().toISOString().slice(0, 10);
  return FOMC_DATES_2026.includes(today);
}

export function nextFOMCDate() {
  const today = new Date().toISOString().slice(0, 10);
  return FOMC_DATES_2026.find(d => d >= today) || "2027-TBD";
}
