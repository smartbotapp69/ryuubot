# Batas Import Node ke Go

Database Node lama dipakai sebagai sumber baca saja.

## Yang diimport

- User: legacy ID, username, email, status, dan bcrypt password hash.
- Bonus referral: saldo bonus per user dan coin.

## Yang tidak diimport

- Saldo wallet/provider.
- Sesi login.
- Sesi trading dan riwayat roll.
- Taruhan provider.
- Pengaturan bot user lama.
- Subscription lama.
- Settlement fee dan owner payout.
- Sesi browser/JWT Ryubot lama.

## Aturan saldo

Saldo wallet user tidak boleh diisi dari hasil import atau tabel Ryubot.
Saat user membuka aplikasi atau trading aktif, aplikasi membaca saldo live dari
socket Pasino. Database Go hanya menyimpan ledger internal, misalnya bonus
referral, operasi transfer, serta fee/kewajiban yang belum selesai.

## Bonus yang diimport

Setiap saldo bonus lama diimport sebagai event `IMPORT_OPENING` yang memiliki
external ID unik. Dengan begitu import dapat dijalankan ulang tanpa menggandakan
bonus. Setelah cutover, bonus baru hanya dibuat oleh sistem Go.

## Data Pasino yang ikut diimport

Untuk menjaga alur aplikasi lama, Go mengimport data Pasino berikut per user:

- provider username dan email;
- password provider yang sudah terenkripsi;
- access token dan waktu kedaluwarsanya;
- socket token dan waktu kedaluwarsanya.

Token yang sudah kedaluwarsa akan diperbarui dengan alur refresh/login Pasino
yang sama seperti Node. User tidak dipaksa memasukkan ulang password Pasino
hanya karena aplikasi berpindah ke Go.

Sesi browser/JWT Ryubot lama sengaja tidak diimport karena ditandatangani dengan
secret aplikasi lama. User tetap login memakai username dan password Ryubot
yang sama; setelah itu Go membuat sesi browser baru yang aman.
