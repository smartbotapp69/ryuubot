# Admin Panel Ryubot

Panel admin adalah bagian dari binary Go yang sama. Tidak ada service frontend
tambahan dan seluruh angka bisnis disimpan di database.

## Menu

- Dashboard: pintu masuk seluruh pengaturan.
- Trading & Fee: bagian user, akun penampung, `kangden69`, dan username bebas
  fee.
- Referral: persentase level 1, 2, dan 3.
- Subscription: harga, reward upline, management, dan trial.
- Owner & Jadwal: pembagian Nana, Deni, Arya, operasional, serta cutoff.
- Coin & Minimum: minimum bet, withdrawal, dan minimum klaim bonus untuk TRX,
  DOGE, FLOKI, dan BTT.

## Penyimpanan

Setiap halaman memiliki satu tombol `Simpan`.

```text
Ubah angka → Simpan → validasi → langsung tersimpan di database
```

Tidak ada alasan perubahan, draft, atau aktivasi kedua.

Riwayat tetap disimpan otomatis: admin, waktu, nilai lama, dan nilai baru.

## Validasi

Database menolak nilai yang tidak sesuai:

- Pembagian trading harus total 100%.
- Total referral tidak boleh melebihi bagian akun penampung.
- Upline + management subscription harus sama dengan harga subscription.
- Pembagian owner harus total 100%.
- Angka minimum tidak boleh negatif.
- Waktu cutoff harus memakai format jam yang valid.

## Dampak perubahan

- Tidak perlu build atau deploy ulang untuk mengganti angka bisnis.
- Transaksi dan roll baru memakai nilai terbaru.
- Roll yang sedang berjalan tetap memakai snapshot pengaturan saat roll itu
  dimulai; perubahan mulai berlaku pada roll berikutnya.
- Riwayat lama tidak dihitung ulang dengan nilai baru.

Password, key enkripsi, URL database, token Pasino, dan secret tetap berada di
environment/secret manager, bukan di panel admin.
