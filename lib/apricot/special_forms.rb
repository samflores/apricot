module Apricot
  class SpecialForm
    Specials = {}

    def self.[](name)
      Specials[name.to_sym]
    end

    def self.define(name, &block)
      name = name.to_sym
      Specials[name] = new(name, block)
    end

    def initialize(name, block)
      @name = name.to_sym
      @block = block
    end

    def bytecode(g, args)
      @block.call(g, args)
    end
  end

  FastMathOps = {
    :+    => :meta_send_op_plus,
    :-    => :meta_send_op_minus,
    :==   => :meta_send_op_equal,
    :===  => :meta_send_op_tequal,
    :<    => :meta_send_op_lt,
    :>    => :meta_send_op_gt
  }

  # (. receiver method args*)
  # (. receiver method args* & rest)
  # (. receiver method args* | block)
  # (. receiver method args* & rest | block)
  # (. receiver (method args*))
  # (. receiver (method args* & rest))
  # (. receiver (method args* | block))
  # (. receiver (method args* & rest | block))
  SpecialForm.define(:'.') do |g, args|
    g.compile_error "Too few arguments to send expression, expecting (. receiver method ...)" if args.length < 2

    receiver, method_or_list = args.shift(2)

    # Handle the (. receiver (method args*)) form
    if method_or_list.is_a? AST::List
      method = method_or_list.elements.shift

      g.compile_error "Invalid send expression, expecting (. receiver (method ...))" unless args.empty?

      args = method_or_list.elements
    else
      method = method_or_list
    end

    g.compile_error "Method in send expression must be an identifier" unless method.is_a? AST::Identifier

    block_arg = nil
    splat_arg = nil

    if args[-2].is_a?(AST::Identifier) && args[-2].name == :|
      block_arg = args.last
      args.pop(2)
    end

    if args[-2].is_a?(AST::Identifier) && args[-2].name == :&
      splat_arg = args.last
      args.pop(2)
    end

    args.each do |arg|
      next unless arg.is_a?(AST::Identifier)
      g.compile_error "Incorrect use of & in send expression" if arg.name == :&
      g.compile_error "Incorrect use of | in send expression" if arg.name == :|
    end

    receiver.bytecode(g)

    if block_arg || splat_arg
      args.each {|a| a.bytecode(g) }

      if splat_arg
        splat_arg.bytecode(g)
        g.cast_array unless splat_arg.is_a?(AST::ArrayLiteral)
      end

      if block_arg
        nil_block = g.new_label
        block_arg.bytecode(g)
        g.dup
        g.is_nil
        g.git nil_block

        g.push_cpath_top
        g.find_const :Proc

        g.swap
        g.send :__from_block__, 1

        nil_block.set!
      else
        g.push_nil
      end

      if splat_arg
        g.send_with_splat method.name, args.length
      else
        g.send_with_block method.name, args.length
      end

    elsif args.length == 1 && op = FastMathOps[method.name]
      args.each {|a| a.bytecode(g) }
      g.__send__ op, g.find_literal(method.name)

    elsif method.name == :new
      slow = g.new_label
      done = g.new_label

      g.dup # dup the receiver
      g.check_serial :new, Rubinius::CompiledMethod::KernelMethodSerial
      g.gif slow

      # fast path
      g.send :allocate, 0, true
      g.dup
      args.each {|a| a.bytecode(g) }
      g.send :initialize, args.length, true
      g.pop

      g.goto done

      # slow path
      slow.set!
      args.each {|a| a.bytecode(g) }
      g.send :new, args.length

      done.set!

    else
      args.each {|a| a.bytecode(g) }
      g.send method.name, args.length
    end
  end

  # (def name value?)
  SpecialForm.define(:def) do |g, args|
    g.compile_error "Too few arguments to def" if args.length < 1
    g.compile_error "Too many arguments to def" if args.length > 2

    target, value = *args

    value ||= AST::Literal.new(0, :nil)

    case target
    when AST::Identifier
      target.assign_bytecode(g, value)
    else
      g.compile_error "First argument to def must be an identifier"
    end
  end

  # (if cond body else_body?)
  SpecialForm.define(:if) do |g, args|
    g.compile_error "Too few arguments to if" if args.length < 2
    g.compile_error "Too many arguments to if" if args.length > 3

    cond, body, else_body = args
    else_label, end_label = g.new_label, g.new_label

    cond.bytecode(g)
    g.gif else_label

    body.bytecode(g)
    g.goto end_label

    else_label.set!
    if else_body
      else_body.bytecode(g)
    else
      g.push_nil
    end

    end_label.set!
  end

  # (do body*)
  SpecialForm.define(:do) do |g, args|
    if args.empty?
      g.push_nil
    else
      args[0..-2].each do |a|
        a.bytecode(g)
        g.pop
      end
      args.last.bytecode(g)
    end
  end

  # (quote form)
  SpecialForm.define(:quote) do |g, args|
    g.compile_error "Too few arguments to quote" if args.length < 1
    g.compile_error "Too many arguments to quote" if args.length > 1

    args.first.quote_bytecode(g)
  end

  # Code shared between let and loop. type is :let or :loop
  def self.let(g, args, type)
    g.compile_error "Too few arguments to #{type}" if args.length < 1
    g.compile_error "First argument to #{type} must be an array literal" unless args.first.is_a? AST::ArrayLiteral

    bindings = args.shift.elements

    g.compile_error "Bindings array for #{type} must contain an even number of forms" if bindings.length.odd?

    scope = AST::LetScope.new(g.scope)
    g.scopes << scope

    bindings.each_slice(2) do |name, value|
      g.compile_error "Binding targets in let must be identifiers" unless name.is_a? AST::Identifier

      value.bytecode(g)
      g.set_local scope.new_local(name)
      g.pop
    end

    if type == :loop
      scope.loop_label = g.new_label
      scope.loop_label.set!
    end

    SpecialForm[:do].bytecode(g, args)

    g.scopes.pop
  end

  # (let [binding*] body*) where binding is an identifier followed by a value
  SpecialForm.define(:let) do |g, args|
    let(g, args, :let)
  end

  # (loop [binding*] body*) where binding is an identifier followed by a value
  # Just like let but also introduces a loop target for (recur ...)
  SpecialForm.define(:loop) do |g, args|
    let(g, args, :loop)
  end

  # (recur args*)
  # Rebinds the arguments of the nearest enclosing loop or fn and jumps to the
  # top of the loop/fn. Argument rebinding is done in parallel (rebinding a
  # variable in a recur will not affect uses of that variable in the other
  # recur bindings.)
  SpecialForm.define(:recur) do |g, args|
    target = g.scope.find_recur_target
    g.compile_error "No recursion target found for recur" unless target
    vars = target.variables.values

    # TODO: check for fns with rest (splat) args
    g.compile_error "Arity of recur does not match enclosing loop or fn" unless vars.length == args.length

    args.each {|arg| arg.bytecode(g) }

    vars.reverse_each do |var|
      g.set_local var
      g.pop
    end

    g.check_interrupts
    g.goto target.loop_label
  end

  class ArgList
    attr_reader :required_args, :optional_args, :rest_arg,
      :num_required, :num_optional, :num_total

    def initialize(args, g)
      @required_args = []
      @optional_args = []
      @rest_arg = nil

      next_is_rest = false

      args.each do |arg|
        g.compile_error "Unexpected arguments after rest argument" if @rest_arg

        case arg
        when AST::ArrayLiteral
          g.compile_error "Arguments in fn form must be identifiers" unless arg[0].is_a? AST::Identifier
          g.compile_error "Arguments in fn form can have only one optional value" unless arg.elements.length == 2

          optional_args << [arg[0].name, arg[1]]
        when AST::Identifier
          if next_is_rest
            @rest_arg = arg.name
            next_is_rest = false
          elsif arg.name == :&
            next_is_rest = true
          else
            g.compile_error "Optional arguments in fn form must be last" if @optional_args.any?
            @required_args << arg.name
          end
        else
          g.compile_error "Arguments in fn form must be identifiers or 2-element arrays"
        end
      end

      g.compile_error "Expected identifier following & in argument list" if next_is_rest

      @num_required = @required_args.length
      @num_optional = @optional_args.length
      @num_total = @num_required + @num_optional
    end
  end

  # (fn name? [args*] body*)
  # (fn name? [args* & rest] body*)
  # (fn name? ([args*] body*) ... ([args*] body*))
  SpecialForm.define(:fn) do |g, args|
    fn_name = args.shift.name if args.first.is_a? AST::Identifier

    overloads = []

    case args.first
    when AST::List
      # This is the multi-arity form (fn name? ([args*] body*) ... ([args*] body*))
      args.each do |overload|
        # Each overload is of the form ([args*] body*)
        g.compile_error "Expected an arity overload (a list)" unless overload.is_a? AST::List
        arglist, *body = overload.elements
        g.compile_error "Argument list in overload must be an array literal" unless arglist.is_a? AST::ArrayLiteral
        arglist = ArgList.new(arglist.elements, g)
        overloads << [arglist, body]
      end
    when AST::ArrayLiteral
      # This is the single-arity form (fn name? [args*] body*)
      arglist, *body = args
      arglist = ArgList.new(arglist.elements, g)
      overloads << [arglist, body]
    else
      # Didn't match any of the legal forms.
      g.compile_error "Expected argument list or arity overload in fn definition"
    end

    # Check that the overloads do not conflict with each other.
    if overloads.length > 1
      variadic, normals = overloads.partition {|(arglist1, _)| arglist1.rest_arg }

      g.compile_error "Can't have more than one variadic overload" if variadic.length > 1

      # Sort the non-variadic overloads by ascending number of required arguments.
      normals.sort_by! {|(arglist1, _)| arglist1.num_required }

      if variadic.length == 1
        # If there is a variadic overload, it should have at least as many
        # required arguments as the next highest overload.
        variadic_arglist = variadic[0][0]
        if variadic_arglist.num_required < normals.last[0].num_required
          g.compile_error "Can't have a fixed arity overload with more params than a variadic overload"
        end

        # Can't have two overloads with same number of required args unless
        # they have no optional args and one of them is the variadic overload.
        if variadic_arglist.num_required == normals.last[0].num_required &&
          (variadic_arglist.num_optional != 0 || normals.last[0].num_optional == 0)
          g.compile_error "Can't have two overloads with the same arity"
        end
      end

      # Compare each consecutive two non-variadic overloads.
      normals.each_cons(2) do |(arglist1, _), (arglist2, _)|
        if arglist1.num_required == arglist2.num_required
          g.compile_error "Can't have two overloads with the same arity"
        elsif arglist1.num_total >= arglist2.num_required
          g.compile_error "Can't have an overload with more total (required + optional) arguments than another overload with more required arguments"
        end
      end

      overloads = normals + variadic

      g.compile_error "Arity overloading is not fully implemented yet"
    end

    arglist, body = overloads.first

    fn = g.class.new
    fn.name = fn_name || :__fn__
    fn.file = g.file

    scope = AST::FnScope.new(g.scope, name)
    fn.scopes << scope

    fn.definition_line g.line
    fn.set_line g.line

    # Allocate slots for the required arguments
    arglist.required_args.each {|arg| scope.new_local(arg) }

    next_optional = fn.new_label

    arglist.optional_args.each_with_index do |(name, value), i|
      # Calculate the position of this optional arg, off the end of the
      # required args
      arg_index = arglist.num_required + i

      # Allocate a slot for this optional argument
      scope.new_local(name)

      fn.passed_arg arg_index
      fn.git next_optional

      value.bytecode(fn)
      fn.set_local arg_index
      fn.pop

      next_optional.set!
      next_optional = fn.new_label
    end

    if arglist.rest_arg
      # Allocate the slot for the rest argument
      scope.new_local(arglist.rest_arg)
      scope.splat = true
    end

    scope.loop_label = next_optional
    scope.loop_label.set!

    SpecialForm[:do].bytecode(fn, body)

    fn.ret
    fn.close

    fn.scopes.pop

    # If there is a rest arg, it will appear after all the required and
    # optional arguments.
    fn.splat_index = arglist.num_total if arglist.rest_arg

    fn.total_args = arglist.num_total
    fn.required_args = arglist.num_required

    fn.local_count = scope.local_count
    fn.local_names = scope.local_names

    g.push_cpath_top
    g.find_const :Kernel
    g.create_block fn
    g.send_with_block :lambda, 0
    g.set_local scope.self_reference.slot if fn_name
  end

  # (try body* (rescue name|[name condition*] body*)* (ensure body*)?)
  SpecialForm.define(:try) do |g, args|
    body = []
    rescue_clauses = []
    ensure_clause = nil

    if args.last.is_a?(AST::List) && args.last[0].is_a?(AST::Identifier) && args.last[0].name == :ensure
      ensure_clause = args.pop[1..-1] # Chop off the ensure identifier
    end

    args.each do |arg|
      if arg.is_a?(AST::List) && arg[0].is_a?(AST::Identifier) && arg[0].name == :rescue
        rescue_clauses << arg[1..-1] # Chop off the rescue identifier
      else
        g.compile_error "Unexpected form after rescue clause" unless rescue_clauses.empty?
        body << arg
      end
    end

    # Set up ensure
    if ensure_clause
      ensure_ex = g.new_label
      ensure_ok = g.new_label
      g.setup_unwind ensure_ex, 1
    end

    ex = g.new_label
    done = g.new_label

    g.push_exception_state
    g.set_stack_local(ex_state = g.new_stack_local)
    g.pop

    # Evaluate body
    g.setup_unwind ex, 0
    SpecialForm[:do].bytecode(g, body)
    g.pop_unwind
    g.goto done

    # Body raised an exception
    ex.set!

    # Save exception state for re-raise
    g.push_exception_state
    g.set_stack_local(raised_ex_state = g.new_stack_local)
    g.pop

    # Push exception for rescue conditions
    g.push_current_exception

    rescue_clauses.each do |clause|
      # Parse either (rescue e body) or (rescue [e Exception] body)
      if clause[0].is_a?(AST::Identifier)
        name = clause.shift
        conditions = []
      elsif clause[0].is_a?(AST::ArrayLiteral)
        conditions = clause.shift.elements
        name = conditions.first
        conditions = conditions.drop(1)
        g.compile_error "Expected identifier as first form of rescue clause binding" unless name.is_a?(AST::Identifier)
      else
        g.compile_error "Expected identifier or array as first form of rescue clause"
      end

      # Default to StandardError for (rescue e body) and (rescue [e] body)
      conditions << AST::Identifier.new(name.line, :StandardError) if conditions.empty?

      body = g.new_label
      next_rescue = g.new_label

      conditions.each do |cond|
        g.dup # The exception
        cond.bytecode(g)
        g.swap
        g.send :===, 1
        g.git body
      end
      g.goto next_rescue

      # This rescue condition matched
      body.set!

      # Create a new scope to hold the exception
      scope = AST::LetScope.new(g.scope)
      g.scopes << scope

      # Exception is still on the stack
      g.set_local scope.new_local(name)
      g.pop

      SpecialForm[:do].bytecode(g, clause)

      # Yay!
      g.clear_exception
      g.goto done

      g.scopes.pop

      # Rescue condition did not match
      next_rescue.set!
    end

    # No rescue conditions matched, re-raise
    g.pop # The exception

    # Re-raise the original exception
    g.push_stack_local raised_ex_state
    g.restore_exception_state
    g.reraise

    # Body executed without exception or was rescued
    done.set!

    g.push_stack_local raised_ex_state
    g.restore_exception_state

    if ensure_clause
      g.pop_unwind
      g.goto ensure_ok

      # Body raised an exception
      ensure_ex.set!

      # Execute ensure clause
      g.push_exception_state
      ensure_clause.each do |expr|
        expr.bytecode(g)
        g.pop # Ensure cannot return anything
      end
      g.restore_exception_state

      g.reraise

      # Body executed without exception or was rescued
      ensure_ok.set!

      # Execute ensure clause
      ensure_clause.each do |expr|
        expr.bytecode(g)
        g.pop
      end
    end
  end
end
