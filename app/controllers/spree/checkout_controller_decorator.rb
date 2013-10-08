Spree::CheckoutController.class_eval do

  before_filter :redirect_for_ebsin, :only => :update

  private

    def redirect_for_ebsin
      return unless params[:state] == "payment"
      if @order.total > 0.0
        @payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
        if @payment_method && @payment_method.kind_of?(Spree::PaymentMethod::Ebsin)
          @order.update_attributes(object_params)
          redirect_to gateway_ebsin_path(:gateway_id => @payment_method.id, :order_id => @order.id)
        end
      elsif @order.total == 0.0
        @order.reload
        @order.next
        session[:order_id] = nil
        @order.finalize!
        redirect_to order_url(@order, {:checkout_complete => true, :token => @order.token}), :notice => I18n.t("payment_success")
      end
    end
end