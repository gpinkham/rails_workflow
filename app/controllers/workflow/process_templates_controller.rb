require 'workflow/application_controller'
module Workflow
  class ProcessTemplatesController < ::InheritedResources::Base
    before_filter do
      @config_section_active = true
    end

    layout 'workflow/application'

    def create
      # create!{ process_template_url(resource) }
      create!{ process_template_operation_templates_path(resource) }
    end

    def update
      update! { process_template_url(resource) }
    end

    def destroy
      destroy! { process_templates_url}
    end

    protected
    def permitted_params
      params.permit(process_template: [:title, :source, :manager_class, :process_class, :type])
    end


    def collection
      ::Workflow::ProcessTemplateDecorator.decorate_collection(super)
    end

    def resource
      super.decorate
    end


  end
end