# frozen_string_literal: true
require './lib/orangelight/illiad_patron_client.rb'
require './lib/orangelight/illiad_account.rb'

class AccountController < ApplicationController
  include ApplicationHelper

  before_action :read_only_redirect, except: [:redirect_to_alma, :user_id]
  before_action :require_user_authentication_provider, except: [:redirect_to_alma, :user_id]
  before_action :verify_user, except: [:borrow_direct_redirect, :redirect_to_alma, :user_id]

  def index
    redirect_to digitization_requests_path
  end

  def digitization_requests
    set_patron
  end

  def borrow_direct_redirect
    # action is only valid if the user is logged in first
    if current_user
      borrow_direct_user_action
    else
      redirect_to user_cas_omniauth_authorize_path(origin: url_for(params.permit!))
    end
  end

  def cancel_ill_requests
    set_patron
    response = IlliadPatronClient.new(@patron).cancel_ill_requests(params[:cancel_requests]) unless params[:cancel_requests].nil?
    illiad_patron_client(@patron)
    respond_to do |format|
      if params[:cancel_requests].nil?
        format.js { flash.now[:error] = I18n.t('blacklight.account.cancel_no_items') }
      elsif cancel_ill_success(response)
        format.js { flash.now[:success] = I18n.t('blacklight.account.cancel_success') }
      else
        format.js { flash.now[:error] = I18n.t('blacklight.account.cancel_fail') }
      end
    end
  end

  def redirect_to_alma
    render "redirect_to_alma"
  end

  def user_id
    render json: { user_id: current_user&.uid }
  end

  protected

    def read_only_redirect
      if Orangelight.read_only_mode
        flash[:notice] = 'Account login unavailable during maintenace.'
        redirect_to(root_url) && return
      end
    end

    def verify_user
      unless current_user
        flash[:error] = I18n.t('blacklight.saved_searches.need_login') &&
                        raise(Blacklight::Exceptions::AccessDenied)
      end
    end

    def borrow_direct_user_action
      # only cas users are allowed to access borrow direct
      if current_user.cas_provider?
        set_patron
        redirect_to borrow_direct_url(@patron[:barcode]) if @patron && @patron[:barcode]

      # other users (barcode and alma) just get an error
      else
        @illiad_transactions = []
        flash[:error] = I18n.t('blacklight.account.borrow_direct_ineligible')
        redirect_to root_url
      end
    end

    ## For local dev purposes hardcode a net id string in place of current_user.uid
    ## in this method. Hacky, but convienent to see what "real" data looks like for
    ## edge case patrons.
    def set_patron
      @netid = current_user.uid
      @patron = current_patron(current_user)
      illiad_patron_client(@patron)
    end

    def illiad_patron_client(patron)
      @illiad_transactions = []
      return unless patron && current_user.cas_provider?

      @illiad_account = IlliadAccount.new(patron)
      return unless @illiad_account.verify_user

      @illiad_transactions = IlliadPatronClient.new(patron).outstanding_ill_requests
    end

    def cancel_ill_success(response)
      bodies = response.map { |rep| JSON.parse(rep.body) }
      bodies.reject { |body| body['TransactionStatus'] =~ /^Cancelled/ }.empty?
    end

  private

    def current_patron(user)
      Bibdata.get_patron(user)
    end

    def borrow_direct_url(barcode)
      url = if params[:q]
              BorrowDirect::GenerateQuery.new(RELAIS_BASE).query_url_with(keyword: params[:q])
            elsif params[:query] # code in umlaut borrow direct gem requires 'query' as a param
              BorrowDirect::GenerateQuery.new(RELAIS_BASE).query_url_with(params[:query])
            else
              RELAIS_BASE
            end
      %(#{url}&LS=#{BorrowDirect::Defaults.library_symbol}&PI=#{barcode})
    end
end
