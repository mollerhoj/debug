# frozen_string_literal: true

module DEBUGGER__
  FrameInfo = Struct.new(:location, :self, :binding, :iseq, :class, :frame_depth,
                          :has_return_value, :return_value,
                          :has_raised_exception, :raised_exception,
                          :show_line,
                          :_local_variables, :_callee # for recorder
                        )

  # extend FrameInfo with debug.so
  if File.exist? File.join(__dir__, 'debug.so')
    require_relative 'debug.so'
  else
    require_relative 'debug'
  end

  class FrameInfo
    HOME = ENV['HOME'] ? (ENV['HOME'] + '/') : nil

    def path
      location.path
    end

    def realpath
      location.absolute_path
    end

    def pretty_path
      return '#<none>' unless path = self.path
      use_short_path = CONFIG[:use_short_path]

      case
      when use_short_path && path.start_with?(dir = CONFIG["rubylibdir"] + '/')
        path.sub(dir, '$(rubylibdir)/')
      when use_short_path && Gem.path.any? do |gp|
          path.start_with?(dir = gp + '/gems/')
        end
        path.sub(dir, '$(Gem)/')
      when HOME && path.start_with?(HOME)
        path.sub(HOME, '~/')
      else
        path
      end
    end

    def name
      # p frame_type: frame_type, self: self
      case frame_type
      when :block
        level, block_loc, _args = block_identifier
        "block in #{block_loc}#{level}"
      when :method
        ci, _args = method_identifier
        "#{ci}"
      when :c
        c_identifier
      when :other
        other_identifier
      end
    end

    def file_lines
      SESSION.source(self.iseq)
    end

    def frame_type
      if self.local_variables && iseq
        if iseq.type == :block
          :block
        elsif callee
          :method
        else
          :other
        end
      else
        :c
      end
    end

    BLOCK_LABL_REGEXP = /\Ablock( \(\d+ levels\))* in (.+)\z/

    def block_identifier
      return unless frame_type == :block
      args = parameters_info(iseq.argc)
      _, level, block_loc = location.label.match(BLOCK_LABL_REGEXP).to_a
      [level || "", block_loc, args]
    end

    def method_identifier
      return unless frame_type == :method
      args = parameters_info(iseq.argc)
      ci = "#{klass_sig}#{callee}"
      [ci, args]
    end

    def c_identifier
      return unless frame_type == :c
      "[C] #{klass_sig}#{location.base_label}"
    end

    def other_identifier
      return unless frame_type == :other
      location.label
    end

    def callee
      self._callee ||= self.binding&.eval('__callee__')
    end

    def return_str
      if self.binding && iseq && has_return_value
        DEBUGGER__.short_inspect(return_value)
      end
    end

    def location_str
      "#{pretty_path}:#{location.lineno}"
    end

    private def make_binding
      __newb__ = self.self.instance_eval('binding')
      self.local_variables.each{|var, val|
        __newb__.local_variable_set(var, val)
      }
      __newb__
    end

    def eval_binding
      if b = self.binding
        b
      elsif self.local_variables
        make_binding
      end
    end

    def local_variables
      if lvars = self._local_variables
        lvars
      elsif b = self.binding
        lvars = b.local_variables.map{|var|
          [var, b.local_variable_get(var)]
        }.to_h
        self._local_variables = lvars
      end
    end

    private

    def get_singleton_class obj
      obj.singleton_class # TODO: don't use it
    rescue TypeError
      nil
    end

    private def local_variable_get var
      local_variables[var]
    end

    def parameters_info(argc)
      vars = iseq.locals[0...argc]
      vars.map{|var|
        begin
          { name: var, value: DEBUGGER__.short_inspect(local_variable_get(var)) }
        rescue NameError, TypeError
          nil
        end
      }.compact
    end

    def klass_sig
      if self.class == get_singleton_class(self.self)
        "#{self.self}."
      else
        "#{self.class}#"
      end
    end
  end
end
