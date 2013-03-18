module Apricot
  module AST
    class LocalReference
      attr_reader :slot, :depth

      def initialize(slot, depth = 0)
        @slot = slot
        @depth = depth
      end

      def bytecode(g)
        if @depth == 0
          g.push_local @slot
        else
          g.push_local_depth @depth, @slot
        end
      end
    end

    class NamespaceReference
      def initialize(name, ns = nil)
        @name = name
        @ns = ns || Apricot.current_namespace
      end

      def bytecode(g)
        if @ns.is_a?(Namespace) && !@ns.vars.include?(@name)
          g.compile_error "Unable to resolve name #{@name} in namespace #{@ns}"
        end

        g.push_cpath_top

        ns_id = Apricot::Identifier.intern(@ns.name)
        ns_id.const_names.each {|n| g.find_const(n) }

        g.push_literal @name

        if @ns.is_a? Namespace
          g.send :get_var, 1
        else # @ns is a regular Ruby module
          g.send :method, 1
        end
      end

      def fn?
        @ns.is_a?(Namespace) && @ns.fns.include?(@name)
      end

      def method?
        !@ns.is_a?(Namespace) && @ns.respond_to?(@name)
      end
    end

    # For the 'self' identifier. Just like Ruby's 'self'.
    class SelfReference
      def bytecode(g)
        g.push_self
      end
    end
  end
end
