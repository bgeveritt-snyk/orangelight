# frozen_string_literal: true

class AdvancedController < BlacklightAdvancedSearch::AdvancedController
  copy_blacklight_config_from(CatalogController)

  def index
    redirect_to '/catalog', params if params[:id]

    super
  end
end
