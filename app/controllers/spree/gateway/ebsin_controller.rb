require 'base64'
require 'digest/md5'
require 'ruby_rc4'

module Spree
  class Gateway::EbsinController < Spree::StoreController
    include Spree::Core::ControllerHelpers::Order
    include Spree::Core::ControllerHelpers::Auth
    include ERB::Util
    rescue_from ActiveRecord::RecordNotFound, :with => :render_404
    helper 'spree/products'

    respond_to :html

    skip_before_filter :verify_authenticity_token, :only => [:comeback]

    NECESSARY = [
                 "Mode",
                 "PaymentID",
                 "DateCreated",
                 "MerchantRefNo",
                 "Amount",
                 "TransactionID",
                 "ResponseCode",
                 "ResponseMessage"
                ]


    # Show form EBS for pay
    #
    def show
      @order   = Spree::Order.find(params[:order_id])
      @gateway = @order.available_payment_methods.find{|x| x.id == params[:gateway_id].to_i }
      @order.payments.destroy_all
      @hash = Digest::MD5.hexdigest(@gateway.preferred_secret_key+"|"+@gateway.preferred_account_id+"|"+@order.total.to_s+"|"+@order.number+"|"+[gateway_ebsin_comeback_url(@order),'DR={DR}'].join('?')+"|"+@gateway.preferred_mode)
      payment = @order.payments.create!(:amount => 0,  :payment_method_id => @gateway.id)

      if @order.blank? || @gateway.blank?
        flash[:error] = I18n.t("invalid_arguments")
        redirect_to :back
      else
        @bill_address, @ship_address =  @order.bill_address, (@order.ship_address || @order.bill_address)
        render :action => :show
      end

      #have delayed job to check order after 30 mins in case 'comeback' fails
      #make sure you have delayed_job in Gemfile to use this, comment following lines otherwise
      ebs = Spree::EbsJob.new
      ebs.delay.perform(@order.number)
    end

    # Result from EBS
    #
    def comeback
      @order   = current_order || Spree::Order.find_by_number(params[:id])
      payment = @order.payments.where(:payment_method_id => ebs_payment_method.id).first
      payment = @order.payments.create!(:amount => 0,  :payment_method_id => ebs_payment_method.id) if payment.blank?
      @gateway = @order && @order.payments.first.payment_method
      #@gateway && @gateway.kind_of?(PaymentMethod::Ebsin) && params[:DR] 
      @data = ebsin_decode(params[:DR], @gateway.preferred_secret_key)
      if  (@data) &&
          (@data["ResponseMessage"] == "Transaction Successful") &&
          (@data["ResponseCode"] == "0") &&
          (@data["MerchantRefNo"] == @order.number.to_s) &&
          (@data["Amount"].to_f == @order.outstanding_balance.to_f)

        ebsin_payment_success(@data)
        
        @order.reload
        @order.next
        
        session[:order_id] = nil
        
        @order.finalize!
        redirect_to order_url(@order, {:checkout_complete => true, :token => @order.token}), :notice => I18n.t("payment_success")
      else
        ebs_error = @data["ResponseMessage"]      
        flash[:error] = I18n.t("ebsin_payment_response_error")+" Payment: "+ebs_error
        redirect_to (@order.blank? ? root_url : edit_order_url(@order, {:token => @order.token}))
      end

    end


    private

    # processing geteway returned data
    #
    def ebsin_decode(data, key)
      rc4 = RubyRc4.new(key)
      (Hash[ rc4.encrypt(Base64.decode64(data.gsub(/ /,'+'))).split('&').map { |x| x.split("=") } ]).slice(* NECESSARY )
    end

    # Completed payment process
    #
    def ebsin_payment_success(data)
      # record the payment
      source = Spree::Ebsinfo.create(:first_name => @order.bill_address.firstname, :last_name => @order.bill_address.lastname, :TransactionId => @data["TransactionID"], :PaymentId => @data["PaymentID"], :amount => @data["Amount"], :order_id => @order.id)

      ebs_payment_method = Spree::PaymentMethod.where(:type => "Spree::PaymentMethod::Ebsin").last
      payment = @order.payments.where(:payment_method_id => ebs_payment_method.id).first
      payment = @order.payments.create!(:amount => 0,  :payment_method_id => ebs_payment_method.id) if payment.blank?
      payment.source = source
      payment.amount = source.amount
      payment.save
      payment.complete!
    end

  end
end
