require 'group_authz_helper'

module GroupAuthz
  module Application
    def self.included(klass)
      klass.extend(ClassMethods)
    end
    include Helper

    def redirect_to_lobby(message = "You aren't authorized for that")
      flash[:error] = message
      begin
        redirect_to :back
      rescue ActionController::RedirectBackError
        redirect_to home_url
      end
    end

    def check_authorized
      current_user = AuthnFacade.current_user(self)

      criteria = {:action => action_name, :id => params[:id]}

      return false if current_user.blank?

      if self.class.can_authorize(current_user, criteria)
        flash[:group_authorization] = true
        return true
      else
        redirect_to_lobby("You are not authorized to perform this action.  Perhaps you need to log in?")
        flash[:group_authorization] = false
        return false
      end
    end

    module ClassMethods
      def can_authorize(user, criteria=nil)
        criteria ||= {}

        groups = criteria[:group] ? [criteria[:group]] : user.groups

        (read_inheritable_attribute(:dynamic_authorization_procs) || []).each do |prok|
          approval = prok.call(user, criteria)
          next if approval == false
          next if approval.blank?
          return true
        end

        select_on = {
          :group_id => groups.map{|grp| grp.id},
          :controller => controller_path,
          :action => nil,
          :subject_id => nil
        }

        permissions = GroupAuthz::Permission.find(:first, :conditions => select_on)
        return true unless permissions.nil?

        action_grants = [criteria[:action]]
        grant_aliases = read_inheritable_attribute(:grant_alias_hash)

        if not grant_aliases.nil? and grant_aliases.has_key?(criteria[:action])
          action_grants += grant_aliases[criteria[:action]]
        end

        select_on[:action] = action_grants
        permissions = GroupAuthz::Permission.find(:first, :conditions => select_on)
        return true unless permissions.nil?

        select_on[:subject_id] = criteria[:id]
        permissions = GroupAuthz::Permission.find(:first, :conditions => select_on)
        return (not permissions.nil?)
      end

      def needs_authorization(*actions)
        before_filter CheckAuthorization
        if actions.empty?
          write_inheritable_attribute(:whole_controller_authorization, true)
        else
          write_inheritable_array(:requires_action_authorization, actions)
        end
      end

      def grant_aliases(hash)
        aliases = read_inheritable_attribute(:grant_alias_hash) || Hash.new{|h,k| h[k] = []}
        hash.each_pair do |grant, allows|
          [*allows].each do |allowed|
            aliases[allowed.to_s] << grant.to_s
          end
        end
        write_inheritable_attribute(:grant_alias_hash, aliases)
      end

      def dynamic_authorization(&block)
        write_inheritable_array(:dynamic_authorization_procs, [proc &block])
      end

      def admin_authorized(*actions)
        actions.map!{|action| action.to_s}
        dynamic_authorization do |user, criteria|
          unless actions.nil? or actions.empty?
            return false unless actions.include?(criteria[:action].to_s)
          end
          return user.groups.include?(Group.admin_group)
        end
      end
    end

    class CheckAuthorization
      def self.filter(controller)
        if controller.class.read_inheritable_attribute(:whole_controller_authorization)
          return controller.check_authorized
        elsif (controller.class.read_inheritable_attribute(:requires_action_authorization) || []).include?(controller.action_name.to_sym)
          return controller.check_authorized
        else
          return true
        end
      end
    end
  end
end
