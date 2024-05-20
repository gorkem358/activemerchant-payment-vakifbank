# frozen_string_literal: true

module ActiveMerchant
  module Billing
    class Vakifbank < Gateway
      #atanan parametreye daha sonra erişmek için tanımlama yapıyoruz
      attr_reader :merchant_id

      self.display_name = 'Vakıfbank Sanal POS'

      self.money_format = :cents

      self.supported_cardtypes = %i[visa master]

      self.default_currency = 'TRY'

      self.currencies_without_fractions = %i[EUR GBP USD TRY]

      self.supported_countries = %w[TR]

      PROCESS_STATUSES = {
        'ACS' => "Kart Sahipliği Kontrolü İşlemi",
        'NON3D' => "İşlem 3D Olmadan Tamamlandı!"
      };

      CARD_IDENTIFIERS = {
        'visa' => 100,
        'master' => 200,
        'troy' => 300
      }

      CURRENCY_CODES = {
        'YTL' => 949,
        'TRL' => 949,
        'TL'  => 949,
        'USD' => 840,
        'EUR' => 978,
        'GBP' => 826
      }

      ENDPOINTS = {
        "enrollment" => {
          "test" => "https://3dsecuretest.vakifbank.com.tr:4443/MPIAPI/MPI_Enrollment.aspx",
          "live" => "https://3dsecure.vakifbank.com.tr:4443/MPIAPI/MPI_Enrollment.aspx"
        },
        "payment_services" => {
          "test" => "https://onlineodemetest.vakifbank.com.tr:4443/VposService/v3/Vposreq.aspx",
          "live" => "https://onlineodeme.vakifbank.com.tr:4443/VposService/v3/Vposreq.aspx"
        }
      }

      def initialize(options = {})
        requires!(options, :merchant_id, :merchant_password, :terminal_no)
        @merchant_id = options[:merchant_id]
        @merchant_password = options[:merchant_password]
        @terminal_no = options[:terminal_no]
        super
      end

      def enrollment(money, credit_card, currency)
        commit("enrollment",build_enrollment_request(money, credit_card, currency))
      end

      def purchase(money, credit_card, currency, options)
        #enrollment isteğini atıp kartın 3d, half 3d ya da non-3d durumunu kontrol ediyoruz
        enrollment_result = enrollment(money, credit_card, currency)
        #enrollment sonucunu yorumlayarak işleme kart tipine göre devam ediyoruz
        #eğer dönen response içerisinde VERes>Status alanı Y ise 3d, A ise half-3d, U ise non-3d durumundadır
        #3d satış işlemi farklı, half-3d farklı ve non-3d satış işlemi farklı fonksiyonlar üzerinden yapılır.

        if ['Y', 'A'].include?(enrollment_result.params['status']) && options[:full_3d] == "on"
          # Y kartın 3d durumudur işlem buna göre devam eder.
          # A ise half secure durumudur fakat yine de otomatik form post işlemi gerçekleştirilmeli ve gereken ECI + CAVV değerleri alınmalıdır
          enrollment_result
        elsif enrollment_result.params['status'] == 'U' || !options[:full_3d].present?
          # Kartın non-3d durumu işleme devam etmek risklidir fakat yapılabilir ya da parametrik kontrol eklenerek non-3d işlemler kontrol altında izinle yapılabilir
          commit("payment_services","prmstr=#{build_non3d_purchase_request(money, credit_card, currency, options)}")
        else
          #eğer Status E ya da N durumunda ise hata vererek VERes>MessageErrorCode içerisindeki koda göre hata mesajı dönülmelidir
          Response.new(
            false,
            "Unproccessable credit / debit card information! Please try with different card.",
            {
              "status" => 422,
              "message" => "Unprocessable Content"
            },
            test: test?,
            authorization: ""
          )
        end
          #Enrollmenttan gelen PAReq, TermUrl, MD ve ACSUrl değişkenlerini view'a dönerek otomatik bir post işlemi gerçekleştirmesi gerekir.
      end

      def complete_3d_purchase(money, credit_card, currency, options={})
        requires!(options, :eci, :cavv, :mpi_transaction_id, :user_ip)
        commit("payment_services","prmstr=#{build_3d_purchase_request(money, credit_card, currency, options)}")
      end

      def cancel(options={})
        requires!(options, :reference_transaction_id, :user_ip)
        commit("payment_services","prmstr=#{build_cancel_request(options)}")
      end

      private

      def build_enrollment_request(money, credit_card, currency)
        datetime = DateTime.now
        formatted_datetime = datetime.strftime("%Y%m%d%H%M%S")
        request_params = {
          "MerchantId" => @merchant_id,
          "MerchantPassword" => @merchant_password,
          "VerifyEnrollmentRequestId" => formatted_datetime,
          "Pan" => credit_card.number,
          "ExpiryDate" => credit_card.year.to_s[-2..-1]+credit_card.month.to_s,
          "PurchaseAmount" => money,
          "Currency" => currency,
          "BrandName" => CARD_IDENTIFIERS[credit_card.brand],
          "SuccessUrl" => "http://localhost:3000/purchase-step-two",
          "FailureUrl" => "http://localhost:3000/purchase-step-two",
          #
          "SessionInfo" => credit_card.verification_value
        }

        URI.encode_www_form(request_params)
      end

      def build_xml_request
        xml = Builder::XmlMarkup.new(indent: 2)
        xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
        xml.tag! 'VposRequest' do
          xml.tag! 'MerchantId', @merchant_id
          xml.tag! 'Password', @merchant_password

          if block_given?
            yield xml
          else
            xml.target!
          end
        end
      end

      def build_non3d_purchase_request(money, credit_card, currency, options)
        build_xml_request do |xml|
          add_terminal_data(xml)
          add_card_data(xml,credit_card)
          add_user_ip(xml,options[:user_ip])
          add_amount(xml, money)
          add_currency(xml, currency)
          add_transaction_type(xml, 'Sale')
          add_device_source(xml)
          xml.target!
        end
      end

      def build_3d_purchase_request(money, credit_card, currency, options)
        build_xml_request do |xml|
          add_terminal_data(xml)
          add_card_data(xml,credit_card)
          add_user_ip(xml,options[:user_ip])
          add_transaction_id(xml,options[:mpi_transaction_id])
          add_amount(xml, money)
          add_currency(xml, currency)
          add_transaction_type(xml, 'Sale')
          add_device_source(xml)
          add_eci_info(xml, options[:eci])
          add_cavv_info(xml, options[:cavv])
          xml.target!
        end
      end

      def build_cancel_request(options)
        build_xml_request do |xml|
          add_transaction_type(xml, 'Cancel')
          add_reference_transaction_id(xml, options[:reference_transaction_id])
          add_user_ip(xml, options[:user_ip])
          xml.target!
        end
      end

      def add_terminal_data(xml)
        xml.tag! 'TerminalNo', @terminal_no
      end
      def add_user_ip(xml, ip)
        xml.tag! 'ClientIp', ip
      end
      def add_transaction_id(xml, transaction_id)
        xml.tag! 'MpiTransactionId', transaction_id
      end
      def add_reference_transaction_id(xml, reference_transaction_id)
        xml.tag! 'ReferenceTransactionId', reference_transaction_id
      end
      def add_device_source(xml)
        xml.tag! 'TransactionDeviceSource', '0'
      end
      def add_transaction_type(xml, type)
        xml.tag! 'TransactionType', type
      end
      def add_amount(xml, money)
        xml.tag! 'CurrencyAmount', money
      end
      def add_currency(xml, currency)
        xml.tag! 'CurrencyCode', currency
      end
      def add_eci_info(xml, eci)
        xml.tag! 'ECI', eci
      end
      def add_cavv_info(xml, cavv)
        xml.tag! 'CAVV', cavv
      end
      def add_card_data(xml, credit_card)
        xml.tag! 'Pan', credit_card.number
        xml.tag! 'Expiry', credit_card.year.to_s+credit_card.month.to_s
        xml.tag! 'Cvv', credit_card.verification_value
      end

      def commit(process, request)
        url = test? ? ENDPOINTS[process]['test'] : ENDPOINTS[process]['live']

        raw_response = ssl_post(url, request)

        response = parse(raw_response)

        success = success?(response)

        Response.new(
          success,
          success ? 'Approved' : "Declined (Reason: #{response[:reason_code]} - #{response[:error_msg]} - #{response[:sys_err_msg]})",
          response,
          test: test?,
          authorization: response[:order_id]
        )
      end

      def parse(body)
        xml = REXML::Document.new(strip_invalid_xml_chars(body))

        response = {}
        xml.root.elements.to_a.each do |node|
          parse_element(response, node)
        end
        response
      end

      def parse_element(response, node)
        if node.has_elements?
          node.elements.each { |element| parse_element(response, element) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end

      def success?(response)
          response[:result_code] == "0000" || response[:ResultCode] == "0000" || response[:status] == 'Y'
      end

      def strip_invalid_xml_chars(xml)
        xml.gsub(/&(?!(?:[a-z]+|#[0-9]+|x[a-zA-Z0-9]+);)/, '&amp;')
      end

      def build_sale_request_old(money, credit_card, currency, options)
        builder = Builder::XmlMarkup.new(indent: 2)
        xml_body = builder.VposRequest do |vpos_request|
          vpos_request.MerchantId @merchant_id
          vpos_request.Password @merchant_password
          vpos_request.TerminalNo @terminal_no
          vpos_request.Pan credit_card.number
          vpos_request.Expiry credit_card.year.to_s+credit_card.month.to_s
          vpos_request.CurrencyAmount "%.2f" % (money.to_i / 100.0)
          vpos_request.CurrencyCode currency
          vpos_request.TransactionType 'Sale'
          vpos_request.Cvv credit_card.verification_value
          vpos_request.ECI options[:eci]
          vpos_request.CAVV options[:cavv]
          vpos_request.MpiTransactionId options[:mpi_transaction_id]
          vpos_request.ClientIp options[:user_ip]
          vpos_request.TransactionDeviceSource '0'
        end
        "prmstr=#{xml_body}"
      end
    end
  end
end
