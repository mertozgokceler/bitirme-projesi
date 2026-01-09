// tools/seed_users.js

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const serviceAccount = require(path.resolve(__dirname, "serviceAccountKey.json"));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: "techconnectapp-e56d3.firebasestorage.app",
});

const db = admin.firestore();
const auth = admin.auth();
const bucket = admin.storage().bucket("techconnectapp-e56d3.firebasestorage.app");

console.log("Using bucket:", bucket.name);

const DEFAULT_PASSWORD = "abcd1234";
const SEED_TAG = "batch_2025_12_31";

function trLower(s) {
  if (!s) return "";
  return s.toString().trim().toLocaleLowerCase("tr-TR");
}

function normalizeSkill(s) {
  return trLower(s).replace(/\s+/g, " ").trim();
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

const ALLOWED_SKILLS = [
  'JavaScript','Python','Java','C#','PHP','C++','TypeScript','Ruby','Swift','Go','Kotlin','Rust','Dart','Scala','SQL',
  'HTML','CSS','React','Angular','Vue.js','Svelte','Next.js','Nuxt.js','Redux','MobX','Tailwind CSS','Bootstrap','Material UI','Chakra UI',
  'Webpack','Vite','Babel',
  'Node.js','Express.js','NestJS','Django','FastAPI','Flask','Spring','Spring Boot','ASP.NET','ASP.NET Core','Laravel','Symfony','Ruby on Rails',
  'Flutter','React Native','SwiftUI','Jetpack Compose','Android SDK','iOS SDK',
  'MySQL','PostgreSQL','SQLite','MongoDB','Redis','Elasticsearch','Firebase','Firestore','DynamoDB','Cassandra',
  'AWS','Azure','Google Cloud','Docker','Kubernetes','Helm','Terraform','Ansible','Jenkins','GitHub Actions','GitLab CI','CircleCI','NGINX','Apache',
  'REST API','GraphQL','gRPC','WebSocket','Socket.IO','Swagger','OpenAPI',
  'TensorFlow','PyTorch','Keras','Scikit-learn','Pandas','NumPy','OpenCV','YOLO','LangChain','OpenAI API',
  'RabbitMQ','Kafka','ActiveMQ','Redis Streams',
  'JUnit','Mockito','Jest','Mocha','Chai','Cypress','Playwright','Selenium','PyTest',
  'JWT','OAuth','OAuth2','OpenID Connect','Keycloak','Firebase Auth','Auth0',
  'Git','GitHub','GitLab','Bitbucket','Postman','Insomnia','Linux','Unix','Bash','PowerShell',
  'Unity','Unreal Engine','Godot','OpenGL','DirectX',
  'Microservices','Monolithic Architecture','Clean Architecture','Domain Driven Design','Event Driven Architecture','CQRS',
  'CI/CD','Agile','Scrum','Kanban',
];

const PROFILES = [
  {
    key: "frontend",
    role: "Frontend Developer",
    titles: ["Frontend Developer", "React Developer", "Web UI Developer"],
    skillsPool: ["JavaScript","TypeScript","HTML","CSS","React","Redux","Next.js","Tailwind CSS","Vite","Webpack","Material UI","Chakra UI"],
    bio: (level, loc) =>
      `${loc} merkezli ${level} seviyesinde frontend geliştiriciyim. React/TypeScript odaklı; component yapısı, performans ve UI tutarlılığına önem veriyorum.`,
  },
  {
    key: "backend",
    role: "Backend Developer",
    titles: ["Backend Developer", "Node.js Developer", "API Developer"],
    skillsPool: ["Node.js","Express.js","NestJS","REST API","Swagger","OpenAPI","PostgreSQL","Redis","Docker","CI/CD","MongoDB"],
    bio: (level, loc) =>
      `${loc} lokasyonunda ${level} backend geliştiriciyim. Ölçeklenebilir API’ler, veri modelleme ve servis tasarımı üzerine çalışıyorum.`,
  },
  {
    key: "mobile",
    role: "Mobile Developer",
    titles: ["Flutter Developer", "Mobile App Developer", "Cross-Platform Developer"],
    skillsPool: ["Flutter","Dart","Firebase","Firestore","REST API","Git","CI/CD","Android SDK","iOS SDK"],
    bio: (level, loc) =>
      `${loc} merkezli ${level} mobil geliştiriciyim. Flutter + Firebase ile ürün odaklı mobil uygulamalar geliştiriyorum.`,
  },
  {
    key: "devops",
    role: "DevOps Engineer",
    titles: ["DevOps Engineer", "Cloud Engineer", "Platform Engineer"],
    skillsPool: ["AWS","Docker","Kubernetes","Terraform","NGINX","Jenkins","GitHub Actions","Linux","CI/CD","Azure","Google Cloud"],
    bio: (level, loc) =>
      `${loc} lokasyonunda ${level} DevOps alanında çalışıyorum. CI/CD, container ve bulut altyapılarıyla dağıtım süreçleri kuruyorum.`,
  },
  {
    key: "dataai",
    role: "Data/AI Engineer",
    titles: ["Data Scientist", "ML Engineer", "AI Engineer"],
    skillsPool: ["Python","Pandas","NumPy","Scikit-learn","PyTorch","TensorFlow","OpenCV","YOLO","Docker","Elasticsearch"],
    bio: (level, loc) =>
      `${loc} lokasyonunda ${level} Data/AI alanında çalışıyorum. Python ekosistemiyle model geliştirme ve değerlendirme süreçlerine odaklanıyorum.`,
  },
];

function pickUniqueFromPool(pool, minCount, maxCount) {
  const filtered = pool.filter((x) => ALLOWED_SKILLS.includes(x));
  const arr = [...filtered].sort(() => 0.5 - Math.random());
  const count = Math.min(randomInt(minCount, maxCount), arr.length);
  return arr.slice(0, count);
}

const seed = [
  { name: "Ahmet Yılmaz", username: "ahmetyilmaz", email: "ahmet.yilmaz@techconnect.app", level: "Junior", location: "İstanbul" },
  { name: "Elif Kaya", username: "elifkaya", email: "elif.kaya@techconnect.app", level: "Junior", location: "Ankara" },
  { name: "Mehmet Demir", username: "mehmetdemir", email: "mehmet.demir@techconnect.app", level: "Senior", location: "İzmir" },
  { name: "Zeynep Arslan", username: "zeyneparslan", email: "zeynep.arslan@techconnect.app", level: "Mid", location: "Bursa" },
  { name: "Merve Aydın", username: "merveaydin", email: "merve.aydin@techconnect.app", level: "Mid", location: "İstanbul" },
];

function buildUserDocBase(u) {
  const usernameLower = trLower(u.username);
  const nameLower = trLower(u.name);

  const profile = PROFILES[usernameLower.length % PROFILES.length];
  const title = profile.titles[usernameLower.length % profile.titles.length];

  const skills = pickUniqueFromPool(profile.skillsPool, 7, 10);
  const skillsNormalized = skills.map(normalizeSkill);

  const bioText = u.bio || profile.bio(u.level || "Junior", u.location || "İstanbul");

  return {
    isSeedUser: true,
    seedTag: SEED_TAG,

    active: true,
    email: u.email,
    emailVerified: true,
    type: "individual",
    roles: ["user"],

    role: profile.role,
    title,

    name: u.name,
    nameLower,
    username: u.username,
    usernameLower,

    bio: bioText,
    level: u.level || "Junior",
    location: u.location || "İstanbul",
    locationSource: "manual",
    isSearchable: true,

    skills,
    skillsNormalized,

    workModelPrefs: {
      remote: false,
      hybrid: true,
      "on-site": false,
    },

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    profileUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function createOrGetAuth(email, displayName) {
  try {
    const user = await auth.getUserByEmail(email);
    return { user, created: false };
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
    const user = await auth.createUser({
      email,
      password: DEFAULT_PASSWORD,
      displayName,
      emailVerified: true,
      disabled: false,
    });
    return { user, created: true };
  }
}

async function uploadCvAndGetFields(uid, usernameLower) {
  const localCvPath = path.resolve(__dirname, "seed_cvs", `${usernameLower}.pdf`);

  if (!fs.existsSync(localCvPath)) {
    const cvsDir = path.resolve(__dirname, "seed_cvs");
    let existing = [];
    try {
      if (fs.existsSync(cvsDir)) existing = fs.readdirSync(cvsDir).map((f) => f.toLowerCase());
    } catch (_) {}
    throw new Error(
      `CV bulunamadı: ${localCvPath}\nMevcut dosyalar: ${existing.join(", ")}`
    );
  }

  const fileName = `${usernameLower}.pdf`;
  const storagePath = `users/${uid}/cv/${fileName}`;

  await bucket.upload(localCvPath, {
    destination: storagePath,
    metadata: { contentType: "application/pdf" },
  });

  const file = bucket.file(storagePath);

  const [url] = await file.getSignedUrl({
    action: "read",
    expires: "03-01-2035",
  });

  return {
    cvName: `${usernameLower} CV`,
    cvPdfFileName: fileName,
    cvPdfStoragePath: storagePath,
    cvPdfUrl: url,
    cvUrl: url,
    cvPdfUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    cvParseStatus: "uploaded",
    cvTextHash: "",
  };
}

async function writeUserAndUsername(uid, userDoc) {
  const userRef = db.collection("users").doc(uid);
  const usernameRef = db.collection("usernames").doc(userDoc.usernameLower);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(usernameRef);
    if (snap.exists) {
      const owner = snap.data()?.uid;
      if (owner && owner !== uid) {
        throw new Error(`USERNAME_TAKEN: ${userDoc.usernameLower} owned by ${owner}`);
      }
    }

    tx.set(userRef, userDoc, { merge: true });
    tx.set(usernameRef, { uid }, { merge: true });
  });
}

async function main() {
  console.log("Seed start (first 5 users + CV upload)...");

  let ok = 0, fail = 0;

  for (const u of seed) {
    try {
      const { user, created } = await createOrGetAuth(u.email, u.name);

      const baseDoc = buildUserDocBase(u);
      const cvFields = await uploadCvAndGetFields(user.uid, baseDoc.usernameLower);

      const finalDoc = { ...baseDoc, ...cvFields };

      await writeUserAndUsername(user.uid, finalDoc);

      ok++;
      console.log(
        `OK | ${u.email} | ${u.username} | uid=${user.uid} | authCreated=${created} | cv=${baseDoc.usernameLower}.pdf`
      );
    } catch (err) {
      fail++;
      console.error(`FAIL | ${u.email} | ${u.username} | ${err.message || err}`);
    }
  }

  console.log(`Done. Success=${ok} Fail=${fail}`);
  console.log(`Test password for all seeded users: ${DEFAULT_PASSWORD}`);
  console.log(`Bucket: ${bucket.name}`);
  console.log(`CV local folder: tools/seed_cvs/{username}.pdf`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
