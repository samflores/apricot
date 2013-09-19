class Object
  attr_accessor :apricot_meta

  def apricot_inspect
    inspect
  end

  def apricot_str
    to_s
  end

  def apricot_call(*args)
    call(*args)
  end
end

class Array
  # Adapted from Array#inspect. This version prints no commas and calls
  # #apricot_inspect on its elements. e.g. [1 2 3]
  def apricot_inspect
    return '[]' if size == 0

    str = '['

    return '[...]' if Thread.detect_recursion self do
      each {|x| str << x.apricot_inspect << ' ' }
    end

    str.chop!
    str << ']'
  end

  def bind(g, values, scope)
    # FIXME: should not convert to array
    list = values.to_a.dup
    enum = self.to_enum
    amp = Apricot::Identifier.intern(:'&')
    loop do
      id = enum.next
      id, value = case id
              when amp
                [enum.next, list.empty? ? nil : list]
              when :as
                [enum.next, values]
              else
                [id, list.delete_at(0)]
              end
      id.bind(g, value, scope)
    end
  rescue NameError => e
    puts e
  rescue StopIteration
  end

  def bytecode(g, quoted=false, macroexpand=true)
    each {|e| e.bytecode(g, quoted) }
    g.make_array size
  end

  def apricot_call(idx)
    self[idx]
  end

  alias_method :apricot_str, :apricot_inspect

  def to_seq
    if length == 0
      nil
    else
      Seq.new(self, 0)
    end
  end

  class Seq
    include Apricot::Seq

    def initialize(array, offset = 0)
      @array = array
      @offset = offset
    end

    def first
      @array[@offset]
    end

    def next
      if @offset + 1 < @array.length
        Seq.new(@array, @offset + 1)
      else
        nil
      end
    end

    def each
      @array[@offset..-1].each {|x| yield x }
    end

    def count
      @array.length - @offset
    end

    def to_a
      @array[@offset..-1]
    end
  end
end

class Hash
  # Adapted from Hash#inspect. Outputs Apricot hash syntax, e.g. {:a 1, :b 2}
  def apricot_inspect
    return '{}' if size == 0

    str = '{'

    return '{...}' if Thread.detect_recursion self do
      each_item do |item|
        str << item.key.apricot_inspect
        str << ' '
        str << item.value.apricot_inspect
        str << ', '
      end
    end

    str.shorten!(2)
    str << '}'
  end

  def bytecode(g, quoted=false, macroexpand=true)
    # Create a new Hash
    g.push_const :Hash
    g.push size
    g.send :new_from_literal, 1

    # Add keys and values
    each_pair do |key, value|
      g.dup # the Hash
      key.bytecode(g, quoted)
      value.bytecode(g, quoted)
      g.send :[]=, 2
      g.pop # drop the return value of []=
    end
  end

  def apricot_call(key, default = nil)
    fetch(key, default)
  end

  alias_method :apricot_str, :apricot_inspect

  def to_seq
    each_pair.to_a.to_seq
  end
end

class Set
  def apricot_inspect
    return '#{}' if size == 0

    str = '#{'

    return '#{...}' if Thread.detect_recursion self do
      each {|x| str << x.apricot_inspect << ' ' }
    end

    str.chop!
    str << '}'
  end

  def bytecode(g, quoted=false, macroexpand=false)
    g.push_const :Set
    g.send :new, 0 # TODO: Inline this new?

    each do |elem|
      elem.bytecode(g, quoted)
      g.send :add, 1
    end
  end

  def apricot_call(elem, default = nil)
    include?(elem) ? elem : default
  end

  alias_method :apricot_str, :apricot_inspect

  def to_seq
    to_a.to_seq
  end
end

module Onceable
  # Some literals, such as regexps and rationals, should only be created the
  # first time they are encountered. We push a literal nil here, and then
  # overwrite the literal value with the created object if it is nil, i.e.
  # the first time only. Subsequent encounters will use the previously
  # created object. This idea was copied from Rubinius::AST::RegexLiteral.
  #
  # The passed block should take a generator and generate the bytecode to
  # create the object the first time.
  def once(g)
    idx = g.add_literal(nil)
    g.push_literal_at idx
    g.dup
    g.is_nil

    lbl = g.new_label
    g.gif lbl
    g.pop

    yield g

    g.set_literal idx
    lbl.set!
  end
end

class Rational
  include Onceable

  def apricot_inspect
    if @denominator == 1
      @numerator.to_s
    else
      to_s
    end
  end

  def bytecode(g, quoted=false, macroexpand=true)
    once(g) do
      g.push_self
      g.push numerator
      g.push denominator
      g.send :Rational, 2, true
    end
  end

  alias_method :apricot_str, :apricot_inspect
end

class Regexp
  include Onceable

  def apricot_inspect
    "#r#{inspect}"
  end

  def bytecode(g, quoted=false, macroexpand=true)
    once(g) do
      g.push_const :Regexp
      g.push_literal source
      g.push options
      g.send :new, 2
    end
  end

  alias_method :apricot_str, :apricot_inspect
end

class Symbol
  def apricot_inspect
    str = to_s

    if str =~ /\A#{Apricot::Reader::IDENTIFIER}+\z/
      ":#{str}"
    else
      ":#{str.inspect}"
    end
  end

  def bytecode(g, quoted=false, macroexpand=true)
    g.push_literal self
  end

  def apricot_call(obj, default = nil)
    if obj.is_a?(Hash) || obj.is_a?(Set)
      obj.apricot_call(self, default)
    else
      nil
    end
  end
end

class Range
  def to_seq
    if first > last || (first == last && exclude_end?)
      nil
    else
      Seq.new(first, last, exclude_end?)
    end
  end

  class Seq
    include Apricot::Seq

    def initialize(first, last, exclusive)
      @first = first
      @last = last
      @exclusive = exclusive
    end

    def first
      @first
    end

    def next
      next_val = @first.succ

      if @first == @last || (next_val == @last && @exclusive)
        nil
      else
        Seq.new(next_val, @last, @exclusive)
      end
    end

    def each
      prev = nil
      val = @first

      until prev == @last || (val == @last && @exclusive)
        yield val
        prev = val
        val = val.succ
      end

      self
    end
  end
end

module Enumerable
  def to_list
    list = Apricot::List::EMPTY_LIST
    reverse_each {|x| list = list.cons(x) }
    list
  end
end

class NilClass
  include Enumerable

  def each
  end

  def empty?
    true
  end

  # Seq Methods
  # Many functions that return seqs occasionally return nil, so it's
  # convenient if nil can respond to some of the same methods as seqs.

  def to_seq
    nil
  end

  def first
    nil
  end

  def next
    nil
  end

  def rest
    Apricot::List::EMPTY_LIST
  end
end

class String
  def bytecode(g, quoted=false, macroexpand=true)
    g.push_literal self
    g.string_dup # Duplicate string to prevent mutating the literal
  end
end

class Fixnum
  def bytecode(g, quoted=false, macroexpand=true)
    g.push self
  end
end

class Float
  def bytecode(g, quoted=false, macroexpand=true)
    g.push_unique_literal self
  end
end

class BigNum
  def bytecode(g, quoted=false, macroexpand=true)
    g.push_unique_literal self
  end
end

class TrueClass
  def bytecode(g, quoted=false, macroexpand=true)
    g.push :true
  end
end

class FalseClass
  def bytecode(g, quoted=false, macroexpand=true)
    g.push :false
  end
end

class NilClass
  def bytecode(g, quoted=false, macroexpand=true)
    g.push :nil
  end
end
