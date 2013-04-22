# encoding: utf-8

require 'is/monkey/namespace'

$module_hook_start = __LINE__

class Module

  def module_scope
    m = self.inspect
    if m[0...8] == '#<Class:'
      s = m.rindex '>'
      v = m[8...s]
      begin
        value = sandbox { eval v }
        return [value, :class]
      rescue
        return [nil, nil]
      end
    else
      return [self, :instance]
    end
  end

  alias :old_attr :attr
  alias :old_attr_reader :attr_reader
  alias :old_attr_writer :attr_writer
  alias :old_attr_accessor :attr_accessor

  def parse_caller clr
    clr.each do |s|
      if s.include?('`<module:') || s.include?('`<class:') ||
          s.include?("`singletonclass'")
        a = s.split(':')
        begin
          return [a[0], a[1].to_i]
        rescue
        end
      end
    end
    return nil
  end

  def attr *names
    RDot.attr_register *module_scope, [:r, parse_caller(caller)], names
    old_attr *names
  end

  def attr_reader *names
    RDot.attr_register *module_scope, [:r, parse_caller(caller)], names
    old_attr_reader *names
  end

  def attr_writer *names
    RDot.attr_register *module_scope, [:w, parse_caller(caller)], names
    old_attr_writer *names
  end

  def attr_accessor *names
    RDot.attr_register *module_scope, [:r, :w, parse_caller(caller)], names
    old_attr_accessor *names
  end

end

$module_hook_end = __LINE__

pp [$module_hook_start, $module_hook_end]

module RDot

  VERSION = '0.10.0'

  class << self

    def attr_list
      @@attr_list ||= {}
      @@attr_list
    end

    def attr_register mod, scope, access, names
      @@attr_list ||= {}
      @@attr_list[mod] ||= {}
      @@attr_list[mod][scope] ||= {}
      names.each do |name|
        @@attr_list[mod][scope][name] = access
      end
    end

  end

  class Method

    attr_reader :ruby
    attr_reader :owner
    attr_reader :name
    attr_reader :signature
    attr_reader :source
    attr_reader :file
    attr_reader :line

    def initialize owner, ruby, opts = {}
      @owner = owner
      @opts = opts
      @ruby = ruby
      @name = ruby.name
      @scope = opts[:scope] || :instance
      @source = ruby.source_location
      if @source
        #pp [@name, @source, __FILE__]
      if @source[0] == __FILE__ &&
          ($module_hook_start..$module_hook_end).include?(@source[1])
        pp [@name, owner.name, @source]
      end
        @file = @source[0]
        $:.sort.reverse.each do |path|
          l = path.length
          if @file[0...l] == path
            @file = @file[l..-1]
            break
          end
        end
        @line = @source[1]
      end
      @signature = @name.to_s
      if ! @opts[:hide_arguments]
        letter = 'a'
        first = true
        ruby.parameters.each do |par|
          if par.size == 1
            n = letter
            letter = letter.succ
          else
            n = par[1]
          end
          case par[0]
          when :req
            @signature += "#{first && ' ' || ', '}#{n}"
          when :opt
            @signature += "#{first && ' [' || '[, '}#{n}]"
          when :rest
            @signature += "#{first && ' *' || ', *'}#{n}"
          when :block
            @signature += "#{first && ' &' || ', &'}#{n}"
          end
          first = nil
        end
      end
    end

  end

  class Module

    include Comparable

    attr_reader :name

    def initialize mod, opts = {}
      @opts = opts
      @module = mod
      @name = mod.name
      @instance_public_methods = {}
      @instance_protected_methods = {}
      @instance_private_methods = {}
      @class_public_methods = {}
      @class_protected_methods = {}
      @class_private_methods = {}
      @constants = {}
      if ! @opts[:no_init]
        if ! @opts[:hide_methods]
          mod.instance_methods(false).each do |m|
            m = mod.instance_method(m)
            @instance_public_methods[m.name] = RDot::Method.new self, m, @opts
          end
          mod.methods(false).each do |m|
            m = mod.method(m)
            @class_public_methods[m.name] = RDot::Method.new self, m,
                @opts.merge(:scope => :class)
          end
          if @opts[:show_protected]
            mod.instance_protected_methods(false) do |m|
            m = mod.instance_method(m)
              @instance_protected_methods[m.name] = RDot::Method.new self, m,
                  @opts.merge(:visibility => :protected)
            end
            mod.protected_methods(false).each do |m|
            m = mod.method(m)
              @class_protected_methods[m.name] = RDot::Method.new self, m,
                  @opts.merge(:visibility => :protected, :scope => :class)
            end
          end
          if @opts[:show_private]
            mod.instance_private_methods(false) do |m|
            m = mod.instance_method(m)
              @instance_private_methods[m.name] = RDot::Method.new self, m,
                  @opts.merge(:visibility => :private)
            end
            mod.private_methods(false).each do |m|
            m = mod.method(m)
              @class_private_methods[m.name] = RDot::Method.new self, m,
                  @opts.merge(:visibility => :private, :scope => :class)
            end
          end
        end
        if ! @opts[:hide_constants]
          mod.constants(false).each do |c|
            @constants[c] = mod.const_get c
          end
        end
      end
    end

    def add_method m
      if m.visibility == :private
        if m.scope == :class
          @class_private_methods[m.name] = m
        else
          @instance_private_methods[m.name] = m
        end
      elsif m.visibility == :protected
        if m.scope == :class
          @class_protected_methods[m.name] = m
        else
          @instance_protected_methods[m.name] = m
        end
      else
        if m.scope == :class
          @class_public_methods[m.name] = m
        else
          @instance_public_methods[m.name] = m
        end
      end
    end

    def add_constant name, value
      @constants[name] = value
    end

    def [] name
      @instance_public_methods[name] || @instance_protected_methods[name] ||
          @instance_private_methods[name] || @class_public_methods[name] ||
          @class_protected_methods[name] || @class_private_methods[name] ||
          @constants[name]
    end

    def <=> other
      @name <=> other.name
    end

    def sub other
      if other == nil
        return self
      end
      result = RDot::Module.new @module, :no_init => true
      @instance_public_methods.each do |n, m|
        result.add_method m if other[n].ruby != m.ruby
      end
      @instance_protected_methods.each do |n, m|
        result.add_method m if other[n].ruby != m.ruby
      end
      @instance_private_methods.each do |n, m|
        result.add_method m if other[n].ruby != m.ruby
      end
      @class_public_methods.each do |n, m|
        result.add_method m if other[n].ruby != m.ruby
      end
      @class_protected_methods.each do |n, m|
        result.add_method m if other[n].ruby != m.ruby
      end
      @class_private_methods.each do |n, m|
        result.add_method m if other[n].ruby != m.ruby
      end
      @constants.each do |n, c|
        result.add_constant n, c if other[n] != c
      end
      if @instance_public_methods.empty? &&
          @instance_protected_methods.empty? &&
          @instance_private_methods.empty? && @class_public_methods.empty? &&
          @class_protected_methods.empty? && @class_private_methods.empty? &&
          @constants.empty?
        nil
      else
        result
      end
    end

    protected :add_method, :add_constant

  end

  class Space

    include Enumerable

    attr_reader :modules

    def initialize opts = {}
      @opts = opts
      @modules = {}
      if ! opts[:no_init]
        ObjectSpace.each_object ::Module do |m|
          catch :module do
            if (exclude_classes = @opts[:exclude_classes])
              exclude_classes.each { |cls| throw :module if m <= cls }
            end
            if (only_classes = @opts[:only_classes])
              only_classes.each { |cls| throw :module if !(m <= cls) }
            end
            if (exclude_namespaces = @opts[:exclude_namespaces])
              exclude_namespaces.each do |ns|
                throw :module if m == ns || m.in?(ns)
              end
            end
            if (only_namespaces = @opts[:only_namespaces])
              only_namespaces.each do |ns|
                throw :module if m != ns && ! m.in?(ns)
              end
            end
            if @opts[:only_global]
              throw :module if !m.global?
            end
            @modules[m.name] = RDot::Module.new m, @opts
          end
        end
      end
    end

    def [] name
      @modules[name]
    end

    def []= name, m
      @modules[name] = m
    end

    def each &block
      @modules.each &block
    end

    def sub other
      result = RDot::Space.new :no_init => true
      @modules.each do |m|
        sm = m.sub other[m.name]
        result[m.name] = sm if sm
      end
      result
    end

    protected :[]=

  end

end
