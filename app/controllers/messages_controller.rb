class MessagesController < ApplicationController

  before_action :authenticate_user!
  include MessagesScope

end