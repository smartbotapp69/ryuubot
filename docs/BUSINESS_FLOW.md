# Mekanisme Bisnis Ryubot

Status: **draf—sebagian aturan telah dikonfirmasi owner**.  
Dokumen ini hanya membahas bisnis, bukan teknis aplikasi.

## 1. Tujuan aplikasi

Ryubot membantu user menjalankan trading otomatis pada akun Pasino berdasarkan
pengaturan yang dipilih user.

Ryubot juga mengelola:

- akun dan masa aktif user;
- referral dan bonus;
- pembagian hasil trading;
- laporan saldo dan riwayat transaksi.

## 2. User dan akun Pasino

1. User mendaftar melalui Ryubot.
2. Setiap user terhubung dengan satu akun Pasino.
3. User login ke Ryubot untuk mengatur dan menjalankan bot.
4. Satu user hanya boleh memiliki satu sesi login dan satu sesi trading aktif.
5. User nonaktif, terhapus, atau masa aktifnya habis tidak boleh memulai trading.

Perlu dikoreksi:

- Apakah akun Pasino dibuat oleh Ryubot atau sudah dimiliki user?
- Apakah satu akun Pasino boleh digunakan manual ketika bot aktif?

### Migrasi dari aplikasi lama

Keputusan owner: user, bonus referral, serta akun/token Pasino diambil dari
aplikasi Node lama. Saldo wallet tidak diimport. Setelah pindah, saldo wallet
selalu dibaca live dari socket Pasino. Alur login dan register tetap sama.

## 3. Saldo

Ada tiga saldo yang perlu dibedakan:

- **Saldo Pasino**: saldo aktual pada akun provider.
- **Saldo tertahan**: fee atau kewajiban yang belum dibayarkan.
- **Saldo tersedia**: saldo Pasino dikurangi saldo tertahan.

Bot hanya boleh memakai saldo tersedia.

Pada halaman user sebaiknya ditampilkan:

```text
Saldo Pasino
Saldo tertahan
Saldo tersedia
```

Dengan pemisahan ini, saldo yang tertahan tidak terlihat seperti saldo hilang.

Ketentuan yang telah dikonfirmasi owner:

- Ketika aplikasi pertama dibuka, saldo awal wajib dibaca langsung dari socket
  Pasino, bukan memakai cache atau saldo sesi lama.
- Selama trading berjalan, saldo yang ditampilkan kepada user adalah **saldo
  bersih milik user setelah seluruh fee dari hasil trading dikurangi**.
- Saldo tidak boleh terlihat lebih besar hanya karena fee belum ditransfer ke
  penerima.
- Setiap perbedaan antara saldo Pasino dan saldo bersih harus dapat dijelaskan
  sebagai fee/kewajiban yang tercatat, tidak boleh ada selisih tanpa ledger.

## 4. Trading otomatis

Setiap user mempunyai pengaturan trading sendiri di database. Pengaturan satu
user tidak boleh memengaruhi user lain.

User menentukan melalui menu pengaturan:

- coin;
- taruhan awal;
- chance;
- jeda setiap roll;
- aturan kenaikan taruhan setelah menang atau kalah;
- aturan reset taruhan;
- take profit;
- stop loss;
- batas saldo;
- stop setelah menang jika diperlukan.

Nominal taruhan berikutnya tidak ditentukan oleh satu rumus global. Bot
mengikuti pengaturan martingale, reset, boom, dan batas yang disimpan untuk
user tersebut.

Alur trading:

1. Ryubot membaca saldo Pasino.
2. Ryubot memastikan saldo cukup dan tidak ada sesi lain.
3. Ryubot membuat sesi trading.
4. Bot mengirim satu taruhan.
5. Bot menunggu hasil taruhan tersebut.
6. Setelah hasil pasti, bot menghitung profit dan taruhan berikutnya.
7. Proses berulang sampai user menghentikan bot atau batas tercapai.

Bot tidak boleh mengirim taruhan baru jika hasil taruhan sebelumnya belum pasti.

Jika koneksi terputus atau respons Pasino tidak jelas, trading dihentikan untuk
diperiksa. Taruhan tersebut tidak boleh dikirim ulang otomatis.

Ketika sesi dimulai, seluruh pengaturan user disalin sebagai snapshot ke sesi.
Dengan demikian, histori dapat menjelaskan mengapa setiap taruhan mempunyai
nominal tertentu meskipun pengaturan user kemudian berubah.

Jika user mengubah pengaturan ketika trading sedang aktif, roll yang sedang
diproses tetap memakai pengaturan lama. Pengaturan baru mulai berlaku pada roll
berikutnya setelah hasil roll aktif sudah pasti.

## 5. Pembagian kemenangan

Aturan yang telah dikonfirmasi owner:

| Penerima | Bagian |
|---|---:|
| User | 86% |
| Akun penampung | 12% |
| Akun `kangden69` | 2% |

Total pembagian setiap hasil positif adalah tepat 100%.

```text
Gross profit 100%
├── User 86%
├── Akun penampung 12%
└── kangden69 2%
```

Kerugian ditanggung dari saldo user. Pembagian hanya dilakukan ketika hasil
taruhan positif. Username `kangden69` bebas fee trading, sehingga hasil positif
milik akun tersebut tidak dipotong 12% maupun 2%.

Perlu dikonfirmasi lebih lanjut: ketika `kangden69` trading, apakah bonus
referral juga tidak dibuat karena tidak ada alokasi 12% ke akun penampung?

## 6. Referral

Aturan aplikasi lama:

| Tingkat | Bonus |
|---|---:|
| Level 1 | 1,5% |
| Level 2 | 0,9% |
| Level 3 | 0,6% |

Total bonus referral adalah 3% dari gross profit.

Bonus referral diambil dari alokasi 12% akun penampung, bukan biaya tambahan
dan bukan potongan dari bagian user. Setelah kewajiban referral dikurangi,
sisa saldo akun penampung menjadi hak owner dan operasional.

```text
Akun penampung menerima 12% gross profit
├── Maksimum 3% gross profit untuk referral level 1–3
└── Sisanya untuk owner dan operasional
```

Perlu dikonfirmasi:

- Jika suatu level upline tidak ada, apakah jatah level tersebut tetap menjadi
  saldo owner/operasional atau dialihkan ke pihak lain?
- Apakah upline nonaktif masih memperoleh bonus?

Bonus dikumpulkan sebagai saldo bonus dan dapat diklaim setelah mencapai batas
minimum.

## 7. Klaim bonus

Batas minimum lama:

| Coin | Minimum klaim |
|---|---:|
| TRX | 30 |
| DOGE | 50 |
| FLOKI | 250.000 |
| BTT | 20.000.000 |

Alur:

1. User meminta klaim.
2. Sistem memeriksa saldo bonus.
3. Bonus dikirim ke akun Pasino user.
4. Jika pengiriman berhasil, saldo bonus dikurangi.
5. Jika hasil transfer tidak jelas, klaim ditahan untuk pemeriksaan dan tidak
   dikirim ulang otomatis.

## 8. Deposit, withdrawal, dan transfer

User dapat:

- melihat alamat deposit;
- melakukan withdrawal;
- mentransfer coin ke username Pasino;
- melihat riwayat transaksi.

Withdrawal dan transfer tidak boleh dilakukan ketika trading masih aktif atau
masih ada taruhan yang hasilnya belum pasti.

## 9. Langganan

Aturan lama:

- Harga: 22 TRX per bulan.
- Trial user baru: 2 hari.
- Pembayaran memperpanjang masa aktif dari tanggal kedaluwarsa terakhir atau
  dari hari pembayaran jika sudah kedaluwarsa.
- Dari 22 TRX, upline memperoleh 3 TRX.
- Sisa 19 TRX menjadi bagian akun penampung/management.

```text
Pembayaran 22 TRX
├── Upline 3 TRX
└── Akun penampung/management 19 TRX
```

Perlu dikoreksi:

- Ke akun mana pembayaran 22 TRX pertama kali dikirim?
- Apakah campaign September 2026 dihapus dan selalu memakai pembagian 3/19?
- Jika user tidak mempunyai upline, 3 TRX menjadi milik siapa?

## 10. Pembagian owner

Aturan yang telah dikonfirmasi owner:

- Dilakukan pukul 13:00 dan 18:00 WIB.
- Hanya saldo yang tidak menjadi kewajiban user/referral yang boleh dibagikan.

| Penerima | Bagian |
|---|---:|
| Kang Nana | 30% |
| Kang Deni | 30% |
| Pak Arya | 30% |
| Operasional | 10% |

Pembagian ini diterapkan pada sisa hak akun penampung setelah seluruh kewajiban
referral dan kewajiban user dikurangi.

Perlu dikoreksi:

- Apakah jadwal 13:00 dan 18:00 WIB masih berlaku?
- Apakah semua coin dibagikan atau hanya TRX?

## 11. Ketika server bermasalah

Jika server mati atau koneksi Pasino terputus:

1. Status sesi dan taruhan terakhir dibaca dari database.
2. Bot memastikan hasil taruhan terakhir terlebih dahulu.
3. Jika hasil dapat dibuktikan, sesi dapat dilanjutkan atau diselesaikan.
4. Jika hasil tidak dapat dibuktikan, sesi menunggu pemeriksaan admin.
5. Bot tidak mengulang taruhan atau transfer yang hasilnya belum jelas.

## 12. Keputusan yang diperlukan

Keputusan yang masih diperlukan:

1. Apakah akun `kangden69` yang bebas fee tetap menghasilkan bonus referral.
2. Apakah upline nonaktif tetap memperoleh bonus.
3. Tujuan awal pembayaran subscription dan nasib 3 TRX jika tidak ada upline.
4. Apakah campaign September 2026 dihapus.
5. Jadwal pembagian owner dan coin yang ikut dibagikan.

Setelah keputusan ini dikoreksi, dokumen dapat dijadikan aturan resmi dan
diterjemahkan menjadi automated test.

## 13. Konfigurasi di database

Angka dan aturan yang mungkin berubah tidak ditulis permanen di source code.
Konfigurasi disimpan di database agar dapat diubah tanpa build ulang aplikasi.

### Aturan global

Dikelola admin dan berlaku untuk seluruh user:

- Persentase user, akun penampung, dan `kangden69`.
- Persentase referral level 1–3.
- Minimum bet, withdrawal, dan claim per coin.
- Harga subscription dan reward upline.
- Pembagian owner dan operasional.
- Jadwal pembagian owner.
- Username akun penerima.
- Daftar coin aktif.

### Pengaturan per user

Dikelola masing-masing user:

- Coin dan base bet.
- Chance.
- Delay roll.
- Martingale setelah win/loss.
- Reset setelah win/loss.
- Boom setelah kondisi tertentu.
- Take profit dan stop loss.
- Batas saldo dan stop-on-win.

### Ketentuan perubahan

- Nominal disimpan sebagai decimal, bukan angka pecahan biner.
- Persentase mempunyai batas dan total pembagian wajib tepat 100%.
- Perubahan aturan global hanya dapat dilakukan admin berwenang.
- Setiap perubahan menyimpan nilai lama, nilai baru, admin, alasan, dan waktu.
- Aturan global memiliki nomor versi dan waktu mulai berlaku.
- Sesi trading menyimpan versi aturan global serta snapshot pengaturan user.
- Histori lama selalu dihitung dengan konfigurasi yang berlaku ketika transaksi
  dibuat, bukan konfigurasi terbaru.
- Perubahan recipient tidak boleh mengubah tujuan payout yang sudah berstatus
  diproses atau menunggu pemeriksaan.
