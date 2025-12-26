# TechConnect  
## Yapay Zekâ Destekli Yazılımcı – İşveren Eşleştirme Mobil Uygulaması

TechConnect, yazılım geliştiriciler ile teknoloji şirketlerini tek bir platformda buluşturan, yapay zekâ destekli bir mobil uygulamadır.  
Bu proje, Bartın Üniversitesi Bilgisayar Mühendisliği Bitirme Projesi kapsamında geliştirilmiştir.

Uygulama; ilan paylaşımı, başvuru süreçleri, gerçek zamanlı iletişim ve yapay zekâ destekli analizler ile modern işe alım süreçlerini dijital ve akıllı bir yapıya taşımayı hedeflemektedir.

---

## 🎯 Projenin Amacı

Bu projenin temel amacı, klasik CV odaklı ve manuel işe alım süreçlerinin yetersizliklerini gidermek ve:

- Aday–ilan uyumunu daha doğru analiz etmek  
- Yazılımcıların yetkinliklerini yalnızca anahtar kelimelere bağlı kalmadan değerlendirmek  
- İşverenlerin uygun adaylara daha hızlı ulaşmasını sağlamak  
- Yapay zekâ destekli geri bildirimlerle adayların gelişimine katkı sunmak  

şeklinde özetlenebilecek daha verimli bir istihdam platformu oluşturmaktır.

---

## 🚀 Proje Kapsamı ve Sunulan Özellikler

- 👤 **Bireysel ve Kurumsal Kullanıcı Yapısı**
- 📄 **İlan Oluşturma ve Başvuru Yönetimi**
- 💬 **Gerçek Zamanlı Mesajlaşma**
- 📞 **Sesli ve Görüntülü Görüşme Altyapısı**
- 🤖 **Yapay Zekâ Destekli CV Analizi**
- 🎯 **Aday – İlan Uyum Analizi**
- 📊 **Eksik Yetkinlik ve Gelişim Geri Bildirimleri**
- 🔔 **Uygulama İçi Bildirim Sistemi**
- 🌙 **Karanlık / Aydınlık Tema Desteği**

---

## 🧠 Yapay Zekâ Yaklaşımı

Projede yapay zekâ modeli doğrudan eğitilmemiştir.  
Bunun yerine **OpenAI GPT API** kullanılarak hazır bir büyük dil modeli üzerinden analiz ve öneri servisleri alınmıştır.

Yapay zekâ aşağıdaki alanlarda kullanılmıştır:
- CV içeriklerinin metinsel analizi  
- Adayın ilana uygunluk değerlendirmesi  
- Eksik veya geliştirilmesi gereken yetkinliklerin belirlenmesi  
- Adaya özel kariyer ve başvuru önerilerinin oluşturulması  

Bu yaklaşım sayesinde sistem, yüksek maliyetli model eğitimi gerektirmeden ölçeklenebilir bir yapıya kavuşmuştur.

---

## 🏗️ Sistem Mimarisi

Proje, istemci ve bulut tabanlı servislerden oluşan modüler bir mimari ile tasarlanmıştır.

- **Mobil Uygulama:** Flutter (Dart)
- **Kimlik Doğrulama:** Firebase Authentication
- **Veri Yönetimi:** Firebase Firestore ve Realtime Database
- **Dosya Depolama:** Firebase Storage
- **Sunucu Tarafı İşlemler:** Firebase Functions (Node.js)
- **Gerçek Zamanlı İletişim:** WebRTC
- **Yapay Zekâ Entegrasyonu:** OpenAI GPT API

---

## 🛠️ Kullanılan Teknolojiler

| Alan | Teknoloji |
|----|----|
| Mobil Geliştirme | Flutter (Dart) |
| Backend Servisleri | Firebase Functions (Node.js) |
| Veritabanı | Firebase Firestore |
| Kimlik Doğrulama | Firebase Authentication |
| Yapay Zekâ | OpenAI GPT API |
| Gerçek Zamanlı İletişim | WebRTC |
| Bildirim Sistemi | Firebase Cloud Messaging |

---

## 📄 Akademik Bilgiler

- **Üniversite:** Bartın Üniversitesi  
- **Bölüm:** Bilgisayar Mühendisliği  
- **Ders:** Bitirme Projesi  
- **Proje Sahibi:** Mert Özgökçeler  

---

## 📌 Açıklamalar

- Bu depo, bitirme projesinin yazılım geliştirme sürecini ve proje yapısını belgelemek amacıyla oluşturulmuştur.
- Güvenlik ve gizlilik gerekçeleriyle ortam değişkenleri ve özel anahtarlar repoya dahil edilmemiştir.
- Proje, ölçeklenebilirlik ve modülerlik esas alınarak geliştirilmiştir.

---
