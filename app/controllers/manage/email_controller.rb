module Manage
  class EmailController < BaseController

    def index
      @blazer_queries = Blazer::Query.where("name ilike '%[Email Campaign]%'")
    end

    def send_email
      bq = Blazer::Query.find_by_id(params[:email][:blazer_query_id])
      res = User.connection.execute(bq.statement)

      emails = res.map{|r| r["email"]}
      template_id = params[:email][:sendwithus_template_id]
      if res.count == 0
        flash[:error] = "The blazer query you selected did not have any users. Please double check and try again"
      elsif template_id.blank?
        flash[:error] = "You have an empty template id so we did not send"
      else
        res.each do |r|
          email = r["email"]
          data = {}
          r.each_pair do |k,v|
            data[k] = v
          end
          Email.new.send_template_for(template_id, email, data)
        end
        flash[:notice] = "Sent email to #{emails.count} users"
      end
      redirect_to "/manage/email/index"
    end

  end
end
