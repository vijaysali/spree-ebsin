module Spree
  class EbsJob# < Struct.new(:recipient, :user)

    def perform(number)
      order = Spree::Order.find_by_number(number)
      gateway = Spree::PaymentMethod::Ebsin.where(:environment => "production").first
      unless order.blank? && order.state == "complete" && gateway.blank?
        uri = URI.parse( "https://secure.ebs.in/api/1_0" ); 
        params = {
          "Action" => 'statusByRef', 
          "RefNo" => number, 
          "AccountID" => gateway.preferred_account_id, 
          "SecretKey" => gateway.preferred_secret_key
        }
   
        http = Net::HTTP.new(uri.host, uri.port) 
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.use_ssl = true
        request = Net::HTTP::Post.new(uri.path) 
        request.set_form_data( params )

        response = http.request(request)
        data = Nokogiri::XML.parse(response.body)
        if data.elements.attribute("errorCode") == nil
          if data.elements.attribute("amount").value.to_f == order.total.to_f
            payment = order.payment
            payment.state = "completed"
            payment.save
            if order.next
              send_mail("Order #{order.number} manually transitioned by bot <EOM>")
              Spree::Ebsinfo.create(:first_name => order.bill_address.firstname, :last_name => order.bill_address.lastname, :TransactionId => data.elements.attribute("TransactionID"), :PaymentId => data.elements.attribute("PaymentID"), :amount => data.elements.attribute("amount"), :order_id => order.id)
            else
              send_mail("Order #{order.number} UNABLE  to transition by bot manual transition needs to be done. <EOM>")
            end
          else 
            send_mail("Order #{order.number} EBS amount not matching <EOM>")
          end
        else
          send_mail("Order #{order.number} - No EBS payment found<EOM>")
        end
      end
    end
    
    def send_mail(subject)
      ActionMailer::Base.mail(:from => 'noreply@email.styletag.com', :to => 'ebs@styletag.com', :subject => subject).deliver
    end
  
    handle_asynchronously :perform, :priority => 20, :run_at => lambda { 30.minutes.from_now }
  end
end
