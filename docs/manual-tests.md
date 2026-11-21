# Elle yapılacak testler

CI her güncellemede görüntüyü, biçimlendirme komutlarını, link tamamlamayı, resim
yapıştırmayı, Hugo önizlemesini ve yazma hızını otomatik sınıyor. Ama fareyle tıklama,
sürükle-bırak, açılan pencerelerin görünüşü ve "elde nasıl hissettiriyor" gibi şeyleri
sınayamıyor. Bu liste onlar için.

**Nasıl kullanılır:** Uygulamayı derle (`scripts/build_app.sh`), `Samples/Welcome.md`'yi aç ve
sırayla dene. Bir sorun görürsen test numarasıyla birlikte yaz (ör. "L3: link yeni pencerede
değil, aynı pencerede açıldı"). Geçenleri işaretlemen yeterli.

Son güncelleme: 21 Kasım 2026 (odak modu, yazı genişliği ve 10 yeni arayüz dili eklendi)

---

## A. Açılış ve genel

- [ ] **A1** — Uygulama açılıyor; Dock'ta ikon (M↓ ve yıldızlar) görünüyor.
- [ ] **A2** — Slopdown → Slopdown Hakkında: turuncu "⚠︎ Vibe-coded" uyarısı **Türkçe** görünüyor.
- [ ] **A5** — Mac'in dili Türkçeyken menüler, araç çubuğu ipuçları, durum çubuğu ve uyarı pencereleri Türkçe. Sistem Ayarları → Genel → Dil ve Bölge → Uygulamalar'dan Slopdown'u İngilizceye alınca her şey İngilizce. Çevirisi tuhaf ya da kesilen metin varsa ekran görüntüsüyle yaz.
- [ ] **A6** — Slopdown'u Sistem Ayarları → Genel → Dil ve Bölge → Uygulamalar'dan sırayla Almanca, Japonca ve Arapçaya al. Menüler o dilde. Arapçada menüler ve pencere sağdan sola dizilebilir; editörün içindeki madde işaretleri, alıntı çizgileri ve durum çubuğu bozuluyor mu bak (bilinen sınırlama, ama ne kadar kötü olduğunu bilmek istiyorum).
- [ ] **A3** — Açık ve koyu modda (Sistem Ayarları → Görünüm) metin, kod blokları, tablo, alıntı çizgisi okunaklı.
- [ ] **A4** — Pencereyi daralt/genişlet: metin ortalı kalıyor, resimler genişliğe göre küçülüyor.

## E. Canlı önizleme ve yazma

- [ ] **E1** — İmleci bir **kalın** kelimenin içine götür: `**` işaretleri görünüyor; çıkınca kayboluyor.
- [ ] **E2** — Başlık satırına gelince `#` görünüyor; satırdan çıkınca kayboluyor.
- [ ] **E3** — Görev kutusuna tıkla: işaretleniyor, metin üstü çiziliyor; ⌘Z geri alıyor.
- [ ] **E4** — Tabloya tıkla: tablo ham markdown'a dönüyor; dışarı çıkınca yeniden ızgara.
- [ ] **E5** — Hızlı yazarken takılma/titreme yok (uzun bir notta da dene: Welcome.md'yi birkaç kez kopyala-yapıştır).
- [ ] **E6** — ⌘E ile kaynak moduna geçip geri dön; görünüş bozulmuyor.
- [ ] **E7** — ⌘F arama çubuğu açılıyor, buluyor, ⌘G sonraki.

## T. Araç çubuğu, menüler, durum çubuğu

- [ ] **T1** — Bir kelime seç, araç çubuğunda **B**, *I*, ~~S~~, `</>` düğmelerine bas: biçim uygulanıyor; tekrar basınca kalkıyor.
- [ ] **T2** — "Aa" başlık menüsü: Başlık 1–6 ve Paragraf çalışıyor.
- [ ] **T3** — Lists menüsü: madde, numaralı, görev listesi ve alıntı seçili satırların hepsine uygulanıyor.
- [ ] **T4** — Araç çubuğuna sağ tık → Customize Toolbar: düğmeler eklenip çıkarılabiliyor.
- [ ] **T5** — Durum çubuğunda satır/sütun, kelime, karakter sayısı güncelleniyor; metin seçince seçimin sayıları görünüyor.
- [ ] **T6** — Durum çubuğundaki dosya yoluna tıkla: Finder'da dosya seçili açılıyor.

## F. Odak modu ve yazı genişliği

- [ ] **F1** — ⇧⌘D: araç çubuğu ve durum çubuğu kayboluyor, imlecin olduğu paragraf parlak, geri kalan her şey (resimler dahil) soluk.
- [ ] **F2** — Odak modunda ok tuşlarıyla paragraflar arasında gez: parlak alan imleçle birlikte kayıyor, titreme yok. Başlık satırında yalnızca o başlık, listede yalnızca o madde parlak.
- [ ] **F3** — Odak modunda yaz: yeni satırlar parlak alanda kalıyor; boş satır bırakıp yazınca yeni paragraf parlıyor.
- [ ] **F4** — Esc ya da tekrar ⇧⌘D: her şey normale dönüyor, araç çubuğu ve durum çubuğu geri geliyor. Tamamlama listesi açıkken Esc önce yalnızca listeyi kapatıyor.
- [ ] **F5** — Görüntü → Yazı Genişliği (⌥⌘1–4): Dar, Orta, Geniş, Tam Genişlik; metin sütunu hemen değişiyor, resimler yeni genişliğe uyuyor. Seçili olanın yanında onay işareti var.
- [ ] **F6** — İki not açıkken genişliği değiştir: ikisi de değişiyor. Uygulamayı kapatıp açınca seçim korunuyor.

## L. Linkler

- [ ] **L1** — ⌘ basılıyken bir linkin üstüne gel: imleç el işaretine dönüyor.
- [ ] **L2** — ⌘+tık `[[Second Note]]`: not **yeni pencerede** açılıyor (sekme değil).
- [ ] **L3** — ⌘+tık `[[Not Written Yet]]`: pencerede oluşturulacak dosyanın tam yolu yazıyor. "Create New File" dosyayı notun klasöründe oluşturup açıyor.
- [ ] **L4** — Olmayan bir linkte "Choose File…" ile başka bir not seç: link metni o dosyaya göre değişiyor, ⌘Z geri alıyor.
- [ ] **L5** — `[[../../Library/deneme]]` yazıp ⌘+tık → Create: notun klasörü dışında olduğu için **ikinci bir onay** istiyor.
- [ ] **L6** — ⌘+tık `https://github.com`: tarayıcıda açılıyor.
- [ ] **L7** — `[test](ssh://localhost)` yazıp ⌘+tık: adresi tam gösteren **onay** penceresi çıkıyor.
- [ ] **L8** — Notun yanına `deneme.command` adlı bir dosya koy, `[x](deneme.command)` linkine ⌘+tık: dosya **açılmıyor**, "Show in Finder" öneriliyor.
- [ ] **L9** — Gömülü not kutusuna ⌘+tık: o not açılıyor.

## C. Link tamamlama

- [ ] **C1** — Boş bir satıra `[[sec` yaz: imlecin altında liste açılıyor, "Second Note" en üstte.
- [ ] **C2** — ↑↓ ile seç, Return: `[[Second Note]]` ekleniyor, liste kapanıyor. Tab da çalışıyor.
- [ ] **C3** — Liste açıkken Esc: liste kapanıyor, yazılan metin kalıyor.
- [ ] **C4** — Listeye fareyle tıkla: seçilen öğe ekleniyor.
- [ ] **C5** — ⇧⌘K: `[[]]` ekleniyor ve liste kendiliğinden açılıyor.
- [ ] **C6** — `![[ink` yaz: listede `inkwell.png` resmi de çıkıyor.
- [ ] **C7** — Liste ekranın altına taşıyorsa satırın üstünde açılıyor.

## Q. Hızlı açma ve başlıklar

- [ ] **Q1** — ⌘P: pencerenin üstünde arama kutusu açılıyor; yazdıkça klasördeki notlar süzülüyor; ↑↓ ve Return ile seçilen not yeni pencerede açılıyor; Esc kapatıyor.
- [ ] **Q2** — Hugo sitesinde ⌘P: sayfalar frontmatter başlıklarıyla listeleniyor.
- [ ] **Q3** — ⇧⌘O: notun başlıkları düzeyine göre girintili listeleniyor; seçince imleç o başlığa gidiyor.
- [ ] **Q4** — Arama kutusu açıkken başka bir pencereye tıklayınca kutu kapanıyor.

## I. Resimler

- [ ] **I1** — Bir ekran görüntüsü al (⌃⇧⌘4 → panoya), notta ⌘V: `pasted-image-…png` dosyası notun yanına kaydediliyor, `![[…]]` ekleniyor, resim görünüyor.
- [ ] **I2** — Finder'dan notun klasörü **dışındaki** bir resmi nota sürükle: resim notun klasörüne kopyalanıyor, link ekleniyor.
- [ ] **I3** — Notun klasöründeki bir resmi sürükle: kopyalanmadan olduğu yerden linkleniyor.
- [ ] **I4** — Metin kopyalayıp yapıştırmak (resim değil) eskisi gibi düz metin yapıştırıyor.
- [ ] **I5** — ⇧⌘E ile `![[]]` eklenip liste açılıyor.

## H. Hugo (`Samples/hugo-site/content/posts/first.md`; Hugo kurulu olmalı: `brew install hugo`)

- [ ] **H1** — Durum çubuğunun solunda "Hugo · relref links" görünüyor; menüsünden link stilini değiştirince ⌘K'nın eklediği link de değişiyor.
- [ ] **H2** — ⌘K: `[]({{< relref "" >}})` ekleniyor, imleç tırnakların arasında; yazmaya başlayınca sayfa listesi başlıklarıyla açılıyor.
- [ ] **H3** — `[[wiki link]]` turuncu ve noktalı altı çizili; üstüne gelince açıklama balonu çıkıyor.
- [ ] **H4** — İlk önizlemede "Run this Hugo site's build?" onayı geliyor; ikinci seferde sormuyor.
- [ ] **H5** — ⇧⌘P önizleme paneli: sayfa temasıyla açılıyor; yazdıkça birkaç saniye içinde güncelleniyor.
- [ ] **H6** — Panel açıkken editörü kaydır: panel **aynı başlığa** kayıyor (sayfanın başında tema başlığı/menü olsa da).
- [ ] **H7** — Paneldeki bir site içi linke tıkla: panelde açılıyor. Dış bir linke tıkla: tarayıcıda açılıyor.
- [ ] **H8** — ⌥⌘P: sayfa tarayıcıda açılıyor.
- [ ] **H9** — File → New Hugo Page…: frontmatter'ı (title, date, draft) dolu yeni sayfa açılıyor.
- [ ] **H10** — ⇧⌘E: resim seçme penceresi; seçilen resim `static/images`'a kopyalanıp `![](/images/…)` ekleniyor.
- [ ] **H11** — Sitenin bütün pencerelerini kapat: Etkinlik Monitörü'nde `hugo` süreci kayboluyor.
- [ ] **H13** — Çok dilli bir sitede (`yazi.tr.md` gibi dosyalar ya da `content/tr` klasörü): Türkçe sayfadan ⌘K ile eklenen linkin tamamlama listesinde yalnızca Türkçe sayfalar var; ⌘+tık Türkçe çeviriyi açıyor; olmayan sayfa `.tr.md` olarak oluşturuluyor.
- [ ] **H12** — Hugo kurulu değilken (ya da PATH'te yokken) önizleme: "Hugo isn't installed / brew install hugo" mesajı.

## D. Dosya ve belge davranışı

- [ ] **D1** — Yazıp pencereyi kapat: soru sormadan kaydediyor (otomatik kaydetme); tekrar açınca değişiklik orada.
- [ ] **D2** — File → Revert to Saved / Browse All Versions çalışıyor.
- [ ] **D3** — File → Rename… ve Move To… sonrası linkler ve resimler hâlâ çözülüyor.
- [ ] **D4** — Not açıkken dosyayı başka bir editörde değiştir: Slopdown yeni içeriği yüklüyor.
- [ ] **D5** — Not açıkken klasöre yeni bir not ekle: o nota giden soluk (kırık) link birkaç saniye içinde normal renge dönüyor.
