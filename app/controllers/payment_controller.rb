class PaymentController < ApplicationController
  #purchase methoduna ACS kontrolünden sonra dışarıdan tekrar post isteği atılarak işleme devam edildiği için
  #origin hatası alınıyordu. Koruma yöntemi CSRF'i devre dışı bırakmak yerine tek methodu hariç bıraktım
  protect_from_forgery except: :purchase_step_two

  def payment
    @credit_card = 4938460158754205
    @expire_year = 2024
    @expire_month = 11
    @cvv = 715
    @amount = "5638,92"
    @currency = "TRY"
  end

  def purchase
    month, year = params[:expire_date].split('/')
    ActiveMerchant::Billing::Base.mode = :test
    gateway = ActiveMerchant::Billing::Vakifbank.new(
      {
        merchant_id: ENV['VAKIFBANK_MERCHANT_ID'],
        merchant_password: ENV['VAKIFBANK_MERCHANT_PASSWORD'],
        terminal_no: ENV['VAKIFBANK_TERMINAL_NO']
      })
    credit_card = ActiveMerchant::Billing::CreditCard.new(
      :first_name => 'Hebele',
      :last_name => 'Hübele',
      :number => params[:card_number],
      :month => month,
      :year => year,
      :verification_value => params[:cvv]
    )

    if credit_card.validate.empty?
      @response = gateway.purchase(normalize_amount(params[:amount]), credit_card, params[:currency], {
        full_3d: params[:full_3d],
        user_ip: request.remote_ip
      })

      if @response.success?
        if @response.params['acs_url'].present?
          redirect_to acs_service_path(response: @response.params)
        else
          puts @response.params
          redirect_to purchase_result_path(response: @response.params)
        end
      else
        raise StandardError, response.message
      end
    end
  end

  def purchase_step_two
    date = params['Expiry']
    year = (date[0, 2].to_i)+2000
    month = date[2, 2].to_i

    ActiveMerchant::Billing::Base.mode = :test
    gateway = ActiveMerchant::Billing::Vakifbank.new(
      {
        merchant_id: ENV['VAKIFBANK_MERCHANT_ID'],
        merchant_password: ENV['VAKIFBANK_MERCHANT_PASSWORD'],
        terminal_no: ENV['VAKIFBANK_TERMINAL_NO']
      })
    credit_card = ActiveMerchant::Billing::CreditCard.new(
      :first_name => 'Hebele',
      :last_name => 'Hübele',
      :number => params[:Pan],
      :month => month,
      :year => year,
      :verification_value => params[:SessionInfo]
    )

    @response = gateway.complete_3d_purchase(params[:PurchAmount],credit_card,params[:PurchCurrency],{eci: params[:Eci], cavv: params[:Cavv], mpi_transaction_id: params[:VerifyEnrollmentRequestId], user_ip: request.remote_ip })
    if @response.success?
      redirect_to purchase_result_path(response: @response.params)
    else
      raise StandardError, @response
    end
  end

  def acs_service
    @response = params[:response]
  end
  def purchase_result
    @response = params[:response]
  end

  def cancel
    if params[:order_id].present?
      ActiveMerchant::Billing::Base.mode = :test
      gateway = ActiveMerchant::Billing::Vakifbank.new(
        {
          merchant_id: ENV['VAKIFBANK_MERCHANT_ID'],
          merchant_password: ENV['VAKIFBANK_MERCHANT_PASSWORD'],
          terminal_no: ENV['VAKIFBANK_TERMINAL_NO']
        })
      @response = gateway.cancel({reference_transaction_id: params[:order_id], user_ip: request.remote_ip})

      if @response.success?
        if @response.params['acs_url'].present?
          redirect_to acs_service_path(response: @response.params)
        else if !@response.nil?
               redirect_to purchase_result_path(response: @response.params)
           end
        end
      else
        raise StandardError, response.message
      end
    end
  end

  private
  def normalize_amount(amount)
    amount.gsub!(',', '.')
    normalized_amount = BigDecimal(amount).round(2)
    '%.2f' % normalized_amount
  end
end
