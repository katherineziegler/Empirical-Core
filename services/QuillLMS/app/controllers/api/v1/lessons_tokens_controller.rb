class Api::V1::LessonsTokensController < Api::ApiController
  skip_before_action :verify_authenticity_token

  def create
    token = LessonsTokenCreator
      .new(current_user, params[:classroom_unit_id])
      .create
    render json: { token: token }
  end
end
