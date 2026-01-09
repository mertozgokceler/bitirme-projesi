/**
 * ULTRA SAFE cleanup:
 * - SADECE users/{uid}.isSeedUser === true ise siler
 * - Domain kontrolü opsiyonel; burada ekstra sigorta olarak da bırakıldı
 */

const admin = require("firebase-admin");
const path = require("path");

const serviceAccount = require(path.resolve(__dirname, "serviceAccountKey.json"));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const auth = admin.auth();

const SEED_EMAIL_DOMAIN = "@techconnect.app";

// Seed usernameLower listesi (doc id’ler)
const seedUsernames = [
  "ahmetyilmaz","elifkaya","mehmetdemir","zeyneparslan","canozkan",
  "aysesahin","burakcelik","senakoc","emreaksoy","merveaydin",
  "kerempolat","eceyurt","onurkaraca","buseerdem","furkanyildirim",
  "dilaramutlu","serkantopal","iremgunes","okansezer","meliskurt",
];

async function cleanupOne(usernameLower) {
  const usernameRef = db.collection("usernames").doc(usernameLower);
  const usernameSnap = await usernameRef.get();

  if (!usernameSnap.exists) {
    console.log(`SKIP: ${usernameLower} (username doc yok)`);
    return { deleted: false };
  }

  const uid = usernameSnap.data()?.uid;
  if (!uid) {
    console.log(`SKIP: ${usernameLower} (uid yok)`);
    return { deleted: false };
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();

  // 🔒 users doc yoksa bile güvenli davran: silme.
  if (!userSnap.exists) {
    console.log(`PROTECTED: ${usernameLower} (users doc yok, silmiyorum)`);
    return { deleted: false };
  }

  const userData = userSnap.data() || {};

  // ✅ En güçlü güvenlik: sadece seed flag true ise sil
  if (userData.isSeedUser !== true) {
    console.log(`PROTECTED: ${usernameLower} (isSeedUser true değil)`);
    return { deleted: false };
  }

  // Ekstra sigorta: domain kontrolü (istersen kaldır)
  let authUser;
  try {
    authUser = await auth.getUser(uid);
  } catch (e) {
    console.log(`SKIP: ${usernameLower} (auth user yok)`);
    // isSeedUser true ama auth yoksa: sadece firestore temizlenebilir
    await db.runTransaction(async (tx) => {
      tx.delete(userRef);
      tx.delete(usernameRef);
    });
    console.log(`DELETED(FS only): ${usernameLower}`);
    return { deleted: true };
  }

  if (!authUser.email || !authUser.email.endsWith(SEED_EMAIL_DOMAIN)) {
    console.log(`PROTECTED: ${authUser.email} (domain koruması)`);
    return { deleted: false };
  }

  // 🧨 Sil
  await db.runTransaction(async (tx) => {
    tx.delete(userRef);
    tx.delete(usernameRef);
  });

  await auth.deleteUser(uid);

  console.log(`DELETED: ${authUser.email} | ${usernameLower}`);
  return { deleted: true };
}

async function main() {
  console.log("ULTRA SAFE cleanup started...");

  let deleted = 0;
  let protectedCount = 0;

  for (const uname of seedUsernames) {
    try {
      const res = await cleanupOne(uname);
      if (res.deleted) deleted++;
      else protectedCount++;
    } catch (err) {
      protectedCount++;
      console.error(`FAIL: ${uname}`, err.message || err);
    }
  }

  console.log(`Cleanup finished. Deleted=${deleted}, Protected/Skipped=${protectedCount}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
