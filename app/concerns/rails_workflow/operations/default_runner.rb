module RailsWorkflow
  module Operations
    #
    # = Workflow::Operations::DefaultRunner contains operation starting,
    # completing etc logic.
    #
    module DefaultRunner
      extend ActiveSupport::Concern

      included do
        # in this default operation runner we don't need to wait anything
        # so we just can run operation. If you need to gather some other
        # information - feel free to redefine operation start logic but
        # try to gather all your custom logic in operation build method.
        # operation start can be usefull if you need to send some notifications
        # to external systems that operation is tarted etc...
        def start
          can_start? ? starting : waiting
        rescue => exception
          RailsWorkflow::Error.create_from exception, parent: self
        end

        def starting
          update_attribute(:status, self.class::IN_PROGRESS)

          is_background && RailsWorkflow.config.activejob_enabled ?
              OperationExecutionJob.perform_later(id) :
              OperationExecutionJob.perform_now(id)
        end

        # This method allows you to add requirements for operation to start. For example
        # some operation can't start because of some process or overal system conditions.
        # By default any operation can start :)
        def can_start?
          status == Operation::NOT_STARTED
        end

        # move operation to waiting status. for example - for user operations
        def waiting
          update_attribute(:status, self.class::WAITING)
          start_waiting if respond_to? :start_waiting
        rescue => exception
          RailsWorkflow::Error.create_from exception, parent: self
        end

        def execute_in_transaction
          status = nil
          self.class.transaction(requires_new: true) do
            begin
              child_process.start if child_process.present?
              status = execute
            rescue ActiveRecord::Rollback
              status = nil
            end

            raise ActiveRecord::Rollback unless status
          end

          if status
            context.save
            complete
          end

        rescue ActiveRecord::Rollback => exception
          # In case of rollback exception we do nothing -
          # this may be caused by usual validations
        rescue => exception
          RailsWorkflow::Error.create_from(
            exception, parent: self,
                       target: self,
                       method: :execute_in_transaction
          )
        end

        def execute
          true
        end

        def completed?
          completed_statuses.include? status
        end

        def can_complete?
          child_process.present? ?
              child_process.status == RailsWorkflow::Process::DONE :
              true
        end

        def complete(to_status = nil)
          if can_complete?

            on_complete if to_status.blank? && respond_to?(:on_complete)

            update_attributes(
              status: to_status || self.class::DONE,
              completed_at: Time.zone.now
            )
            manager.operation_completed self
          end
        rescue => exception
          RailsWorkflow::Error.create_from(
            exception,                 parent: self,
                                       target: self,
                                       method: :complete,
                                       args: [to_status]
          )
        end

        def cancel
          on_cancel if respond_to? :on_cancel
          complete self.class::CANCELED
        end

        def skip
          on_cancel if respond_to? :on_skip
          complete self.class::SKIPPED
        end
      end
    end
  end
end
