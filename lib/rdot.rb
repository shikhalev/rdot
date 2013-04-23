# encoding: utf-8

require 'is/monkey/sandbox'
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

  alias :rdot_old_attr :attr
  alias :rdot_old_attr_reader :attr_reader
  alias :rdot_old_attr_writer :attr_writer
  alias :rdot_old_attr_accessor :attr_accessor

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
    RDot.register_attribute *module_scope, names, '[r]', parse_caller(caller)
    rdot_old_attr *names
  end

  def attr_reader *names
    RDot.register_attribute *module_scope, names, '[r]', parse_caller(caller)
    rdot_old_attr_reader *names
  end

  def attr_writer *names
    RDot.register_attribute *module_scope, names, '[w]', parse_caller(caller)
    rdot_old_attr_writer *names
  end

  def attr_accessor *names
    RDot.register_attribute *module_scope, names, '[rw]', parse_caller(caller)
    rdot_old_attr_accessor *names
  end

  private :module_scope, :parse_caller, :attr, :attr_reader, :attr_writer,
      :attr_accessor

end

$module_hook_end = __LINE__

class Object

  def echo *args
    args.each do |a|
      self << a
    end
    self << "\n"
  end

end

class String

  def escape
    gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub("\n", '\n')
  end

end

module RDot

  VERSION = '0.10.0'

  class << self

    def register_attribute mod, scope, names, access, source
      @attributes ||= {}
      @attributes[mod] ||= {}
      @attributes[mod][scope] ||= {}
      names.each do |name|
        @attributes[mod][scope][name.intern] = {
          :access => access,
          :source => source
        }
      end
    end

    def get_file file
      src = File.expand_path file
      $:.each do |dir|
        dir = File.expand_path dir
        len = dir.length
        if src[0...len] == dir
          src = src[len..-1]
          if src[0] == '/'
            src = src[1..-1]
          end
          return src
        end
      end
      return file
    end

    def get_method_object mod, scope, name
      case scope
      when :instance
        mod.instance_method(name)
      when :class
        mod.singleton_class.instance_method(name)
      end
    end

    def add_method acc, mod, scope, visibility, name, opts = {}
      m = get_method_object mod, scope, name
      src = m.source_location
      obj = {}
      if src
        if src[0] == __FILE__ &&
            ($module_hook_start..$module_hook_end).include?(src[1])
          nm = name.to_s
          nm = nm[0..-2] if nm[-1] == '='
          nm = nm.intern
          if @attributes && @attributes[mod] && @attributes[mod][scope] &&
              @attributes[mod][scope][nm]
            src = @attributes[mod][scope][nm][:source]
            obj[:access] = @attributes[mod][scope][nm][:access]
          end
        end
        obj[:file] = get_file src[0]
        obj[:line] = src[1]
        if opts[:exclude_files]
          opts[:exclude_files].each do |f|
            if File.expand_path(f) == File.expand_path(src[0])
              return nil
            end
          end
        end
        if opts[:filter_files]
          opts[:filter_files].each do |f|
            if File.expand_path(f) == File.expand_path(src[0])
              return nil
            end
          end
        end
      elsif opts[:filter_files]
        return nil
      end
      acc[scope] ||= {}
      acc[scope][visibility] ||= {}
      if opts[:select_attributes] && obj[:access]
        obj[:signature] = nm.to_s + ' ' + obj[:access]
        acc[scope][visibility][:attributes] ||= {}
        acc[scope][visibility][:attributes][nm] = obj
      else
        ltr = 'a'
        obj[:signature] = name.to_s + ' ' + m.parameters.map do |q, n|
          nm = n || ltr
          ltr = ltr.succ
          case q
          when :req
            nm
          when :opt
            "#{nm} = <def>"
          when :rest
            "*#{nm}"
          when :block
            "&#{nm}"
          end
        end.join(', ')
        acc[scope][visibility][:methods] ||= {}
        acc[scope][visibility][:methods][name] = obj
      end
      return obj
    end

    def get_module mod, opts = {}
      result = {}
      incs = mod.included_modules - [mod]
      exts = mod.singleton_class.included_modules - Module.included_modules
      if Class === mod
        exts -= Class.included_modules
        result[:superclass] = mod.superclass && mod.superclass.inspect || nil
        if mod.superclass
          incs -= mod.superclass.included_modules
          exts -= mod.superclass.singleton_class.included_modules
        end
      end
      incs.dup.each { |d| incs -= d.included_modules }
      exts.dup.each { |d| exts -= d.included_modules }
      result[:included] = incs.map &:inspect
      result[:extended] = exts.map &:inspect
      result[:nested] = mod.namespace && mod.namespace.inspect || nil
      if ! opts[:hide_constants]
        result[:constants] = {}
        mod.constants(false).each do |c|
          next if mod == Object && c == :Config
          result[:constants][c] = mod.const_get(c).class.inspect
        end
      end
      if ! opts[:hide_methods]
        mod.instance_methods(false).each do |m|
          add_method result, mod, :instance, :public, m, opts
        end
        mod.singleton_class.instance_methods(false).each do |m|
          add_method result, mod, :class, :public, m, opts
        end
        if opts[:show_protected]
          mod.protected_instance_methods(false).each do |m|
            add_method result, mod, :instance, :protected, m, opts
          end
          mod.singleton_class.protected_instance_methods(false).each do |m|
            add_method result, mod, :class, :protected, m, opts
          end
        end
        if opts[:show_private]
          mod.private_instance_methods(false).each do |m|
            add_method result, mod, :instance, :private, m, opts
          end
          mod.singleton_class.private_instance_methods(false).each do |m|
            add_method result, mod, :class, :private, m, opts
          end
        end
      end
      result
    end

    def add_module acc, mod, opts = {}
      if opts[:exclude_classes]
        opts[:exclude_classes].each do |c|
          return nil if mod <= c
        end
      end
      if opts[:filter_classes]
        opts[:filter_classes].each do |c|
          return nil unless mod <= c
        end
      end
      if opts[:exclude_namespaces]
        opts[:exclude_namespaces].each do |n|
          return nil if mod == n || mod.in?(n)
        end
      end
      if opts[:filter_namespaces]
        opts[:filter_namespaces].each do |n|
          return nil unless mod == n || mod.in?(n)
        end
      end
      if opts[:filter_global]
        return nil unless mod.global?
      end
      acc[mod.inspect] = get_module mod, opts
    end

    def snapshot opts = {}
      result = {}
      ObjectSpace.each_object(Module) { |m| add_module result, m, opts }
      result
    end

    def diff_module base, other
      if ! other
        return self
      end
      result = {}
      result[:superclass] = base[:superclass]
      result[:nested] = base[:nested]
      result[:included] = base[:included] - other[:included]
      result[:extended] = base[:extended] - other[:extended]
      result[:constants] = {}
      if base[:constants]
        base[:constants].each do |c|
          if base[:constants][c] != other[:constants][c]
            result[:constants][c] = base[:constants][c]
          end
        end
      end
      [:class, :instance].each do |s|
        [:public, :protected, :private].each do |v|
          [:attributes, :methods].each do |k|
            if base[s] && base[s][v] && base[s][v][k]
              base[s][v][k].each do |n, m|
                unless other[s] && other[s][v] && other[s][v][k] &&
                    other[s][v][k][n] &&
                    other[s][v][k][n][:file] == m[:file] &&
                    other[s][v][k][n][:line] == m[:line]
                  result[s] ||= {}
                  result[s][v] ||= {}
                  result[s][v][k] ||= {}
                  result[s][v][k][n] = m
                end
              end
            end
          end
        end
      end
      if result[:included].empty? && result[:extended].empty? &&
          result[:constants].empty? && result[:class].nil? &&
          result[:instance].nil?
        nil
      else
        result
      end
    end

    def diff base, other
      result = {}
      base.each do |n, m|
        d = diff_module m, other[n]
        result[n] = d if d
      end
      result
    end

    private :get_file, :get_method_object, :get_module, :add_method, :add_module

  end

end
