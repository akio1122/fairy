module BaseDoc
  include Apipie::DSL::Concern

  def namespace(namespace, options = {})
    @namespace = namespace
    @namespace_name = options[:name]
  end
  attr_reader :namespace_name

  def resource(resource)
    controller_name = resource.to_s.camelize + 'Controller'

    (class << self; self; end).send(:define_method, :superclass) do
      mod = @namespace.present? ? @namespace.classify.constantize : Object
      mod.const_get(controller_name)
    end

    Apipie.app.set_resource_id(self, controller_name)

    resource_description do
      api_version @controller.namespace_name if @controller.namespace_name
    end
  end

  def doc_for(action_name, &block)
    instance_eval(&@defaults) if @defaults
    instance_eval(&block)
    api_version namespace_name if namespace_name
    define_method(action_name) do
      # ... define it in your controller with the real code
    end
  end

  AUTH_METHODS = {
    password: Api::Auth::BasicTokenDoc,
    token: Api::Auth::TokenDoc
  }

  def auth_with(auth_method)
    mod = AUTH_METHODS[auth_method] or raise "Unknown auth strategy #{auth_method}"
    send(:include, mod)
  end

  def defaults(&block)
    @defaults = block
  end
end