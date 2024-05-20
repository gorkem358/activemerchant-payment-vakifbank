# ActiveMerchant Vakıfbank Payment Gateway

Bu repo içerisinde activemerchant reposunu extend ederek Vakıfbank ödeme yöntemini entegre ettim.

## Kurulum

### (Docker kullanılacağı varsayılır)<br>
Projeyi lokal ortama çektikten sonra docker-compose up --build diyerek projenin docker ortamında ayağı kalkması beklenir.
```
localhost:3000/payment -> Ödeme formunun bulunduğu bulunduğu sayfa
localhost:3000/cancel -> Ödeme işlemi başarıyla tamamlandıktan sonra
                        'Ödeme Başarılı' sayfasındaki 'transaction_id' alanı kopyalanarak
                        iptal sayfasındaki inputa girilecek bu işlem iptal edilebilir.
```
## ENV yönetimi

Vakıfbank tarafından verilen merchant_id, merchant_password ve terminal_id bilgileri "dotenv-rails" gem'i 
kullanılarak .env.development.local içerisinde saklanmıştır. Örnek dosyayı .env.development.local.example olarak proje içerisinde bulabilirsiniz.  

```
VAKIFBANK_MERCHANT_ID           ="VAKIFBANK_MERCHANT_ID"
VAKIFBANK_MERCHANT_PASSWORD     ="VAKIFBANK_MERCHANT_PASSWORD"
VAKIFBANK_TERMINAL_NO           ="VAKIFBANK_TERMINAL_NO"
```
Projeye docker başlatıldıktan localhost:3000 adresinden ulaşılabilir.

