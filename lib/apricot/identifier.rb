module Apricot
  class Identifier
    attr_reader :name, :unqualified_name

    @table = {}

    def self.intern(name)
      name = name.to_sym
      @table[name] ||= new(name)
    end

    private_class_method :new

    def initialize(name)
      @name = @unqualified_name = name
    end

    def bytecode(g, quoted=false, macroexpand=true)
      if quoted
        quoted_bytecode(g)
      else
        if constant?
          g.push_const const_names.first
          const_names.drop(1).each {|n| g.find_const n }
        elsif self?
          g.push_self
        elsif qualified?
          QualifiedReference.new(unqualified_name, qualifier).bytecode(g)
        else
          g.scope.find_var(name).bytecode(g)
        end
      end
    end

    def quoted_bytecode(g)
      g.push_const :Apricot
      g.find_const :Identifier
      g.push_literal name
      g.send :intern, 1
    end

    def self?
      self == Identifier.intern(:self)
    end

    def qualified?
      qualifier && @unqualified_name != @name
    end

    def constant?
      !const_names.empty?
    end

    # Does the identifier reference a fn on a namespace?
    def fn?
      qualifier.is_a?(Namespace) && qualifier.fns.include?(@unqualified_name)
    end

    # Does the identifier reference a method on a module?
    def method?
      !qualifier.is_a?(Namespace) && qualifier.respond_to?(@unqualified_name)
    end

    # Get the metadata of the object this identifier references, or nil.
    def meta
      qualifier.is_a?(Namespace) && qualifier.vars[@unqualified_name] &&
        qualifier.vars[@unqualified_name].apricot_meta
    end

    def qualifier
      return @qualifier if @qualifier
      if @name =~ /\A(.+?)\/(.+)\z/
        qualifier_id = Identifier.intern($1)
        raise 'Qualifier in qualified identifier must be a constant' unless qualifier_id.constant?

        @qualifier = qualifier_id.const_names.reduce(Object) do |mod, name|
          mod.const_get(name)
        end

        @unqualified_name = $2.to_sym
      end
      @qualifier ||= Apricot.current_namespace
    end

    def const_names
      return @const_names if @const_names
      @const_names = []
      if @name =~ /\A(?:[A-Z]\w*::)*[A-Z]\w*\z/
        @const_names = @name.to_s.split('::').map(&:to_sym)
      end
      @const_names
    end

    # Copying Identifiers is not allowed.
    def initialize_copy(other)
      raise TypeError, "copy of #{self.class} is not allowed"
    end

    private :initialize_copy

    alias_method :==, :equal?
    alias_method :eql?, :equal?

    def hash
      @name.hash
    end

    def inspect
      case @name
      when :true, :false, :nil, /\A(?:\+|-)?\d/
        # Use arbitrary identifier syntax for identifiers that would otherwise
        # be parsed as keywords or numbers
        str = @name.to_s.gsub(/(\\.)|\|/) { $1 || '\|' }
        "#|#{str}|"
      when /\A#{Reader::IDENTIFIER}+\z/
        @name.to_s
      else
        str = @name.to_s.inspect[1..-2]
        str.gsub!(/(\\.)|\|/) { $1 || '\|' }
        "#|#{str}|"
      end
    end

    def to_s
      @name.to_s
    end

    def to_sym
      @name
    end
  end
end
