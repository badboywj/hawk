#======================================================================
#                        HA Web Konsole (Hawk)
# --------------------------------------------------------------------
#            A web-based GUI for managing and monitoring the
#          Pacemaker High-Availability cluster resource manager
#
# Copyright (c) 2009-2012 Novell Inc., All Rights Reserved.
#
# Author: Tim Serong <tserong@suse.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it would be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Further, this software is distributed without any warranty that it is
# free of the rightful claim of any third person regarding infringement
# or the like.  Any license provided herein, whether implied or
# otherwise, applies only to this software file.  Patent licenses, if
# any, provided herein do not apply to combinations of this program with
# other software, or any other product whatsoever.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston MA 02111-1307, USA.
#
#======================================================================

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include FastGettext::Translation

  before_filter :set_users_locale

  def set_users_locale
    I18n.locale = FastGettext.set_locale(params[:locale] || cookies[:locale] ||
      request.env['HTTP_ACCEPT_LANGUAGE'] || 'en_US')
    cookies[:locale] = I18n.locale if cookies[:locale] != I18n.locale.to_s
  end

  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details

  # Force back to status page if e.g.: cluster offline when trying to access
  # resources, etc.
  rescue_from CibObject::CibObjectError, RuntimeError do |e|
    if params[:controller] == "main" || params[:controller] == "cib"
      rescue_action_without_handler(e)
    else
      redirect_to status_path
    end
  end

  def initialize
    responses = {
      'CibObject::RecordNotFound'   => :not_found,
      'CibObject::PermissionDenied' => :forbidden
    }
    # Handle CibObject exceptions
    if defined?(ActionDispatch::ShowExceptions) # Rails 3
      ActionDispatch::ShowExceptions.rescue_responses.update(responses)
    else
      rescue_responses.update(responses)
    end

    require 'socket'
    @host = Socket.gethostname  # should be short hostname
  end

  # Meant to be protected, but must be public to be called by Invoker
  def current_user
    @_current_user ||= session[:username]
  end

  #
  # Technique based on one presented by a very unhappy sounding person at:
  #
  #   http://m.onkey.org/how-to-access-session-cookies-params-request-in-model
  #
  # If you ever read this, o unhappy one, I'm not injecting controller data
  # into my models, but I *do* need the current user when models invoke
  # external commands to update the cluster configuration (this is required
  # for ACLs to work properly in this application, which has nothing to do
  # with Rails at all), and I'm damn well not passing the current user to
  # every model, when the models themselves actually don't need to care who
  # is using them.
  #
  around_filter :inject_current_user_into_invoker

protected

  def inject_current_user_into_invoker
    # Can't use self inside the proc, or the binding is wrong
    current_controller = self
    # TODO(should): Ruby 1.9 apparently doesn't allow send to call private
    #               methods - need to replace with funcall.
    Invoker.send(:define_method, 'current_user', proc { current_controller.current_user })
    yield
    Invoker.send(:remove_method, 'current_user')
  end

  # This login system is a heavily-stripped-back form of what would
  # ordinarily be generated by the restful authentication plugin

  def logged_in?
    !!current_user
  end

  # Overridable
  def authorized?
    logged_in?
  end

  def login_required
    authorized? || access_denied
  end

  def access_denied
    respond_to do |format|
      format.json do
        # This will kill e.g. JSON requests when not logged in.
        head :forbidden
      end
      format.any do
        # Have to use format.any not format.html due to stupid IE accept
        # header brokenness.
        store_location
        redirect_to new_session_path
      end
    end
  end

  # Cribbed from cib.rb -- only use this if you need the cluster to be online,
  # and *don't* have a Cib (or other thing handy) that'll throw an appropriate
  # exception.
  def cluster_online
    crm_status = %x[/usr/sbin/crm_mon -s 2>&1].chomp
    if $?.exitstatus == 10 || $?.exitstatus == 11
      redirect_to status_path
    end
  end

  def store_location
    session[:return_to] = "#{request.protocol}#{request.host_with_port}#{request.fullpath}"
  end

  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end

  # Check if the user is sufficiently privileged to access sensitive
  # information (syslog via hb_report/crm_report, "crm history")
  def is_god?
    return current_user == "hacluster" || current_user == "root"
  end

  # Make some methods accessible to the view
  helper_method :logged_in?
  helper_method :current_user
  helper_method :is_god?
  # TODO(should): This may go away in Rails 3
  helper_method :relative_url_root

end
