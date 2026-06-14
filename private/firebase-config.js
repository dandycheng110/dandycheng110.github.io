// =============================================================
//  Firebase 設定 / config
//  建立 Firebase 專案後，到 Console「專案設定 → 你的應用程式」
//  複製 firebaseConfig，貼到下面取代佔位符。
//  ⚠️ apiKey 不是密碼，可以公開——真正的把關靠 Firestore 安全規則。
// =============================================================
export const firebaseConfig = {
  apiKey:            "PASTE_YOUR_API_KEY",
  authDomain:        "PASTE_PROJECT.firebaseapp.com",
  projectId:         "PASTE_PROJECT",
  storageBucket:     "PASTE_PROJECT.appspot.com",
  messagingSenderId: "PASTE_SENDER_ID",
  appId:             "PASTE_APP_ID"
};

// 管理員 Email（可多個）。這些帳號能上傳/刪除私人筆記、核准其他人。
// 必須和 firestore.rules 裡 isAdmin() 的清單一致。
export const ADMIN_EMAILS = ["dot1000110@gmail.com"];
