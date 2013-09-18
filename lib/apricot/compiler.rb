module Apricot
  module Compiler
    module_function

    def generate(forms, file = "(none)", line = 1, evaluate = false)
      g = Generator.new
      g.name = :__apricot__
      g.file = file.to_sym

      g.scopes << TopLevelScope.new

      g.set_line(line)

      if forms.empty?
        g.push_nil
      else
        forms.each_with_index do |e, i|
          g.pop unless i == 0
          bytecode(g, e)

          # We evaluate top level forms as we generate the bytecode for them
          # so macros can be used immediately after their definitions.
          eval_form(e, file) if evaluate
        end
      end

      g.ret

      scope = g.scopes.pop
      g.local_count = scope.local_count
      g.local_names = scope.local_names

      g.close
      g.encode
      cc = g.package(Rubinius::CompiledCode)
      cc.scope = Rubinius::ConstantScope.new(Object)
      cc
    end

    def compile_and_eval_file(file)
      cc = generate(Reader.read_file(file), file, 1, true)

      if Rubinius::CodeLoader.save_compiled?
        compiled_name = Rubinius::Compiler.compiled_name(file)

        dir = File.dirname(compiled_name)

        unless File.directory?(dir)
          parts = []

          until dir == "/" or dir == "."
            parts << dir
            dir = File.dirname(dir)
          end

          parts.reverse_each do |d|
            Dir.mkdir d unless File.directory?(d)
          end
        end

        Rubinius::CompiledFile.dump cc, compiled_name,
          Rubinius::Signature, Rubinius::RUBY_LIB_VERSION
      end

      cc
    end

    def compile_form(form, file = "(eval)", line = 1)
      generate([form], file, line)
    end

    def eval_form(form, file = "(eval)", line = 1)
      Rubinius.run_script(compile_form(form, file, line))
    end

    def eval(code, file = "(eval)", line = 1)
      forms = Reader.read_string(code, file,line)

      return nil if forms.empty?

      forms[0..-2].each do |form|
        eval_form(form, file, line)
      end

      # Return the result of the last form in the program.
      eval_form(forms.last, file, line)
    end

    def bytecode(g, form, quoted = false, macroexpand = true)
      pos(g, form)

      begin
        form.bytecode(g, quoted, macroexpand)
      rescue NoMethodError
        g.compile_error "Can't generate bytecode for #{form} (#{form.class})"
      end
    end

    def pos(g, form)
      if (meta = form.apricot_meta) && (line = meta[:line])
        g.set_line(line)
      end
    end
  end
end
