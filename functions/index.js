/* eslint-disable */

// functions/index.js

// ========== V2 Firestore & Options & Admin ==========
const {
  onDocumentCreated,
  onDocumentWritten,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2/options");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, FieldPath, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");

// ========== V1 functions (config için) ==========
const functions = require("firebase-functions");

// ✅ CV parse deps
const pdfParseMod = require("pdf-parse");
const pdfParse = typeof pdfParseMod === "function" ? pdfParseMod : pdfParseMod.default;
const crypto = require("crypto");

// ✅ fetch fallback (Node 18+ has global fetch)
const fetchFn =
  typeof fetch === "function"
    ? fetch
    : (...args) => import("node-fetch").then(({ default: f }) => f(...args));

// Firebase Admin init
initializeApp();

// Tüm fonksiyonlar için default region
setGlobalOptions({ region: "europe-west1" });

/* =========================================================
   UTILS (Normalize / Alias / Helpers)
   ========================================================= */

function safeStr(x) {
  return x == null ? "" : String(x);
}

function uniq(arr) {
  return Array.from(new Set((arr || []).filter(Boolean)));
}

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < (arr || []).length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

// ✅ hash helpers
function sha256Buf(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}
function randomId16() {
  return crypto.randomBytes(8).toString("hex");
}

/**
 * Skill normalizer
 * - lower
 * - TR normalize
 * - alias map
 * - punctuation cleanup
 */
function normSkill(s) {
  if (!s) return "";
  let x = String(s).trim().toLowerCase();

  // TR karakter normalize
  x = x
    .replaceAll("ı", "i")
    .replaceAll("İ", "i")
    .replaceAll("ş", "s")
    .replaceAll("Ş", "s")
    .replaceAll("ğ", "g")
    .replaceAll("Ğ", "g")
    .replaceAll("ü", "u")
    .replaceAll("Ü", "u")
    .replaceAll("ö", "o")
    .replaceAll("Ö", "o")
    .replaceAll("ç", "c")
    .replaceAll("Ç", "c");

  x = x.replace(/\s+/g, " ").trim();

  // bullet/garip ayraçlar
  x = x.replace(/[•·]/g, " ");

  // alias map (MVP+)
  const alias = {
    "c#": "csharp",
    "c sharp": "csharp",
    "c-sharp": "csharp",
    js: "javascript",
    "java script": "javascript",
    node: "nodejs",
    "node.js": "nodejs",
    "express.js": "express",
    ts: "typescript",
    "react js": "react",
    "react.js": "react",
    "next js": "nextjs",
    "next.js": "nextjs",
    "asp.net": "aspnet",
    "asp net": "aspnet",
    dotnet: "dotnet",
    ".net": "dotnet",
    "firebase firestore": "firebase",
    "google firebase": "firebase",

    // REST normalize
    "rest api": "restapi",
    "rest-api": "restapi",
    "restful api": "restapi",
    restful: "restapi",
    "restful servisler": "restapi",
    "restful services": "restapi",
    "restful servis": "restapi",
    "rest servisleri": "restapi",
    "rest servisler": "restapi",
    "rest servisleri": "restapi",
    "rest servisleri": "restapi",

    // multiword normalize
    "machine learning": "machinelearning",
    "deep learning": "deeplearning",

    // common multiword tech
    "spring boot": "springboot",
    "react native": "reactnative",
    "unit testing": "unittesting",
    "test automation": "testautomation",
    "ci/cd": "cicd",
    "ci cd": "cicd",
  };

  if (alias[x]) x = alias[x];

  // nokta vs temizle
  x = x.replace(/\./g, "");
  x = x.replace(/[()]/g, " ");
  x = x.replace(/\s+/g, " ").trim();

  // çok kısa / çöp
  if (x.length < 2) return "";
  return x;
}

// Çok genel skill’leri elemek için stoplist (SADECE SEED / DISCOVERY)
const STOP_SKILLS = new Set(["html", "css", "sql", "office", "word", "excel", "powerpoint"]);
function pickDiscriminativeSkills(skillsNorm, max = 5) {
  const filtered = (skillsNorm || []).filter((s) => s && !STOP_SKILLS.has(s));
  return filtered.slice(0, max);
}

/* =========================================================
   ✅ SKILL SANITIZE (TIRT çöpleri ayıkla)
   ========================================================= */

/**
 * Burada STOP_SKILLS kullanmıyoruz.
 * Çünkü match engine'de "sql" required olabilir.
 */
function isProbablyRealSkillToken(norm) {
  if (!norm) return false;

  // Çok uzun "cümle" gibi olanları at
  if (norm.length > 34) return false;

  // İzin verdiğimiz karakterler (multiword için boşluk da izinli)
  if (!/^[a-z0-9+#/\- ]+$/.test(norm)) return false;

  // Çok fazla kelime -> cümle olma ihtimali
  const parts = norm.split(" ").filter(Boolean);
  if (parts.length > 2) return false;

  // Multiword ise her kelime kısa olmalı
  if (parts.length === 2) {
    if (parts[0].length < 2 || parts[1].length < 2) return false;
    if (parts[0].length > 16 || parts[1].length > 16) return false;
  }

  return true;
}

function sanitizeNormalizedSkills(arr) {
  const list = uniq((arr || []).map(normSkill)).filter(Boolean);
  return list.filter(isProbablyRealSkillToken);
}

/* =========================================================
   SKILL SOURCES (manual/cv/effective)
   ========================================================= */

function getUserSkillsManual(afterUser) {
  // Backward compat:
  // Eski sistem: user.skills vardı. Yeni sistem: user.skillsManual.
  const manual = Array.isArray(afterUser?.skillsManual)
    ? afterUser.skillsManual
    : Array.isArray(afterUser?.skills)
      ? afterUser.skills
      : [];
  return sanitizeNormalizedSkills(manual);
}

function getUserSkillsFromCv(afterUser) {
  const cv = Array.isArray(afterUser?.skillsFromCv) ? afterUser.skillsFromCv : [];
  return sanitizeNormalizedSkills(cv);
}

function computeSkillsEffective({ manual, fromCv }) {
  // CV skill'leri tam ağırlıkla "var" sayılacaksa burada birleşir.
  // İstersen ileride "cvWeight" gibi bir yapı kurarsın.
  return sanitizeNormalizedSkills([...(manual || []), ...(fromCv || [])]);
}

/* =========================================================
   CV text helpers (MVP)
   ========================================================= */

function cleanText(t) {
  return safeStr(t)
    .replace(/\u0000/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\r/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
function pickFirstEmail(text) {
  const m = safeStr(text).match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
  return m ? m[0] : "";
}
function pickFirstPhone(text) {
  const t = safeStr(text);
  const m =
    t.match(/(\+?\d{1,3}[\s-]?)?(\(?\d{3}\)?[\s-]?)\d{3}[\s-]?\d{2}[\s-]?\d{2}/) ||
    t.match(/\+?\d[\d\s-]{8,}\d/);
  return m ? m[0] : "";
}

/* =========================================================
   CV SECTION SPLIT + SKILL SEED EXTRACTION
   ========================================================= */

function normalizeForHeading(s) {
  return safeStr(s)
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s-]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const SECTION_ALIASES = [
  { key: "summary", heads: ["ozet", "ozetim", "profil", "hakkimda", "about", "summary", "profile", "professional summary"] },

  { key: "skills", heads: [
    "beceriler", "yetenekler", "skills", "teknolojiler", "technologies", "technical skills",
    "teknik yetenekler", "teknik beceriler", "uzmanliklar", "skill set", "skillset"
  ] },

  { key: "experience", heads: ["deneyim", "is deneyimi", "work experience", "experience", "employment", "kariyer", "staj", "internship"] },

  { key: "education", heads: ["egitim", "education", "akademik", "university", "universite", "lisans", "yuksek lisans"] },

  { key: "projects", heads: ["projeler", "projelerim", "projects", "project experience", "personal projects"] },

  { key: "certificates", heads: ["sertifikalar", "sertifika", "certifications", "certificates", "courses", "kurslar"] },

  { key: "languages", heads: ["diller", "languages", "language"] },

  { key: "links", heads: ["iletisim", "iletisim bilgileri", "contact", "links", "baglantilar", "linkedin", "github", "portfolio", "web sitesi"] },
];

function detectSectionKeyFromLine(line) {
  const n = normalizeForHeading(line);
  if (!n) return null;

  for (const s of SECTION_ALIASES) {
    for (const h of s.heads) {
      if (n === h) return s.key;
      if (n.startsWith(h + " ")) return s.key;
      if (n.includes(" " + h + " ")) return s.key;
    }
  }
  return null;
}

function detectInlineHeading(line) {
  const raw = safeStr(line).trim();
  if (!raw) return null;

  const m = raw.match(/^(.{2,45}?)(\s*[:\-—–|]\s*)(.+)$/);
  if (!m) return null;

  const headPart = m[1].trim();
  const rest = m[3].trim();
  if (headPart.length > 45) return null;

  const key = detectSectionKeyFromLine(headPart);
  if (!key) return null;

  return { key, rest: rest || "" };
}

function splitCvIntoSections(text) {
  const lines = safeStr(text).split("\n").map((l) => l.trim()).filter(Boolean);

  const sections = {};
  let current = "other";
  sections[current] = [];

  for (const line of lines) {
    const inline = detectInlineHeading(line);
    if (inline?.key) {
      current = inline.key;
      if (!sections[current]) sections[current] = [];
      if (inline.rest) sections[current].push(inline.rest);
      continue;
    }

    const isShortish = line.length <= 70;
    const key = isShortish ? detectSectionKeyFromLine(line) : null;

    if (key) {
      current = key;
      if (!sections[current]) sections[current] = [];
      continue;
    }

    sections[current].push(line);
  }

  const out = {};
  for (const [k, arr] of Object.entries(sections)) {
    const joined = arr.join("\n").trim();
    if (joined) out[k] = joined;
  }

  return out;
}

function capStr(s, n) {
  const x = safeStr(s);
  return x.length > n ? x.slice(0, n) : x;
}

function extractSkillsSeed({ sections, fullText }) {
  const candidates = [];

  const skillsText = safeStr(sections?.skills);
  if (skillsText) candidates.push(...skillsText.split("\n"));

  const t = safeStr(fullText);
  const lines = t.split("\n").map((x) => x.trim()).filter(Boolean);

  for (const line of lines) {
    const lower = normalizeForHeading(line);

    const inline = detectInlineHeading(line);
    if (inline?.key === "skills" && inline.rest) {
      candidates.push(inline.rest);
      continue;
    }

    const hasCommaList = /,/.test(line) && line.length <= 140;
    const hasBulletList = /[•·]/.test(line);
    const hasPipeList = /\s\|\s/.test(line) && line.length <= 140;

    const mentionsSkillWord = lower.includes("skills") || lower.includes("beceri") || lower.includes("teknoloji");

    if (mentionsSkillWord && line.length <= 180) candidates.push(line);

    if (hasCommaList || hasBulletList || hasPipeList) {
      if (lower.includes("@") || lower.includes("http") || lower.includes("www")) continue;
      if (line.split(",").length >= 2 || hasBulletList || hasPipeList) candidates.push(line);
    }
  }

  const rawTokens = [];
  for (const c of candidates) {
    const s = safeStr(c);

    const parts = s
      .replace(/[•·]/g, ",")
      .replace(/\s\|\s/g, ",")
      .replace(/\s-\s/g, ",")
      .split(",");

    for (const p of parts) {
      const tok = p.trim();
      if (!tok) continue;
      if (tok.length > 48) continue;
      rawTokens.push(tok);
    }
  }

  const normalized = uniq(rawTokens.map(normSkill))
    .filter(Boolean);

  // seed fazla şişmesin
  return normalized.slice(0, 25);
}

/* =========================================================
   ✅ CV QUALITY GATE (JUNIOR-FRIENDLY)
   ========================================================= */

function computeGarbageRatio(text) {
  if (!text) return 1;
  const garbageMatches = safeStr(text).match(/[�□�]/g);
  const garbageCount = garbageMatches ? garbageMatches.length : 0;
  const len = safeStr(text).length || 1;
  return garbageCount / len;
}

function evaluateCvQuality({ text, sections, emailInCv, phoneInCv }) {
  const t = safeStr(text);
  const lines = t.split("\n").map((x) => x.trim()).filter(Boolean);

  const lineCount = lines.length;
  const avgLineLen = lineCount ? Math.round(lines.reduce((a, b) => a + b.length, 0) / lineCount) : 0;

  const textLen = t.length;
  const garbageRatio = computeGarbageRatio(t);

  const sectionKeys = sections ? Object.keys(sections) : [];
  const hasSkillsSection = sectionKeys.includes("skills");
  const hasExperienceSection = sectionKeys.includes("experience");
  const hasEducationSection = sectionKeys.includes("education");
  const hasSummarySection = sectionKeys.includes("summary");

  const hasEmail = !!safeStr(emailInCv).trim();
  const hasPhone = !!safeStr(phoneInCv).trim();

  const flags = [];

  if (textLen < 450) flags.push("TEXT_TOO_SHORT");
  if (lineCount >= 260 && avgLineLen <= 14) flags.push("MANY_SHORT_LINES");
  if (avgLineLen <= 10 && lineCount >= 140) flags.push("VERY_SHORT_LINES");
  if (garbageRatio >= 0.006) flags.push("GARBLED_TEXT");
  if (!hasEmail && !hasPhone) flags.push("NO_CONTACT_FOUND");

  if (!hasSkillsSection && !hasEducationSection && !hasExperienceSection && !hasSummarySection) {
    flags.push("NO_SECTIONS_DETECTED");
  }

  const isBad = flags.length >= 3;

  let reason = flags[0] || "UNKNOWN";
  if (flags.includes("GARBLED_TEXT")) reason = "GARBLED_TEXT";
  else if (flags.includes("NO_CONTACT_FOUND")) reason = "NO_CONTACT_FOUND";
  else if (flags.includes("NO_SECTIONS_DETECTED")) reason = "NO_SECTIONS_DETECTED";
  else if (flags.includes("TEXT_TOO_SHORT")) reason = "TEXT_TOO_SHORT";
  else if (flags.includes("VERY_SHORT_LINES")) reason = "VERY_SHORT_LINES";
  else if (flags.includes("MANY_SHORT_LINES")) reason = "MANY_SHORT_LINES";

  return {
    isBad,
    reason,
    flags,
    metrics: {
      textLen,
      lineCount,
      avgLineLen,
      garbageRatio: Number(garbageRatio.toFixed(6)),
      sectionKeys,
      hasEmail,
      hasPhone,
    },
  };
}

/* =========================================================
   OpenAI JSON
   ========================================================= */

const CV_ANALYZE_SYSTEM = `
Sen TechConnect uygulaması için çalışan bir CV değerlendirme motorusun.

ÇIKTI DİLİ: TÜRKÇE (ZORUNLU)
- Ürettiğin tüm string alanlar %100 Türkçe olacak.
- İngilizce kelime, cümle, başlık KULLANMA.
- Teknik terimler (ATS, CV, Backend, API gibi) korunabilir ama açıklamalar Türkçe olacak.

AMAÇ:
Kullanıcıya bilgilendirici, yapıcı ve öğretici bir
"CV Yeterlilik + ATS Uyumluluk" raporu sunmak.

KURALLAR:
- SADECE JSON döndür. Açıklama, markdown, kod bloğu yok.
- Uydurma bilgi ekleme. CV’de yoksa null veya [] kullan.
- Skorlar 0–100 arası olmalı.
- ATS uyumluluğunu format, başlıklar, okunabilirlik ve anahtar kelime netliği üzerinden değerlendir.
- "missingSections" yalnızca gerçekten eksik olan bölümleri içermeli.
- Öneriler net, uygulanabilir ve kısa olsun.

JSON ŞEMASI:
{
  "overallScore": number,
  "parseQuality": "good|bad|unknown",

  "ats": {
    "compatScore": number,
    "level": "poor|ok|good|excellent",
    "blockingIssues": ["string"],
    "warnings": ["string"],
    "quickFixes": ["string"]
  },

  "strengths": ["string"],
  "gaps": ["string"],

  "missingSections": ["summary","skills","experience","education","projects","links","certificates","languages"],

  "contentImprovements": {
    "summaryRewrite": "string|null",
    "skillsCleanup": ["string"],
    "experienceFixes": ["string"],
    "projectFixes": ["string"]
  },

  "bulletFixes": [
    {
      "section": "experience|projects|other",
      "before": "string",
      "after": "string"
    }
  ],

  "actionPlan": [
    {
      "title": "string",
      "priority": "high|medium|low",
      "steps": ["string"]
    }
  ],

  "roleFit": {
    "targetRole": "string|null",
    "fitScore": number,
    "why": ["string"],
    "missingSkills": ["string"],
    "nextSteps": ["string"]
  }
}
`.trim();


async function callOpenAiJson({ apiKey, userMessage }) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), 15000);

  try {
    const resp = await fetchFn("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.2,
        max_tokens: 700,
        messages: [
          { role: "system", content: CV_SYSTEM },
          { role: "user", content: userMessage },
        ],
      }),
    });

    if (!resp.ok) {
      const txt = await resp.text().catch(() => "");
      throw new Error(`OPENAI_HTTP_${resp.status} ${txt.slice(0, 200)}`);
    }

    const data = await resp.json().catch(() => null);
    const raw = data?.choices?.[0]?.message?.content || "";
    const trimmed = String(raw).trim();
    if (!trimmed) throw new Error("OPENAI_EMPTY_RESPONSE");

    const jsonText = trimmed.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
    return JSON.parse(jsonText);
  } finally {
    clearTimeout(t);
  }
}

function getOpenAiApiKey() {
  let cfg = {};
  try {
    cfg = functions.config ? functions.config() : {};
  } catch (_) {}
  return (cfg.openai && cfg.openai.key) || process.env.OPENAI_API_KEY || "";
}

function getOpenAiCvAnalyzeKey() {
  const key =
    process.env.OPENAI_API_CV_ANALYZE ||
    process.env.OPENAI_API_KEY || // fallback (istersen sonra kaldırırsın)
    "";

  return key && String(key).trim() ? String(key).trim() : null;
}


/* =========================================================
   CV AI RATE LIMIT (user başı günlük 3)
   collection: cvAiUsage/{uid}
   ========================================================= */

async function enforceCvAiDailyLimit(uid) {
  const db = getFirestore();
  const ref = db.collection("cvAiUsage").doc(uid);

  const PER_DAY = 3;

  const now = new Date();
  const dayBucket = `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, "0")}${String(
    now.getUTCDate()
  ).padStart(2, "0")}`;

  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.exists ? snap.data() || {} : {};

    const dayKey = d.dayBucket || "";
    const dayCount = dayKey === dayBucket ? Number(d.dayCount || 0) : 0;

    if (dayCount >= PER_DAY) throw Object.assign(new Error("CV_AI_DAILY_LIMIT"), { status: 429 });

    tx.set(
      ref,
      {
        dayBucket,
        dayCount: dayCount + 1,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { dayLeft: PER_DAY - (dayCount + 1) };
  });
}

/* =========================================================
   GEO / SCORE ENGINE
   ========================================================= */

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return R * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
}

function normWorkModel(x) {
  const t = safeStr(x).trim().toLowerCase();
  if (!t) return "";
  if (t === "onsite" || t === "on site" || t === "on_site") return "on-site";
  if (t === "on-site") return "on-site";
  if (t === "remote") return "remote";
  if (t === "hybrid") return "hybrid";
  if (t === "any") return "any";
  return t;
}

// LEVEL gate
const LEVEL_RANK = { intern: 0, junior: 1, mid: 2, senior: 3 };

function normLevel(x) {
  const t = safeStr(x).trim().toLowerCase();
  if (!t) return "";
  if (t === "jr") return "junior";
  if (t === "sr") return "senior";
  return t;
}
function levelRank(levelStr) {
  const l = normLevel(levelStr);
  return Object.prototype.hasOwnProperty.call(LEVEL_RANK, l) ? LEVEL_RANK[l] : null;
}
function isLevelEligible(userLevelStr, jobLevelStr) {
  const u = levelRank(userLevelStr);
  const j = levelRank(jobLevelStr);
  if (j == null) return true;
  if (u == null) return true; // MVP
  return u >= j;
}

function isWorkModelEligible(user, jobWorkModel) {
  const jobW = normWorkModel(jobWorkModel);
  if (!jobW || jobW === "any") return true;

  const prefs = user?.workModelPrefs || {};
  const r = prefs.remote === true;
  const h = prefs.hybrid === true;
  const o = prefs["on-site"] === true || prefs.onsite === true;

  if (jobW === "remote") return r;
  if (jobW === "hybrid") return h;
  if (jobW === "on-site") return o;
  return false;
}

/* =========================================================
   ✅ DISPLAY SCORE + CONFIDENCE (User-only hype, ranking-safe)
   ========================================================= */

function getUserSkillSets(user) {
  const manual = sanitizeNormalizedSkills(
    Array.isArray(user?.skillsManual) ? user.skillsManual : Array.isArray(user?.skills) ? user.skills : []
  );
  const fromCv = sanitizeNormalizedSkills(Array.isArray(user?.skillsFromCv) ? user.skillsFromCv : []);
  const effective = sanitizeNormalizedSkills(
    Array.isArray(user?.skillsEffective) ? user.skillsEffective : [...manual, ...fromCv]
  );

  return {
    manualSet: new Set(manual),
    cvSet: new Set(fromCv),
    effectiveSet: new Set(effective),
    manual,
    fromCv,
    effective,
  };
}

function computeConfidenceFromEvidence({ matchedReq, manualSet, cvSet, user }) {
  const m = matchedReq || [];
  const total = m.length || 1;

  let manualHits = 0;
  let cvHits = 0;

  for (const sk of m) {
    if (manualSet.has(sk)) manualHits++;
    else if (cvSet.has(sk)) cvHits++;
  }

  const manualHitRatio = manualHits / total; // 0..1
  let confidenceScore = 0.6;
  let badge = "low";

  if (manualHitRatio >= 0.7) {
    confidenceScore = 1.0;
    badge = "high";
  } else if (manualHitRatio >= 0.35) {
    confidenceScore = 0.8;
    badge = "medium";
  }

  // CV parse kalitesi kötüyse ekstra düşür (opsiyonel ama mantıklı)
  const cvQuality = safeStr(user?.cvParseQuality).trim().toLowerCase();
  if (cvQuality === "bad" && confidenceScore > 0.6) {
    confidenceScore = 0.6;
    badge = "low";
  }

  return {
    confidenceScore,
    confidenceBadge: badge,
    confidenceDetails: {
      manualHits,
      cvHits,
      manualHitRatio: Number(manualHitRatio.toFixed(3)),
      cvParseQuality: cvQuality || "unknown",
    },
  };
}

function toDisplayScore(rawScore) {
  const s = clamp(Math.round(rawScore), 0, 100);

  // Piecewise monotonic calibration (sıralama bozulmaz)
  // Ama üst banda daha agresif “95 hissi” verir.
  if (s >= 80) return clamp(Math.round(92 + ((s - 80) / 20) * 7), 92, 99);   // 80..100 -> 92..99
  if (s >= 60) return clamp(Math.round(75 + ((s - 60) / 20) * 16), 75, 91);  // 60..79 -> 75..91
  if (s >= 35) return clamp(Math.round(55 + ((s - 35) / 25) * 19), 55, 74);  // 35..59 -> 55..74
  return clamp(Math.round((s / 35) * 54), 0, 54);                            // 0..34 -> 0..54
}

/**
 * ✅ Match Engine artık TEK KAYNAK kullanır: skillsEffective
 * (backward compat: skillsEffective yoksa manual/skills'ten üretir)
 */
function getSkillsEffectiveFromUser(user) {
  const eff = Array.isArray(user?.skillsEffective) ? user.skillsEffective : null;
  if (eff && eff.length) return sanitizeNormalizedSkills(eff);

  // fallback
  const manual = getUserSkillsManual(user);
  const fromCv = getUserSkillsFromCv(user);
  return computeSkillsEffective({ manual, fromCv });
}

function computeMatchEngine({ user, job }) {
  if (!user || !job) return null;
  if (user.active === false) return null;
  if (job.isActive !== true) return null;

  // 1) Work model gate
  if (!isWorkModelEligible(user, job.workModel)) return null;

  // 2) Level gate
  const userLevel = safeStr(user.seniority || user.level || "").trim();
  const jobLevel = safeStr(job.level || "").trim();
  if (!isLevelEligible(userLevel, jobLevel)) return null;

  // 3) Skills normalize (ONLY effective for eligibility)
  const sets = getUserSkillSets(user);
  const userSet = sets.effectiveSet;

  const requiredSkillsNorm = uniq((job.requiredSkillsNormalized || job.requiredSkills || []).map(normSkill)).filter(Boolean);
  if (requiredSkillsNorm.length === 0) return null;

  const niceSkillsNorm = uniq((job.niceToHaveSkillsNormalized || job.niceToHaveSkills || []).map(normSkill)).filter(Boolean);

  // 4) Required partial match
  const matchedReq = [];
  const missingReq = [];

  for (const sk of requiredSkillsNorm) {
    if (!sk) continue;
    if (userSet.has(sk)) matchedReq.push(sk);
    else missingReq.push(sk);
  }

  const reqRatio = matchedReq.length / requiredSkillsNorm.length;

  if (matchedReq.length < 1) return null;
  if (reqRatio < 0.5) return null;

  // 5) Raw score base 0..80
  let rawScore = Math.round(reqRatio * 80);

  // 6) Nice bonus 0..20
  let niceBonus = 0;
  let matchedNiceSkills = [];
  let missingNiceSkills = [];

  if (niceSkillsNorm.length > 0) {
    matchedNiceSkills = niceSkillsNorm.filter((sk) => userSet.has(sk));
    missingNiceSkills = niceSkillsNorm.filter((sk) => !userSet.has(sk));
    niceBonus = Math.round((matchedNiceSkills.length / niceSkillsNorm.length) * 20);
    rawScore += niceBonus;
  }

  // 7) Mobile bonus
  let mobileBonus = 0;
  const reqSet = new Set(requiredSkillsNorm);
  const hasMobileJob =
    reqSet.has("dart") || reqSet.has("flutter") || niceSkillsNorm.includes("flutter") || niceSkillsNorm.includes("dart");
  const hasNative = userSet.has("kotlin") || userSet.has("swift");
  if (hasMobileJob && hasNative) mobileBonus = 5;
  rawScore += mobileBonus;

  // 8) Bio bonus
  let bioBonus = 0;
  const userBio = safeStr(user.bio).trim().toLowerCase();
  if (userBio) {
    for (const sk of requiredSkillsNorm) {
      if (sk && userBio.includes(sk)) {
        bioBonus = 5;
        break;
      }
    }
  }
  rawScore += bioBonus;

  // 9) GEO bonus + on-site uzak eleme
  let geoBonus = 0;
  let distanceKm = null;

  const jobWork = normWorkModel(job.workModel);
  const uGeo = user.geo || null;
  const jGeo = job.geo || null;

  const hasUGeo = uGeo && uGeo.latitude != null && uGeo.longitude != null;
  const hasJGeo = jGeo && jGeo.latitude != null && jGeo.longitude != null;

  if (jobWork !== "remote" && hasUGeo && hasJGeo) {
    distanceKm = haversineKm(uGeo.latitude, uGeo.longitude, jGeo.latitude, jGeo.longitude);

    if (jobWork === "on-site" && distanceKm > 200) return null;

    if (distanceKm <= 20) geoBonus = 10;
    else if (distanceKm <= 50) geoBonus = 5;
    else if (distanceKm <= 100) geoBonus = 2;
  }

  rawScore += geoBonus;

  // Missing penalty
  const missingPenalty = Math.min(16, missingReq.length * 4);
  rawScore -= missingPenalty;

  rawScore = clamp(rawScore, 0, 100);
  if (rawScore < 35) return null;

  // ✅ Confidence (manual vs cv evidence)
  const conf = computeConfidenceFromEvidence({
    matchedReq,
    manualSet: sets.manualSet,
    cvSet: sets.cvSet,
    user,
  });

  // ✅ Apply confidence to internal score (ranking-safe)
  const scoreInternal = clamp(Math.round(rawScore * conf.confidenceScore), 0, 100);
  if (scoreInternal < 35) return null;

  // ✅ Display score (user-only hype)
  const displayScore = toDisplayScore(scoreInternal);

  return {
    // UI-friendly score
    score: displayScore,

    // Debug/ranking info
    scoreInternal,
    scoreRawBeforeConfidence: rawScore,

    confidenceScore: conf.confidenceScore,
    confidenceBadge: conf.confidenceBadge,
    confidenceDetails: conf.confidenceDetails,

    matchedSkills: matchedReq,
    missingSkills: missingReq,
    matchedNiceSkills,
    missingNiceSkills,
    reqRatio,
    missingPenalty,
    niceBonus,
    mobileBonus,
    bioBonus,
    geoBonus,
    distanceKm,
  };
}

/* =========================================================
   NOTIFICATION: invalid token cleanup helper
   ========================================================= */

async function maybeCleanupFcmToken({ uid, err }) {
  const code = err?.errorInfo?.code || err?.code || "";
  const msg = String(err?.message || "");

  const isInvalid =
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token" ||
    msg.includes("registration-token-not-registered") ||
    msg.includes("invalid-registration-token");

  if (!isInvalid || !uid) return;

  try {
    const db = getFirestore();
    await db.collection("users").doc(uid).update({
      fcmToken: FieldValue.delete(),
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

/* =========================================================
   MATCH CLEANUP HELPERS
   ========================================================= */

async function cleanupMatchesForJob(jobId) {
  const db = getFirestore();

  const snap = await db
    .collectionGroup("matches")
    .where(FieldPath.documentId(), "==", jobId)
    .get();

  if (snap.empty) return;

  let batch = db.batch();
  let ops = 0;

  for (const d of snap.docs) {
    batch.delete(d.ref);
    ops++;
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) await batch.commit();
  console.log("🧹 cleanupMatchesForJob done:", jobId, "deleted:", snap.size);
}

/* =========================================================
   0) CV URL değişince -> indir + parse + SECTION + QUALITY + SKILLS_SEED + (AI?) + DONE/ERROR
   ========================================================= */
exports.onUserCvUrlChanged = onDocumentWritten("users/{uid}", async (event) => {
  const afterSnap = event.data?.after;
  const beforeSnap = event.data?.before;

  if (!afterSnap || !afterSnap.exists) return;

  const after = afterSnap.data() || {};
  const before = beforeSnap && beforeSnap.exists ? beforeSnap.data() || {} : {};

  // ✅ Sadece bireysel kullanıcı
  if (after.type !== "individual" || after.isCompany === true) return;

  const afterCvUrl = safeStr(after.cvUrl).trim();
  const beforeCvUrl = safeStr(before.cvUrl).trim();

  if (!afterCvUrl) return;
  if (afterCvUrl === beforeCvUrl) return;

  const db = getFirestore();
  const uid = event.params.uid;
  const userRef = db.collection("users").doc(uid);

  const requestId = randomId16();

  await userRef.set(
    {
      cvParseStatus: "parsing",
      cvParseRequestId: requestId,
      cvTextHash: "",
      profileStructured: {},
      profileSummary: "",
      cvParsedAt: null,
      cvParseStartedAt: FieldValue.serverTimestamp(),
      cvParseError: FieldValue.delete(),

      cvParseQuality: "unknown",
      cvParseQualityReason: FieldValue.delete(),
      cvParseQualityFlags: FieldValue.delete(),
      cvParseQualityMetrics: FieldValue.delete(),

      cvAiStatus: "pending",
      cvAiRequestId: FieldValue.delete(),
      cvAiError: FieldValue.delete(),
      cvAiStartedAt: FieldValue.delete(),
      cvAiFinishedAt: FieldValue.delete(),
    },
    { merge: true }
  );

  try {
    const resp = await fetchFn(afterCvUrl, { method: "GET" });
    if (!resp || !resp.ok) {
      const txt = await resp.text().catch(() => "");
      throw new Error(`PDF_DOWNLOAD_FAILED status=${resp?.status} body=${txt?.slice(0, 200) || ""}`);
    }

    const arrBuf = await resp.arrayBuffer();
    const pdfBuf = Buffer.from(arrBuf);

    const pdfHash = sha256Buf(pdfBuf);

    const parsed = await pdfParse(pdfBuf);
    const text = cleanText(parsed?.text || "");
    if (!text) throw new Error("PDF_PARSED_BUT_EMPTY_TEXT");

    const emailInCv = pickFirstEmail(text);
    const phoneInCv = pickFirstPhone(text);

    // race guard
    const latest = await userRef.get();
    const latestReq = safeStr((latest.data() || {}).cvParseRequestId);
    if (latestReq !== requestId) return;

    const prevHash = safeStr((latest.data() || {}).cvTextHash).trim();
    const prevAiDone = safeStr((latest.data() || {}).cvAiStatus).trim() === "done";
    const sameHash = prevHash && prevHash === pdfHash;

    const sectionsRaw = splitCvIntoSections(text);
    const sections = {};
    for (const k of Object.keys(sectionsRaw)) sections[k] = capStr(sectionsRaw[k], 6000);

    const fullText = capStr(text, 200000);

    // ✅ skill seed
    const skillsSeed = extractSkillsSeed({ sections, fullText });
    const skillsNormalizedSeed = uniq(skillsSeed.map(normSkill)).filter(Boolean);

    await userRef.collection("cvParses").doc(requestId).set(
      {
        requestId,
        cvUrl: afterCvUrl,
        cvTextHash: pdfHash,
        fullText,
        sections,
        skillsSeed,
        skillsNormalizedSeed,
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const fallbackSummaryMax = 1800;
    const fallbackSummary =
      text.length > fallbackSummaryMax ? text.slice(0, fallbackSummaryMax).trim() + "…" : text;

    const quality = evaluateCvQuality({ text, sections, emailInCv, phoneInCv });

    await userRef.set(
      {
        cvParseStatus: "done",
        cvTextHash: pdfHash,
        profileSummary: fallbackSummary,
        profileStructured: {
          email: emailInCv,
          phone: phoneInCv,

          // seed'i parse aşamasında bile yaz
          skillsSeed,
          skillsNormalizedSeed,
        },
        cvParsedAt: FieldValue.serverTimestamp(),
        cvParseError: FieldValue.delete(),

        cvParseQuality: quality.isBad ? "bad" : "good",
        cvParseQualityReason: quality.reason,
        cvParseQualityFlags: quality.flags,
        cvParseQualityMetrics: quality.metrics,
      },
      { merge: true }
    );

    if (sameHash && prevAiDone) {
      await userRef.set({ cvAiStatus: "skipped_same_hash" }, { merge: true });
      return;
    }

    if (quality.isBad) {
      await userRef.set(
        {
          cvAiStatus: "skipped_bad_cv",
          cvAiError: FieldValue.delete(),
          cvAiFinishedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    await enforceCvAiDailyLimit(uid);

    const apiKey = getOpenAiApiKey();
    if (!apiKey) {
      await userRef.set({ cvAiStatus: "error", cvAiError: "OPENAI_API_KEY_NOT_CONFIGURED" }, { merge: true });
      return;
    }

    const aiReqId = randomId16();
    await userRef.set(
      {
        cvAiStatus: "parsing",
        cvAiRequestId: aiReqId,
        cvAiStartedAt: FieldValue.serverTimestamp(),
        cvAiError: FieldValue.delete(),
      },
      { merge: true }
    );

    const aiPayload =
      "SKILLS_SEED(normalized, unique):\n" +
      JSON.stringify(skillsNormalizedSeed, null, 2) +
      "\n\nCV_SECTIONS(JSON):\n" +
      JSON.stringify(sections, null, 2) +
      "\n\nTASK: Yukarıdaki bölümlerden şemaya uygun JSON üret. Sadece JSON döndür.";

    let aiJson = null;
    try {
      aiJson = await callOpenAiJson({ apiKey, userMessage: aiPayload });
    } catch (e) {
      const errMsg = String(e?.message || e);
      await userRef.set(
        {
          cvAiStatus: "error",
          cvAiError: errMsg,
          cvAiFinishedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    await userRef.collection("cvParses").doc(requestId).set(
      {
        aiRequestId: aiReqId,
        ai: aiJson,
        aiFinishedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const aiSummary = safeStr(aiJson?.summary).trim();
    const aiSkillsRaw = Array.isArray(aiJson?.skills) ? aiJson.skills : [];

    // ✅ sanitize (cümleleri çöpe at)
    const aiSkillsNormSanitized = sanitizeNormalizedSkills(aiSkillsRaw);

    // ✅ final CV skills: AI + seed birleşsin
    const finalCvSkillsNorm =
      aiSkillsNormSanitized.length > 0
        ? uniq([...aiSkillsNormSanitized, ...skillsNormalizedSeed])
        : skillsNormalizedSeed;

    const finalCvSkillsNorm2 = sanitizeNormalizedSkills(finalCvSkillsNorm);

    // ✅ NEW: skillsManual / skillsFromCv / skillsEffective ayrımı
    // Backward compat: skillsManual yoksa eski skills'i manual sayıyoruz
    const userNow = await userRef.get();
    const userNowData = userNow.data() || {};

    const manual = getUserSkillsManual(userNowData);
    const fromCv = finalCvSkillsNorm2;
    const effective = computeSkillsEffective({ manual, fromCv });

    await userRef.set(
      {
        cvAiStatus: "done",
        cvAiFinishedAt: FieldValue.serverTimestamp(),

        // CV summary UI için
        profileSummary: aiSummary || fallbackSummary,

        // ✅ NEW STORAGE
        skillsManual: manual,          // kullanıcı seçimi (ya da eski skills)
        skillsFromCv: fromCv,          // CV/AI kaynaklı
        skillsEffective: effective,    // match engine tek kaynağı

        profileStructured: {
          email: emailInCv,
          phone: phoneInCv,

          // AI + seed birlikte
          ...aiJson,

          // CV detay ekranı için
          skills: fromCv,
          skillsNormalizedFromAi: fromCv,
          skillsSeed,
          skillsNormalizedSeed,
        },
      },
      { merge: true }
    );
  } catch (err) {
    const msg = String(err?.message || err);

    const latest = await userRef.get().catch(() => null);
    const latestReq = safeStr((latest?.data() || {}).cvParseRequestId);
    if (latestReq && latestReq !== requestId) return;

    await userRef.set(
      {
        cvParseStatus: "error",
        cvParseError: msg,
        cvParsedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
});

/* =========================================================
   ✅ CV ANALYSES (User doc'a dokunmadan rapor üret)
   collection: cvAnalyses/{analysisId}
   Doc örneği (client yazacak):
   {
     uid: "USER_UID",
     cvUrl: "https://....pdf",
     targetRole: "Backend Developer" (opsiyonel),
     createdAt: serverTimestamp(),
     status: "queued"
   }
   ========================================================= */

async function callOpenAiJsonReport({ apiKey, userMessage }) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), 15000);

  try {
    const resp = await fetchFn("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.2,
        max_tokens: 1000,
        messages: [
          { role: "system", content: CV_ANALYZE_SYSTEM },
          { role: "user", content: userMessage },
        ],
      }),
    });

    if (!resp.ok) {
      const txt = await resp.text().catch(() => "");
      throw new Error(`OPENAI_HTTP_${resp.status} ${txt.slice(0, 200)}`);
    }

    const data = await resp.json().catch(() => null);
    const raw = data?.choices?.[0]?.message?.content || "";
    const trimmed = String(raw).trim();
    if (!trimmed) throw new Error("OPENAI_EMPTY_RESPONSE");

    const jsonText = trimmed.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
    return JSON.parse(jsonText);
  } finally {
    clearTimeout(t);
  }
}

// ✅ Ayrı limit: parse limitinle karışmasın
async function enforceCvAnalyzeDailyLimit(uid) {
  const db = getFirestore();
  const ref = db.collection("cvAnalyzeUsage").doc(uid);

  const PER_DAY = 3;

  const now = new Date();
  const dayBucket = `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, "0")}${String(
    now.getUTCDate()
  ).padStart(2, "0")}`;

  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.exists ? snap.data() || {} : {};

    const dayKey = d.dayBucket || "";
    const dayCount = dayKey === dayBucket ? Number(d.dayCount || 0) : 0;

    if (dayCount >= PER_DAY) throw Object.assign(new Error("CV_ANALYZE_DAILY_LIMIT"), { status: 429 });

    tx.set(
      ref,
      { dayBucket, dayCount: dayCount + 1, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );

    return { dayLeft: PER_DAY - (dayCount + 1) };
  });
}

exports.onCvAnalysisCreated = onDocumentCreated("cvAnalyses/{analysisId}", async (event) => {
  const snap = event.data;
  if (!snap || !snap.exists) return;

  const analysisId = event.params.analysisId;
  const db = getFirestore();
  const ref = db.collection("cvAnalyses").doc(analysisId);

  const data = snap.data() || {};
  const uid = safeStr(data.uid).trim();
  const cvUrl = safeStr(data.cvUrl).trim();
  const targetRole = safeStr(data.targetRole || data.jobTitle).trim() || null;

  if (!uid || !cvUrl) {
    await ref.set({ status: "error", error: "MISSING_UID_OR_CVURL", finishedAt: FieldValue.serverTimestamp() }, { merge: true });
    return;
  }

  const st = safeStr(data.status).trim().toLowerCase();
  if (st === "done") return;

  await ref.set(
    {
      status: "running",
      startedAt: FieldValue.serverTimestamp(),
      error: FieldValue.delete(),
    },
    { merge: true }
  );

  try {
    await enforceCvAnalyzeDailyLimit(uid);

    const apiKey = getOpenAiCvAnalyzeKey();
    if (!apiKey) throw new Error("OPENAI_API_CV_ANALYZE_NOT_CONFIGURED");

    const resp = await fetchFn(cvUrl, { method: "GET" });
    if (!resp || !resp.ok) {
      const txt = await resp.text().catch(() => "");
      throw new Error(`PDF_DOWNLOAD_FAILED status=${resp?.status} body=${txt?.slice(0, 200) || ""}`);
    }

    const arrBuf = await resp.arrayBuffer();
    const pdfBuf = Buffer.from(arrBuf);

    const pdfHash = sha256Buf(pdfBuf);

    const parsed = await pdfParse(pdfBuf);
    const text = cleanText(parsed?.text || "");
    if (!text) throw new Error("PDF_PARSED_BUT_EMPTY_TEXT");

    const emailInCv = pickFirstEmail(text);
    const phoneInCv = pickFirstPhone(text);

    const sectionsRaw = splitCvIntoSections(text);
    const sections = {};
    for (const k of Object.keys(sectionsRaw)) sections[k] = capStr(sectionsRaw[k], 6000);

    const quality = evaluateCvQuality({ text, sections, emailInCv, phoneInCv });
    const parseQuality = quality.isBad ? "bad" : "good";

    // Kötü parse ise: AI'a gitme, ATS/okunabilirlik fail raporu dön
    if (quality.isBad) {
      await ref.set(
        {
          status: "done",
          finishedAt: FieldValue.serverTimestamp(),
          cvTextHash: pdfHash,
          parseQuality,
          parseQualityReason: quality.reason,
          parseQualityFlags: quality.flags,
          parseQualityMetrics: quality.metrics,
          extracted: {
            email: emailInCv || null,
            phone: phoneInCv || null,
            sectionKeys: Object.keys(sections),
          },
          report: {
            overallScore: 10,
            parseQuality,
            ats: {
              compatScore: 5,
              level: "poor",
              blockingIssues: [
                "CV metni sağlıklı okunamadı (PDF text tabanlı değil veya layout bozuk).",
              ],
              warnings: [],
              quickFixes: [
                "CV'yi Word/Google Docs'tan 'PDF (text-based)' olarak tekrar export et.",
                "Scan/fotoğraf PDF kullanma.",
                "Başlıkları net yap: Summary, Skills, Experience, Education."
              ],
            },
            strengths: [],
            gaps: ["İçerik değerlendirmesi yapılamadı çünkü parse kalitesi düşük."],
            missingSections: [],
            contentImprovements: {
              summaryRewrite: null,
              skillsCleanup: [],
              experienceFixes: [],
              projectFixes: [],
            },
            bulletFixes: [],
            actionPlan: [
              {
                title: "Önce formatı düzelt",
                priority: "high",
                steps: [
                  "Text-based PDF yükle",
                  "Tek sütun ve standart font kullan",
                  "Başlıkları sade ve ATS uyumlu yaz"
                ],
              },
            ],
            roleFit: { targetRole, fitScore: 0, why: ["Metin okunamadı"], missingSkills: [], nextSteps: [] },
          },
        },
        { merge: true }
      );
      return;
    }

    const skillsSeed = extractSkillsSeed({ sections, fullText: capStr(text, 200000) });
    const skillsNormalizedSeed = uniq(skillsSeed.map(normSkill)).filter(Boolean);

    const payload =
      "TARGET_ROLE:\n" + JSON.stringify(targetRole, null, 2) +
      "\n\nPARSE_QUALITY:\n" + JSON.stringify({ parseQuality, reason: quality.reason, flags: quality.flags, metrics: quality.metrics }, null, 2) +
      "\n\nSKILLS_SEED(normalized):\n" + JSON.stringify(skillsNormalizedSeed, null, 2) +
      "\n\nCV_SECTIONS(JSON):\n" + JSON.stringify(sections, null, 2) +
      "\n\nTASK: CV'yi ATS uyumluluğu dahil değerlendir. Şemaya uygun JSON üret. Sadece JSON döndür.";

    const report = await callOpenAiJsonReport({ apiKey, userMessage: payload });

    await ref.set(
      {
        status: "done",
        finishedAt: FieldValue.serverTimestamp(),
        cvTextHash: pdfHash,
        parseQuality,
        parseQualityReason: quality.reason,
        parseQualityFlags: quality.flags,
        parseQualityMetrics: quality.metrics,
        extracted: {
          email: emailInCv || null,
          phone: phoneInCv || null,
          skillsSeed: skillsNormalizedSeed,
          sectionKeys: Object.keys(sections),
        },
        report,
      },
      { merge: true }
    );
  } catch (err) {
    const msg = String(err?.message || err);
    await ref.set(
      {
        status: "error",
        error: msg,
        finishedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
});

/* =========================================================
   1) SOHBET MESAJI GELİNCE FCM BİLDİRİMİ
   ========================================================= */
exports.sendChatNotification = onDocumentCreated("chats/{chatId}/messages/{messageId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const newMessage = snapshot.data() || {};
  const chatId = event.params.chatId;

  const senderId = newMessage.senderId;
  const type = safeStr(newMessage.type || "text");
  const text = safeStr(newMessage.text || "");

  if (!senderId) return;

  const db = getFirestore();
  const chatDoc = await db.collection("chats").doc(chatId).get();
  if (!chatDoc.exists) return;

  const chatData = chatDoc.data() || {};
  const users = Array.isArray(chatData.users) ? chatData.users : [];
  if (users.length < 2) return;

  const receiverId = users.find((id) => id !== senderId);
  if (!receiverId) return;

  const [receiverDoc, senderDoc] = await Promise.all([
    db.collection("users").doc(receiverId).get(),
    db.collection("users").doc(senderId).get(),
  ]);
  if (!receiverDoc.exists || !senderDoc.exists) return;

  const receiverData = receiverDoc.data() || {};
  const senderData = senderDoc.data() || {};

  const receiverToken = receiverData.fcmToken;
  const senderName = senderData.name || "Bir kullanıcı";
  if (!receiverToken) return;

  let body = "Yeni bir mesajın var";
  if (type === "text") {
    if (!text) body = "Yeni bir mesajın var";
    else if (text.length > 100) body = text.slice(0, 97) + "...";
    else body = text;
  } else if (type === "image") body = "📷 Fotoğraf gönderdi";
  else if (type === "video") body = "🎥 Video gönderdi";
  else if (type === "audio") body = "🎙️ Sesli mesaj gönderdi";
  else if (type === "pdf") body = "📄 PDF dosyası gönderdi";
  else body = "📎 Dosya gönderdi";

  const message = {
    token: receiverToken,
    notification: { title: "Yeni mesajın var !: " + senderName, body },
    data: { chatId, senderId, type },
  };

  try {
    await getMessaging().send(message);
  } catch (err) {
    await maybeCleanupFcmToken({ uid: receiverId, err });
  }
});

/* =========================================================
   2) AI CAREER ADVISOR – Güvenli + Limitli + Hızlı
   ========================================================= */

async function requireFirebaseUser(req) {
  const authHeader = req.headers.authorization || req.headers.Authorization || "";
  const m = String(authHeader).match(/^Bearer\s+(.+)$/i);
  const token = m ? m[1].trim() : "";
  if (!token) throw Object.assign(new Error("UNAUTHENTICATED"), { status: 401 });

  const decoded = await getAuth().verifyIdToken(token).catch(() => null);
  if (!decoded?.uid) throw Object.assign(new Error("UNAUTHENTICATED"), { status: 401 });
  return decoded;
}

async function enforceAiRateLimit(uid) {
  const db = getFirestore();
  const ref = db.collection("aiUsage").doc(uid);

  const PER_MIN = 8;
  const PER_DAY = 60;

  const now = new Date();
  const minuteBucket = `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, "0")}${String(
    now.getUTCDate()
  ).padStart(2, "0")}${String(now.getUTCHours()).padStart(2, "0")}${String(now.getUTCMinutes()).padStart(2, "0")}`;
  const dayBucket = `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, "0")}${String(
    now.getUTCDate()
  ).padStart(2, "0")}`;

  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.exists ? snap.data() || {} : {};

    const minKey = d.minuteBucket || "";
    const dayKey = d.dayBucket || "";

    const minuteCount = minKey === minuteBucket ? Number(d.minuteCount || 0) : 0;
    const dayCount = dayKey === dayBucket ? Number(d.dayCount || 0) : 0;

    if (minuteCount >= PER_MIN) throw Object.assign(new Error("RATE_LIMIT_MINUTE"), { status: 429 });
    if (dayCount >= PER_DAY) throw Object.assign(new Error("RATE_LIMIT_DAY"), { status: 429 });

    tx.set(
      ref,
      {
        minuteBucket,
        dayBucket,
        minuteCount: minuteCount + 1,
        dayCount: dayCount + 1,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { minuteLeft: PER_MIN - (minuteCount + 1), dayLeft: PER_DAY - (dayCount + 1) };
  });
}

exports.aiCareerAdvisor = onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") return res.status(204).send("");

  if (req.method !== "POST") return res.status(405).send("Only POST allowed");

  try {
    const decoded = await requireFirebaseUser(req);
    const uid = decoded.uid;

    await enforceAiRateLimit(uid);

    const body = req.body || {};
    let message = safeStr(body.message).trim();
    if (!message) return res.status(400).json({ error: "MESSAGE_REQUIRED" });
    if (message.length > 2000) message = message.slice(0, 2000);

    const apiKey = getOpenAiApiKey();
    if (!apiKey) return res.status(500).json({ error: "OPENAI_API_KEY_NOT_CONFIGURED" });

    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), 15000);

    const response = await fetchFn("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.4,
        max_tokens: 420,
        messages: [
          {
            role: "system",
            content:
              "Sen TechConnect uygulamasında çalışan, Türkçe konuşan bir AI kariyer danışmanısın. " +
              "Net, uygulanabilir ve kısa öneriler ver. Gereksiz süsleme yapma. " +
              "Kullanıcıdan özel/kişisel veri isteme. Kısa maddelerle anlat.",
          },
          { role: "user", content: message },
        ],
      }),
    }).finally(() => clearTimeout(t));

    if (!response.ok) {
      const errText = await response.text().catch(() => "");
      return res.status(500).json({ error: "AI_HTTP_ERROR", status: response.status, details: errText });
    }

    const data = await response.json().catch(() => null);
    const reply =
      typeof data?.choices?.[0]?.message?.content === "string" && data.choices[0].message.content.trim()
        ? data.choices[0].message.content.trim()
        : "Şu anda sana cevap oluştururken bir sorun yaşadım.";

    return res.json({ reply });
  } catch (err) {
    const status = err?.status || 500;
    const code = String(err?.message || "AI_REQUEST_FAILED");

    if (status === 401) return res.status(401).json({ error: "UNAUTHENTICATED" });
    if (status === 429) return res.status(429).json({ error: code });

    if (String(err?.name || "") === "AbortError") {
      return res.status(504).json({ error: "AI_TIMEOUT" });
    }

    return res.status(500).json({ error: "AI_REQUEST_FAILED" });
  }
});

/* =========================================================
   3) BAĞLANTI İSTEĞİ GELİNCE FCM BİLDİRİMİ
   ========================================================= */
exports.sendConnectionRequestNotification = onDocumentCreated(
  "connectionRequests/{userId}/incoming/{requestId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() || {};
    const targetUserId = event.params.userId;
    const fromId = data.from;
    const toId = data.to;

    if (!fromId || !toId || toId !== targetUserId) return;

    const db = getFirestore();

    try {
      const [fromDoc, toDoc] = await Promise.all([
        db.collection("users").doc(fromId).get(),
        db.collection("users").doc(toId).get(),
      ]);

      if (!toDoc.exists) return;

      const token = (toDoc.data() || {}).fcmToken;
      if (!token) return;

      const fromData = fromDoc.exists ? fromDoc.data() || {} : {};
      const fromName =
        (fromData.name && String(fromData.name).trim()) ||
        (fromData.username && `@${String(fromData.username).trim()}`) ||
        "Bir kullanıcı";

      const message = {
        token,
        notification: { title: "Yeni bağlantı isteği", body: `${fromName} sana bağlantı isteği gönderdi.` },
        data: { type: "connection_request", fromUserId: fromId, toUserId: toId },
      };

      await getMessaging().send(message);
    } catch (err) {
      await maybeCleanupFcmToken({ uid: toId, err });
    }
  }
);

/* =========================================================
   4) USERS -> TERS İNDEKS SENKRON (userSkillIndex)
   ========================================================= */
exports.syncUserSkillIndex = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;
  if (!after) return;

  // ✅ Şirket hesaplarını index'leme
  if (after.type === "company" || after.isCompany === true) return;

  const uid = event.params.uid;
  const db = getFirestore();

  // Skills effective changes?
  const beforeEff = before ? getSkillsEffectiveFromUser(before) : [];
  const afterEff = getSkillsEffectiveFromUser(after);

  // skillsNormalized sync (tek kaynak = skillsEffective)
  const existingNorm = sanitizeNormalizedSkills(after.skillsNormalized || []);
  if (existingNorm.join("|") !== afterEff.join("|")) {
    await db.collection("users").doc(uid).update({
      skillsNormalized: afterEff,
      profileUpdatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }

  if (beforeEff.join("|") === afterEff.join("|")) return;

  const batch = db.batch();

  for (const sk of beforeEff) {
    batch.delete(db.collection("userSkillIndex").doc(sk).collection("users").doc(uid));
  }

  const payload = {
    uid,
    location: after.location || null,
    seniority: after.seniority || after.level || null,
    levelRank: levelRank(after.seniority || after.level || null),
    workModelPrefs: after.workModelPrefs || { remote: true, hybrid: true, "on-site": true },
    updatedAt: FieldValue.serverTimestamp(),
  };

  for (const sk of afterEff) {
    if (!sk) continue;
    batch.set(db.collection("userSkillIndex").doc(sk).collection("users").doc(uid), payload, { merge: true });
  }

  await batch.commit();
});

/* =========================================================
   4.5) NEW USER DEFAULTS (Sadece oluşturulunca)
   ========================================================= */
exports.onUserCreatedEnsureDefaults = onDocumentCreated("users/{uid}", async (event) => {
  const snap = event.data;
  if (!snap || !snap.exists) return;

  const uid = event.params.uid;
  const db = getFirestore();
  const data = snap.data() || {};

  // ✅ Şirket hesaplarına dokunma
  if (data.type === "company" || data.isCompany === true) return;

  const patch = {};

  if (data.active === undefined) patch.active = true;
  if (data.isSearchable === undefined) patch.isSearchable = true;

  if (!Array.isArray(data.roles) || data.roles.length === 0) patch.roles = ["user"];

  if (!data.workModelPreference) patch.workModelPreference = "any";

  if (!data.workModelPrefs || typeof data.workModelPrefs !== "object") {
    patch.workModelPrefs = { remote: true, hybrid: true, "on-site": true };
  }

  const pref = safeStr(data.workModelPreference || patch.workModelPreference || "any").toLowerCase();
  const prefs = data.workModelPrefs || patch.workModelPrefs;
  if (pref === "any" && prefs && typeof prefs === "object") {
    patch.workModelPrefs = { remote: true, hybrid: true, "on-site": true };
  }

  if (!data.createdAt) patch.createdAt = FieldValue.serverTimestamp();

  if (data.name && !data.nameLower) patch.nameLower = String(data.name).toLowerCase();
  if (data.username && !data.usernameLower) patch.usernameLower = String(data.username).toLowerCase();

  // Backward compat: skills -> skillsManual
  if (!Array.isArray(data.skillsManual) && Array.isArray(data.skills)) {
    patch.skillsManual = sanitizeNormalizedSkills(data.skills);
  }

  // Compute effective if missing
  if (!Array.isArray(data.skillsEffective)) {
    const manual = Array.isArray(patch.skillsManual) ? patch.skillsManual : getUserSkillsManual(data);
    const fromCv = getUserSkillsFromCv(data);
    patch.skillsEffective = computeSkillsEffective({ manual, fromCv });
  }

  if ((!Array.isArray(data.skillsNormalized) || data.skillsNormalized.length === 0) && Array.isArray(patch.skillsEffective)) {
    patch.skillsNormalized = patch.skillsEffective;
  }

  if (Object.keys(patch).length === 0) return;

  await db.collection("users").doc(uid).set(
    { ...patch, profileUpdatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );
});

/* =========================================================
   5) JOB upsert -> aday bul -> match yaz / sil (userMatches)
   ========================================================= */
exports.onJobUpsertComputeMatches = onDocumentWritten("jobs/{jobId}", async (event) => {
  const after = event.data?.after?.data() || null;
  const jobId = event.params.jobId;
  const db = getFirestore();

  if (!after) return;

  if (after.isActive !== true) {
    await cleanupMatchesForJob(jobId);
    return;
  }

  // REQUIRED normalize sync
  const requiredNorm = uniq((after.requiredSkills || after.requiredSkillsNormalized || []).map(normSkill)).filter(Boolean);
  const existingRequiredNorm = uniq((after.requiredSkillsNormalized || []).map(normSkill)).filter(Boolean);
  if (requiredNorm.join("|") !== existingRequiredNorm.join("|")) {
    await db.collection("jobs").doc(jobId).update({
      requiredSkillsNormalized: requiredNorm,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }

  // NICE normalize sync
  const niceNorm = uniq((after.niceToHaveSkills || after.niceToHaveSkillsNormalized || []).map(normSkill)).filter(Boolean);
  const existingNiceNorm = uniq((after.niceToHaveSkillsNormalized || []).map(normSkill)).filter(Boolean);
  if (niceNorm.join("|") !== existingNiceNorm.join("|")) {
    await db.collection("jobs").doc(jobId).update({
      niceToHaveSkillsNormalized: niceNorm,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }

  // SEED = REQUIRED
  const seedBase = requiredNorm.length > 0 ? requiredNorm : uniq((after.skillsNormalized || after.skills || []).map(normSkill)).filter(Boolean);

  // ✅ dynamic seed count
  const seedCount = requiredNorm.length <= 4 ? 3 : requiredNorm.length <= 8 ? 5 : 6;
  const seeds = pickDiscriminativeSkills(seedBase, seedCount);
  if (seeds.length === 0) return;

  const candidateMap = new Map();
  for (const sk of seeds) {
    const snap = await db.collection("userSkillIndex").doc(sk).collection("users").limit(500).get();
    snap.forEach((doc) => {
      const d = doc.data() || {};
      if (d.uid) candidateMap.set(d.uid, true);
    });
  }

  let candidates = Array.from(candidateMap.keys());
  if (candidates.length === 0) return;
  candidates = candidates.slice(0, 1200);

  const nowTs = FieldValue.serverTimestamp();

  const userRef = (uid) => db.collection("users").doc(uid);
  const userDocs = [];

  for (const part of chunk(candidates, 50)) {
    const refs = part.map(userRef);
    const snaps = await db.getAll(...refs);
    for (const s of snaps) userDocs.push(s);
  }

  let batch = db.batch();
  let ops = 0;

  for (const userDoc of userDocs) {
    if (!userDoc.exists) continue;

    const uid = userDoc.id;
    const user = userDoc.data() || {};

    const result = computeMatchEngine({ user, job: after });
    const matchRef = db.collection("userMatches").doc(uid).collection("matches").doc(jobId);

    if (!result) {
      batch.delete(matchRef);
    } else {
      const requiredNorm2 = uniq((after.requiredSkillsNormalized || after.requiredSkills || []).map(normSkill)).filter(Boolean);

      const reasons = [];
      reasons.push(`Required uyum: %${Math.round(result.reqRatio * 100)} (${result.matchedSkills.length}/${requiredNorm2.length}).`);

      if (result.matchedSkills.length > 0) reasons.push(`Required sende: ${result.matchedSkills.slice(0, 3).join(", ")}.`);
      if (result.missingSkills.length > 0) reasons.push(`Eksik required: ${result.missingSkills.slice(0, 3).join(", ")}.`);
      if (result.matchedNiceSkills?.length > 0) reasons.push(`Nice-to-have sende: ${result.matchedNiceSkills.slice(0, 3).join(", ")} (+bonus).`);
      if (result.mobileBonus > 0) reasons.push("Mobil yakınlık bonusu: Kotlin/Swift geçmişin bu rolü destekliyor.");
      if (result.bioBonus > 0) reasons.push("Bio içeriğin required becerilerle örtüşüyor.");
      if (result.geoBonus > 0 && result.distanceKm != null) reasons.push(`Yakınlık avantajı: ~${Math.round(result.distanceKm)} km.`);
      if (after.workModel) reasons.push(`Çalışma modeli: ${after.workModel}.`);

      // ✅ confidence note (user-side etiketi)
      const confText =
        result.confidenceBadge === "high"
          ? "Güven: Yüksek (profil/manuel kanıt güçlü)."
          : result.confidenceBadge === "medium"
            ? "Güven: Orta (karışık kaynak)."
            : "Güven: Düşük (CV bazlı, doğrulanmamış).";
      reasons.unshift(confText);

      batch.set(
        matchRef,
        {
          jobId,

          // ✅ USER DISPLAY
          score: result.score,

          // ✅ INTERNAL
          scoreInternal: result.scoreInternal,
          scoreRawBeforeConfidence: result.scoreRawBeforeConfidence,

          confidenceScore: result.confidenceScore,
          confidenceBadge: result.confidenceBadge,
          confidenceDetails: result.confidenceDetails,

          reasons: reasons.slice(0, 6),

          matchedSkills: result.matchedSkills,
          missingSkills: result.missingSkills,

          matchedNiceSkills: result.matchedNiceSkills || [],
          missingNiceSkills: result.missingNiceSkills || [],

          reqRatio: result.reqRatio,
          missingPenalty: result.missingPenalty,

          niceBonus: result.niceBonus || 0,
          mobileBonus: result.mobileBonus || 0,
          bioBonus: result.bioBonus || 0,

          geoBonus: result.geoBonus,
          distanceKm: result.distanceKm,

          jobSnapshot: {
            jobId,
            title: after.title || null,
            companyId: after.companyId || null,
            companyName: after.companyName || null,
            location: after.location || null,
            workModel: after.workModel || null,
            minSalary: after.minSalary || null,
            maxSalary: after.maxSalary || null,
            currency: after.currency || null,
            level: after.level || null,
            geo: after.geo || null,
            requiredSkills: after.requiredSkills || null,
            niceToHaveSkills: after.niceToHaveSkills || null,
          },

          updatedAt: nowTs,
        },
        { merge: true }
      );
    }

    ops++;
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) await batch.commit();
});

/* =========================================================
   6) USER değişince -> matches güncelle
   ========================================================= */
exports.onUserProfileRecomputeMatches = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;
  if (!after) return;

  const uid = event.params.uid;
  const db = getFirestore();

  const beforeEff = before ? getSkillsEffectiveFromUser(before) : [];
  const afterEff = getSkillsEffectiveFromUser(after);

  const beforeLoc = safeStr(before?.location).trim().toLowerCase();
  const afterLoc = safeStr(after.location).trim().toLowerCase();

  const beforeBio = safeStr(before?.bio).trim();
  const afterBio = safeStr(after.bio).trim();

  const beforeWork = normWorkModel(before?.workModelPreference || "any");
  const afterWork = normWorkModel(after.workModelPreference || "any");

  const beforePrefs = before?.workModelPrefs ? JSON.stringify(before.workModelPrefs) : "";
  const afterPrefs = after?.workModelPrefs ? JSON.stringify(after.workModelPrefs) : "";
  const prefsChanged = beforePrefs !== afterPrefs;

  const beforeSen = safeStr(before?.seniority || before?.level).trim().toLowerCase();
  const afterSen = safeStr(after.seniority || after.level).trim().toLowerCase();

  const beforeGeo = before?.geo ? `${before.geo.latitude},${before.geo.longitude}` : "";
  const afterGeo = after.geo ? `${after.geo.latitude},${after.geo.longitude}` : "";

  const skillsChanged = beforeEff.join("|") !== afterEff.join("|");
  const locationChanged = beforeLoc !== afterLoc;
  const bioChanged = beforeBio !== afterBio;
  const workChanged = beforeWork !== afterWork;
  const senChanged = beforeSen !== afterSen;
  const geoChanged = beforeGeo !== afterGeo;

  if (!skillsChanged && !locationChanged && !bioChanged && !workChanged && !prefsChanged && !senChanged && !geoChanged) return;
  if (after.active === false) return;

  const jobsSnap = await db.collection("jobs").where("isActive", "==", true).limit(300).get();
  if (jobsSnap.empty) return;

  const nowTs = FieldValue.serverTimestamp();
  let batch = db.batch();
  let ops = 0;

  for (const jobDoc of jobsSnap.docs) {
    const job = jobDoc.data() || {};
    const jobId = jobDoc.id;

    const result = computeMatchEngine({ user: after, job });
    const ref = db.collection("userMatches").doc(uid).collection("matches").doc(jobId);

    if (!result) {
      batch.delete(ref);
    } else {
      const requiredNorm = uniq((job.requiredSkillsNormalized || job.requiredSkills || []).map(normSkill)).filter(Boolean);

      const reasons = [];
      reasons.push(`Required uyum: %${Math.round(result.reqRatio * 100)} (${result.matchedSkills.length}/${requiredNorm.length}).`);
      if (result.matchedSkills.length > 0) reasons.push(`Required sende: ${result.matchedSkills.slice(0, 3).join(", ")}.`);
      if (result.missingSkills.length > 0) reasons.push(`Eksik required: ${result.missingSkills.slice(0, 3).join(", ")}.`);
      if (result.matchedNiceSkills?.length > 0) reasons.push(`Nice-to-have sende: ${result.matchedNiceSkills.slice(0, 3).join(", ")} (+bonus).`);
      if (result.mobileBonus > 0) reasons.push("Mobil yakınlık bonusu: Kotlin/Swift geçmişin bu rolü destekliyor.");
      if (result.bioBonus > 0) reasons.push("Bio içeriğin required becerilerle örtüşüyor.");
      if (result.geoBonus > 0 && result.distanceKm != null) reasons.push(`Yakınlık avantajı: ~${Math.round(result.distanceKm)} km.`);
      if (job.workModel) reasons.push(`Çalışma modeli: ${job.workModel}.`);

      const confText =
        result.confidenceBadge === "high"
          ? "Güven: Yüksek (profil/manuel kanıt güçlü)."
          : result.confidenceBadge === "medium"
            ? "Güven: Orta (karışık kaynak)."
            : "Güven: Düşük (CV bazlı, doğrulanmamış).";
      reasons.unshift(confText);

      batch.set(
        ref,
        {
          jobId,

          // ✅ USER DISPLAY
          score: result.score,

          // ✅ INTERNAL
          scoreInternal: result.scoreInternal,
          scoreRawBeforeConfidence: result.scoreRawBeforeConfidence,

          confidenceScore: result.confidenceScore,
          confidenceBadge: result.confidenceBadge,
          confidenceDetails: result.confidenceDetails,

          reasons: reasons.slice(0, 6),

          matchedSkills: result.matchedSkills,
          missingSkills: result.missingSkills,

          matchedNiceSkills: result.matchedNiceSkills || [],
          missingNiceSkills: result.missingNiceSkills || [],

          reqRatio: result.reqRatio,
          missingPenalty: result.missingPenalty,

          niceBonus: result.niceBonus || 0,
          mobileBonus: result.mobileBonus || 0,
          bioBonus: result.bioBonus || 0,

          geoBonus: result.geoBonus,
          distanceKm: result.distanceKm,

          jobSnapshot: {
            jobId,
            title: job.title || null,
            companyId: job.companyId || null,
            companyName: job.companyName || null,
            location: job.location || null,
            workModel: job.workModel || null,
            minSalary: job.minSalary || null,
            maxSalary: job.maxSalary || null,
            currency: job.currency || null,
            level: job.level || null,
            geo: job.geo || null,
            requiredSkills: job.requiredSkills || null,
            niceToHaveSkills: job.niceToHaveSkills || null,
          },

          updatedAt: nowTs,
        },
        { merge: true }
      );
    }

    ops++;
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) await batch.commit();
});

/* =========================================================
   7) JOB silinince -> userMatches temizle
   ========================================================= */
exports.onJobDeletedCleanupMatches = onDocumentDeleted("jobs/{jobId}", async (event) => {
  const jobId = event.params.jobId;
  await cleanupMatchesForJob(jobId);
});

/* =========================================================
   ✅ DEMO PREMIUM (Aylık / Yıllık)
   Callable: completeDemoPaymentAndActivatePremium
   planId: premium_monthly | premium_yearly
   ========================================================= */

exports.completeDemoPaymentAndActivatePremium = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Giriş yapılmamış.");
  }

  const { planId, clientTxId } = request.data || {};
  if (!planId || !clientTxId) {
    throw new HttpsError("invalid-argument", "Eksik parametre: planId/clientTxId");
  }

  const PLAN_DAYS = {
    premium_monthly: 30,
    premium_yearly: 365,
  };

  const daysToAdd = PLAN_DAYS[planId];
  if (!daysToAdd) {
    throw new HttpsError("invalid-argument", "Geçersiz planId.");
  }

  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);

  // ✅ idempotency: aynı clientTxId tekrar gelirse ikinci kez süre eklemesin
  const txRef = db.collection("premiumEvents").doc(`${uid}_${clientTxId}`);

  let computedPremiumUntil = null;

  await db.runTransaction(async (tx) => {
    const [txSnap, userSnap] = await Promise.all([tx.get(txRef), tx.get(userRef)]);

    // aynı tx tekrar geldiyse -> hiç dokunma (idempotent)
    if (txSnap.exists) {
      // mümkünse eski premiumUntil'ı response için al
      if (userSnap.exists) {
        const u = userSnap.data() || {};
        if (u.premiumUntil && typeof u.premiumUntil.toDate === "function") {
          computedPremiumUntil = u.premiumUntil;
        }
      }
      return;
    }

    const now = Timestamp.now();

    // aktif premium varsa üstüne ekle, yoksa now'dan başlat
    let base = now;
    if (userSnap.exists) {
      const u = userSnap.data() || {};
      const until = u.premiumUntil;
      if (until && typeof until.toDate === "function" && until.toDate() > now.toDate()) {
        base = until;
      }
    }

    const premiumUntil = Timestamp.fromDate(
      new Date(base.toDate().getTime() + daysToAdd * 24 * 60 * 60 * 1000)
    );

    computedPremiumUntil = premiumUntil;

    // ✅ alanlar yoksa otomatik oluşur (merge:true)
    tx.set(
      userRef,
      {
        isPremium: true,
        premiumUntil,
        premiumPlan: planId,           // premium_monthly | premium_yearly
        premiumSource: "demo",
        premiumStartedAt: FieldValue.serverTimestamp(),
        premiumUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // log
    tx.set(
      txRef,
      {
        uid,
        planId,
        type: "demo_activation",
        createdAt: FieldValue.serverTimestamp(),
        premiumUntil,
      },
      { merge: true }
    );
  });

  return {
    isPremium: true,
    planId,
    premiumUntil: computedPremiumUntil, // Timestamp (client isterse gösterir)
  };
});

// ✅ STORY HELPERS
function storySummaryFromItem({ ownerUid, userName, userPhotoUrl, lastStoryAt, lastThumbUrl, expiresAt, activeCount }) {
  return {
    ownerUid,
    userName: userName || "",
    userPhotoUrl: userPhotoUrl || "",
    lastStoryAt: lastStoryAt || FieldValue.serverTimestamp(),
    lastThumbUrl: lastThumbUrl || "",
    expiresAt: expiresAt || FieldValue.serverTimestamp(),
    activeCount: Number(activeCount || 0),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

// recompute owner summary by scanning remaining active items
async function recomputeOwnerStorySummary(db, ownerUid) {
  const itemsRef = db.collection("stories").doc(ownerUid).collection("items");

  // sadece aktifleri çek (expiresAt > now)
  const now = Timestamp.now();
  const snap = await itemsRef.where("expiresAt", ">", now).orderBy("expiresAt", "desc").limit(50).get();

  if (snap.empty) {
    return { exists: false };
  }

  const docs = snap.docs.map(d => ({ id: d.id, ...d.data() }));
  // lastStoryAt: createdAt en yeni item (createdAt yoksa expiresAt'a bakar)
  docs.sort((a, b) => {
    const ac = a.createdAt?.toMillis?.() || 0;
    const bc = b.createdAt?.toMillis?.() || 0;
    return bc - ac;
  });

  const latest = docs[0];
  const maxExpire = docs.reduce((m, x) => {
    const t = x.expiresAt?.toMillis?.() || 0;
    return Math.max(m, t);
  }, 0);

  return {
    exists: true,
    lastStoryAt: latest.createdAt || FieldValue.serverTimestamp(),
    lastThumbUrl: latest.thumbUrl || latest.mediaUrl || "",
    expiresAt: Timestamp.fromMillis(maxExpire),
    activeCount: docs.length,
  };
}

// ✅ 1) ITEM create/update => owner summary + viewer feed update
exports.onStoryItemWrite = onDocumentWritten("stories/{ownerUid}/items/{storyId}", async (event) => {
  const db = getFirestore();
  const ownerUid = event.params.ownerUid;

  // delete handled by separate function
  if (!event.data?.after?.exists) return;

  const item = event.data.after.data() || {};

  // owner summary doc (stories/{ownerUid})
  const ownerRef = db.collection("stories").doc(ownerUid);

  // user meta (adı/foto) users'dan çek
  const userSnap = await db.collection("users").doc(ownerUid).get();
  const u = userSnap.exists ? (userSnap.data() || {}) : {};
  const userName = u.name || u.companyName || "";
  const userPhotoUrl = u.photoUrl || u.photo || u.profilePhotoUrl || "";

  const expiresAt = item.expiresAt && typeof item.expiresAt.toDate === "function"
    ? item.expiresAt
    : Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000));

  const lastStoryAt = item.createdAt || FieldValue.serverTimestamp();
  const lastThumbUrl = item.thumbUrl || item.mediaUrl || "";

  // owner summary'yi en azından ileri taşı (expires büyürse büyüt)
  await ownerRef.set(
    storySummaryFromItem({
      ownerUid,
      userName,
      userPhotoUrl,
      lastStoryAt,
      lastThumbUrl,
      expiresAt,
      activeCount: FieldValue.increment(1), // tam sayı değil ama delete'te recompute edeceğiz
    }),
    { merge: true }
  );

  // connections => storyFeed fanout (SADECE ÖZET)
  const conSnap = await db.collection("connections").doc(ownerUid).collection("list").get();
  if (conSnap.empty) return;

  const payload = storySummaryFromItem({
    ownerUid,
    userName,
    userPhotoUrl,
    lastStoryAt,
    lastThumbUrl,
    expiresAt,
    activeCount: 1, // burada exact olmak zorunda değil, UI için yeterli
  });

  let batch = db.batch();
  let ops = 0;

  for (const c of conSnap.docs) {
    const viewerUid = c.id;
    const ref = db.collection("storyFeed").doc(viewerUid).collection("items").doc(ownerUid);
    batch.set(ref, payload, { merge: true });
    ops++;

    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
});

// ✅ 2) ITEM delete (manual veya TTL) => recompute; bitti ise feed temizle
exports.onStoryItemDelete = onDocumentDeleted("stories/{ownerUid}/items/{storyId}", async (event) => {
  const db = getFirestore();
  const ownerUid = event.params.ownerUid;

  const ownerRef = db.collection("stories").doc(ownerUid);

  // kalan aktif var mı?
  const recompute = await recomputeOwnerStorySummary(db, ownerUid);

  // connections list
  const conSnap = await db.collection("connections").doc(ownerUid).collection("list").get();

  if (!recompute.exists) {
    // owner summary sil
    await ownerRef.delete().catch(() => {});

    // viewer feed’lerden kaldır
    let batch = db.batch();
    let ops = 0;
    for (const c of conSnap.docs) {
      const viewerUid = c.id;
      batch.delete(db.collection("storyFeed").doc(viewerUid).collection("items").doc(ownerUid));
      ops++;
      if (ops >= 450) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    return;
  }

  // user meta
  const userSnap = await db.collection("users").doc(ownerUid).get();
  const u = userSnap.exists ? (userSnap.data() || {}) : {};
  const userName = u.name || u.companyName || "";
  const userPhotoUrl = u.photoUrl || u.photo || u.profilePhotoUrl || "";

  // owner summary güncelle
  await ownerRef.set(
    storySummaryFromItem({
      ownerUid,
      userName,
      userPhotoUrl,
      lastStoryAt: recompute.lastStoryAt,
      lastThumbUrl: recompute.lastThumbUrl,
      expiresAt: recompute.expiresAt,
      activeCount: recompute.activeCount,
    }),
    { merge: true }
  );

  // viewer feed update
  const payload = storySummaryFromItem({
    ownerUid,
    userName,
    userPhotoUrl,
    lastStoryAt: recompute.lastStoryAt,
    lastThumbUrl: recompute.lastThumbUrl,
    expiresAt: recompute.expiresAt,
    activeCount: recompute.activeCount,
  });

  let batch = db.batch();
  let ops = 0;
  for (const c of conSnap.docs) {
    const viewerUid = c.id;
    batch.set(db.collection("storyFeed").doc(viewerUid).collection("items").doc(ownerUid), payload, { merge: true });
    ops++;
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
});

