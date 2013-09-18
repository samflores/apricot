module Apricot
  # Every seq should include this module and define 'first' and 'next'
  # methods. A seq may redefine 'rest' and 'each' if there is a more efficient
  # way to implement them.
  #
  # 'first' should return the first item in the seq.
  # 'next' should return a seq of the rest of the items in the seq, or nil
  #   if there are no more items.
  module Seq
    include Enumerable
    include Comparable

    def rest
      self.next || List::EMPTY_LIST
    end

    def each
      s = self

      while s
        yield s.first
        s = s.next
      end

      self
    end

    def to_seq
      self
    end

    def empty?
      false
    end

    def last
      s = self

      while s.next
        s = s.next
      end

      s.first
    end

    def cons(x)
      Cons.new(x, self)
    end

    def <=>(other)
      return unless other.is_a?(Seq) || other.nil?
      s, o = self, other

      while s && o
        comp = s.first <=> o.first
        return comp unless comp == 0
        s = s.next
        o = o.next
      end

      if s
        1
      elsif o
        -1
      else
        0
      end
    end

    alias_method :eql?, :==

    def hash
      hashes = map {|x| x.hash }
      hashes.reduce(hashes.size) {|acc,hash| acc ^ hash }
    end

    def to_s
      str = '('
      each {|x| str << x.apricot_inspect << ' ' }
      str.chop!
      str << ')'
    end

    alias_method :inspect, :to_s


    def bytecode(g, quoted=false, macroexpand=true)
      if quoted || empty?
        quoted_bytecode(g)
      else
        if first.is_a?(Identifier)
          return if special_bytecode(g) ||
                    macro_bytecode(g, macroexpand) ||
                    inline_bytecode(g) ||
                    callable_bytecode(g)
        end
        others_bytecode(g)
      end
    end

    def others_bytecode(g)
      g.tail_position = false
      first.bytecode(g)
      rest.each {|arg| arg.bytecode(g) }
      g.send :apricot_call, rest.count
    end

    def callable_bytecode(g)
      return unless first.fn? || first.method?
      qualifier_id = Identifier.intern(first.qualifier.name)
      first_name, *rest_names = qualifier_id.const_names

      g.push_const first_name
      rest_names.each {|n| g.find_const(n) }

      rest.each {|arg| arg.bytecode(g) }
      g.send first.unqualified_name, rest.count
      true
    end

    def inline_bytecode(g)
      meta = first.meta
      return unless meta && meta[:inline] && (!meta[:'inline-arities'] ||
      meta[:'inline-arities'].apricot_call(rest.count))
      begin
        inlined_form = meta[:inline].apricot_call(*rest)
      rescue => e
        g.compile_error "Inliner function for '#{first.name}' raised an exception:\n  #{e}"
      end

      g.tail_position = false
      inlined_form.bytecode(g)
      true
    end

    def macro_bytecode(g, macroexpand)
      return unless macroexpand
      form = Apricot.macroexpand(self)
      form.bytecode(g, false, !form.is_a?(Seq))
      true
    end

    def special_bytecode(g)
      return unless special = SpecialForm[first.name]
      special.bytecode(g, rest)
      true
    end

    def quoted_bytecode(g)
      g.push_const :Apricot
      g.find_const :List

      if empty?
        g.find_const :EMPTY_LIST
      else
        each {|e| e.bytecode(g, true) }
        g.send :[], count
      end
    end
  end
end
