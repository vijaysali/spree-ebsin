Spree::CheckoutController.class_eval do
    include AffiliateCredits

  before_filter :redirect_for_ebsin, :only => :update

  private

    def redirect_for_ebsin
      return unless params[:state] == "payment"
      if @order.total > 0.0
        @payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
        if @payment_method && (@payment_method.kind_of?(Spree::PaymentMethod::Ebsin) || @payment_method.kind_of?(Spree::PaymentMethod::MobileWiki) || @payment_method.kind_of?(Spree::PaymentMethod::Rupay))
          @order.update_attributes(object_params)
          x=MailerJob.new
          x.delay.perform(@order,"cc_order_verfiy")
          redirect_to gateway_ebsin_path(:gateway_id => @payment_method.id, :order_id => @order.id)
        end
      elsif @order.total == 0.0 #wallet checkout
        @order.reload
        @order.next
        session[:order_id] = nil
         #referal credits
        if !Spree::Affiliate.where(user_id: spree_current_user.id).empty? && (@order.state == 'complete') && spree_current_user.orders.complete.count==1
      sender=Spree::User.find(Spree::Affiliate.where(user_id: spree_current_user.id).first.partner_id)

      #create credit (if required)
      create_affiliate_credits(sender, spree_current_user, "purchase")
      end
        #@order.finalize!
        redirect_to order_url(@order, {:checkout_complete => true, :token => @order.token}), :notice => I18n.t("payment_success")
      end
    end
end
