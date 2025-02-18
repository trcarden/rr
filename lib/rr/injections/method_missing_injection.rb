module RR
  module Injections
    class MethodMissingInjection < Injection
      extend(Module.new do
        def find_or_create(subject_class)
          instances[subject_class] ||= begin
            new(subject_class).bind
          end
        end

        def exists?(subject)
          instances.include?(subject)
        end
      end)

      BoundObjects = {}

      include ClassInstanceMethodDefined

      attr_reader :subject_class

      def initialize(subject_class)
        @subject_class = subject_class
        @placeholder_method_defined = false
      end

      def bind
        unless class_instance_method_defined(subject_class, original_method_alias_name)
          unless class_instance_method_defined(subject_class, :method_missing)
            @placeholder_method_defined = true
            subject_class.class_eval do
              def method_missing(method_name, *args, &block)
                super
              end
            end
          end
          # Ruby 1.9 will raise a NoMethodError when #method_missing is defined
          # on the subject, but #to_ary isn't. #method_missing will always be
          # defined thanks to BasicObject, but #to_ary may not, so in this case
          # we need to supply our own. Furthermore, Ruby has special logic to
          # handle the return value of #to_ary; if it is nil, then it tells Ruby
          # to ignore #to_ary altogether and use a default rule to arrayify the
          # object in question.
          unless class_instance_method_defined(subject_class, :to_ary)
            subject_class.class_eval do
              def to_ary; nil; end
            end
          end
          subject_class.__send__(:alias_method, original_method_alias_name, :method_missing)
          bind_method
        end
        self
      end

      def reset
        if subject_has_method_defined?(original_method_alias_name)
          memoized_original_method_alias_name = original_method_alias_name
          placeholder_method_defined = @placeholder_method_defined
          subject_class.class_eval do
            remove_method :method_missing
            unless placeholder_method_defined
              alias_method :method_missing, memoized_original_method_alias_name
            end
            remove_method memoized_original_method_alias_name
          end
        end
      end

    protected
      def bind_method
        id = BoundObjects.size
        BoundObjects[id] = subject_class

        if KeywordArguments.fully_supported?
          subject_class.class_eval((<<-METHOD), __FILE__, __LINE__ + 1)
            def method_missing(method_name, *args, **kwargs, &block)
              if respond_to_missing?(method_name, true)
                super(method_name, *args, **kwargs, &block)
              else
                obj = ::RR::Injections::MethodMissingInjection::BoundObjects[#{id}]
                MethodDispatches::MethodMissingDispatch.new(
                  self,
                  obj,
                  method_name,
                  args,
                  kwargs,
                  block
                ).call
              end
            end
          METHOD
        else
          subject_class.class_eval((<<-METHOD), __FILE__, __LINE__ + 1)
            def method_missing(method_name, *args, &block)
              if respond_to_missing?(method_name, true)
                super(method_name, *args, &block)
              else
                obj = ::RR::Injections::MethodMissingInjection::BoundObjects[#{id}]
                MethodDispatches::MethodMissingDispatch.new(
                  self,
                  obj,
                  method_name,
                  args,
                  {},
                  block
                ).call
              end
            end
          METHOD
        end
      end

      def original_method_alias_name
        MethodDispatches::MethodMissingDispatch.original_method_missing_alias_name
      end
    end
  end
end
