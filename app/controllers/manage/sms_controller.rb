module Manage
  class SmsController < BaseController

    def index
      @blazer_queries = Blazer::Query.where("name ilike '%[Ops Sms]%'")
    end

    def send_sms
      bq = Blazer::Query.find_by_id(params[:sms][:blazer_query_id])
      res = User.connection.execute(bq.statement)
      user_ids = res.map{|r| r["user_id"]}
      if user_ids.blank?
        flash[:error] = "The blazer query you selected did not have any users. Please double check and try again"
      elsif params[:sms][:message].blank?
        flash[:error] = "You have an empty message so we did not send"
      else
        User.where(id: user_ids).each do |u|
          Sms.new.run(u, params[:sms][:message])
        end
        flash[:notice] = "Sent message to #{user_ids.count} users"
      end
      redirect_to "/manage/sms/index"
    end

  end
end
