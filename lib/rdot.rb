# encoding: utf-8

require 'is/monkey/sandbox'
require 'is/monkey/namespace'

$module_hook_start = __LINE__

# @api ignore
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
      :attr_accessor, :rdot_old_attr, :rdot_old_attr_accessor,
      :rdot_old_attr_reader, :rdot_old_attr_writer

end

$module_hook_end = __LINE__

module RDot

  VERSION = '0.10.8'

  class << self

    # @api ignore
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

    def add_method acc, mod, scope, visibility, name, opts
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
          else
            src = ['', nil]
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
            if File.expand_path(f) != File.expand_path(src[0])
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
        if ! opts[:hide_arguments]
          ltr = 'a'
          obj[:signature] = name.to_s + '(' + m.parameters.map do |q, n|
            nm = n || ltr
            ltr = ltr.succ
            case q
            when :req
              nm
            when :opt
              "#{nm} = <…>"
            when :rest
              "*#{nm}"
            when :block
              "&#{nm}"
            end
          end.join(', ') + ')'
        else
          obj[:signature] = name.to_s + '()'
        end
        acc[scope][visibility][:methods] ||= {}
        acc[scope][visibility][:methods][name] = obj
      end
      return obj
    end

    def get_module mod, opts
      result = {}
      result[:module] = mod
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
      if opts[:no_scan]
        return result
      end
      if ! opts[:hide_constants]
        result[:constants] = {}
        mod.constants(false).each do |c|
          next if mod == Object && c == :Config
          if (auto = mod.autoload?(c))
            result[:constants][c] = 'auto:' + get_file(auto)
          elsif mod.const_defined? c
            result[:constants][c] = mod.const_get(c).class.inspect
          else
            result[:constants][c] = 'undefined'
          end
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

    def add_module acc, mod, opts
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

    # @param [Hash] opts
    # @return [Hash]
    def snapshot opts = {}
      opts = defaults.merge opts
      result = {}
      ObjectSpace.each_object(Module) { |m| add_module result, m, opts }
      result
    end

    def diff_module base, other, opts
      if ! other
        return base.merge :new => true
      end
      if opts[:show_preloaded]
        return base
      end
      result = {}
      result[:module] = base[:module]
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
        if result[:module] == Object
          result[:included] << 'Kernel' if ! result[:included].include?(Kernel)
        end
        result
      end
    end

    # @param [Hash] base
    # @param [Hash] other
    # @param [Hash] opts
    # @return [Hash]
    def diff base, other, opts = {}
      opts = defaults.merge opts
      if other == nil
        return base
      end
      result = {}
      base.each do |n, m|
        d = diff_module m, other[n], opts
        result[n] = d if d
      end
      result
    end

    def find_module space, name
      return space[name] if space[name]
      begin
        mod = sandbox { eval name }
        return get_module(mod, :no_scan => true)
      rescue
      end
      nil
    end

    # @return [Hash]
    def defaults
      {
        :graph_fontname                 => 'sans-serif',
        :graph_fontsize                 => 24,
        :graph_label                    => 'RDot Graph',
        :node_fontname                  => 'monospace',
        :node_fontsize                  => 9,
        :color_class                    => '#BBFFBB',
        :color_class_preloaded          => '#CCEECC',
        :color_class_core               => '#DDFF99',
        :color_exception                => '#FFBBBB',
        :color_exception_preloaded      => '#EECCCC',
        :color_exception_core           => '#FFDD99',
        :color_module                   => '#BBBBFF',
        :color_module_preloaded         => '#CCCCEE',
        :color_module_core              => '#99DDFF',
        :color_protected                => '#EEEEEE',
        :color_private                  => '#DDDDDD',
        :color_inherited                => '#0000FF',
        :color_included                 => '#00AAFF',
        :color_extended                 => '#AA00FF',
        :color_nested                   => '#EEEEEE'
      }
    end

    def node_name name
      'node_' + name.gsub(/\W/, '_')
    end

    def module_stage m
      if @preset.include? m[:module]
        :core
      elsif m[:new]
        :new
      else
        :old
      end
    end

    def node_color m, opts
      mod = m[:module]
      stg = module_stage m
      if Class === mod
        if mod <= Exception
          case stg
          when :core
            opts[:color_exception_core]
          when :old
            opts[:color_exception_preloaded]
          when :new
            opts[:color_exception]
          end
        else
          case stg
          when :core
            opts[:color_class_core]
          when :old
            opts[:color_class_preloaded]
          when :new
            opts[:color_class]
          end
        end
      else
        case stg
        when :core
          opts[:color_module_core]
        when :old
          opts[:color_module_preloaded]
        when :new
          opts[:color_module]
        end
      end
    end

    def module_kind m
      stg = module_stage m
      if Class === m[:module]
        if m[:module] <= Exception
          "[#{stg}] exception"
        else
          "[#{stg}] class"
        end
      else
        "[#{stg}] module"
      end
    end

    # @param [String] s
    # @return [String]
    def escape s
      s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub("\n", '\n')
    end

    def dot_constants m
      result = []
      if m[:constants]
        m[:constants].sort.each do |n, c|
          result << "#{escape(n.to_s)} &lt;#{escape(c)}&gt;"
        end
      end
      if result.size != 0
        '<TR><TD ROWSPAN="' + result.size.to_s +
            '" ALIGN="RIGHT" VALIGN="TOP">const</TD><TD COLSPAN="3" ALIGN="LEFT">' +
            result.join('</TD></TR><TR><TD COLSPAN="3" ALIGN="LEFT">') +
            '</TD></TR>'
      else
        ''
      end
    end

    def dot_scope m, scope, opts
      result = []
      if m[scope]
        if m[scope][:public]
          if m[scope][:public][:attributes]
            m[scope][:public][:attributes].sort.each do |n, a|
              result << '<TD ALIGN="LEFT">' + escape(a[:signature]) +
                  '</TD><TD ALIGN="RIGHT">' + escape(a[:file].to_s) +
                  '</TD><TD ALIGN="RIGHT">' + a[:line].to_s + '</TD>'
            end
          end
          if m[scope][:public][:methods]
            m[scope][:public][:methods].sort.each do |n, a|
              result << '<TD ALIGN="LEFT">' + escape(a[:signature]) +
                  '</TD><TD ALIGN="RIGHT">' + escape(a[:file].to_s) +
                  '</TD><TD ALIGN="RIGHT">' + a[:line].to_s + '</TD>'
            end
          end
        end
        if m[scope][:protected]
          if m[scope][:protected][:attributes]
            m[scope][:protected][:attributes].sort.each do |n, a|
              result << '<TD BGCOLOR="' + opts[:color_protected] +
                  '" ALIGN="LEFT">' + escape(a[:signature]) +
                  '</TD><TD BGCOLOR="' + opts[:color_protected] +
                  '" ALIGN="RIGHT">' + escape(a[:file].to_s) +
                  '</TD><TD BGCOLOR="' + opts[:color_protected] +
                  '" ALIGN="RIGHT">' + a[:line].to_s + '</TD>'
            end
          end
          if m[scope][:protected][:methods]
            m[scope][:protected][:methods].sort.each do |n, a|
              result << '<TD BGCOLOR="' + opts[:color_protected] +
                  '" ALIGN="LEFT">' + escape(a[:signature]) +
                  '</TD><TD BGCOLOR="' + opts[:color_protected] +
                  '" ALIGN="RIGHT">' + escape(a[:file].to_s) +
                  '</TD><TD BGCOLOR="' + opts[:color_protected] +
                  '" ALIGN="RIGHT">' + a[:line].to_s + '</TD>'
            end
          end
        end
        if m[scope][:private]
          if m[scope][:private][:attributes]
            m[scope][:private][:attributes].sort.each do |n, a|
              result << '<TD BGCOLOR="' + opts[:color_private] +
                  '" ALIGN="LEFT">' + escape(a[:signature]) +
                  '</TD><TD BGCOLOR="' + opts[:color_private] +
                  '" ALIGN="RIGHT">' + escape(a[:file].to_s) +
                  '</TD><TD BGCOLOR="' + opts[:color_private] +
                  '" ALIGN="RIGHT">' + a[:line].to_s + '</TD>'
            end
          end
          if m[scope][:private][:methods]
            m[scope][:private][:methods].sort.each do |n, a|
              result << '<TD BGCOLOR="' + opts[:color_private] +
                  '" ALIGN="LEFT">' + escape(a[:signature]) +
                  '</TD><TD BGCOLOR="' + opts[:color_private] +
                  '" ALIGN="RIGHT">' + escape(a[:file].to_s) +
                  '</TD><TD BGCOLOR="' + opts[:color_private] +
                  '" ALIGN="RIGHT">' + a[:line].to_s + '</TD>'
            end
          end
        end
      end
      if result.size != 0
        '<TR><TD ROWSPAN="' + result.size.to_s +
            '" ALIGN="RIGHT" VALIGN="TOP">' + scope.to_s + '</TD>' +
            result.join('</TR><TR>') + '</TR>'
      else
        ''
      end
    end

    def node_label name, m, opts
      result = []
      result << '<TABLE CELLBORDER="0" CELLSPACING="0">'
      result << '<TR>'
      result << '<TD ALIGN="RIGHT" BGCOLOR="' + node_color(m, opts) + '">'
      result << '<B>'
      result << module_kind(m)
      result << '</B>'
      result << '</TD>'
      result << '<TD COLSPAN="3" ALIGN="LEFT" BGCOLOR="' +
          node_color(m, opts) + '">'
      result << '<B>'
      result << escape(name)
      result << '</B>'
      result << '</TD>'
      result << '</TR>'
      result << dot_constants(m)
      result << dot_scope(m, :class, opts)
      result << dot_scope(m, :instance, opts)
      result << '</TABLE>'
      result.join ''
    end

    def dot_module space, name, m, opts
      if m == nil
        $stderr.puts "Warning: nil module by name \"#{name}\"!"
        return nil
      end
      if @processed.include?(m[:module])
        return nil
      else
        @processed << m[:module]
      end
      result = []
      result << node_name(name) + '['
      result << '  label=<' + node_label(name, m, opts) + '>'
      result << '];'
      if m[:nested] && ! opts[:hide_nested]
        ns = find_module space, m[:nested]
        result << dot_module(space, m[:nested], ns, opts)
        @nested << node_name(m[:nested]) + ' -> ' + node_name(name) + ';'
      end
      if ! opts[:hide_extended]
        m[:extended].each do |e|
          ext = find_module space, e
          result << dot_module(space, e, ext, opts)
          @extended << node_name(e) + ' -> ' + node_name(name) + ';'
        end
      end
      if ! opts[:hide_included]
        m[:included].each do |i|
          next if m[:module].name == 'CMath' && i == 'Math'
          inc = find_module space, i
          result << dot_module(space, i, inc, opts)
          @included << node_name(i) + ' -> ' + node_name(name) + ';'
        end
      end
      if m[:superclass]
        spc = find_module space, m[:superclass]
        result << dot_module(space, m[:superclass], spc, opts)
        @inherited << node_name(m[:superclass]) + ' -> ' + node_name(name) + ';'
      end
      result.join "\n  "
    end

    # @param [Hash] space
    # @param [Hash] opts
    # @return [String]
    def dot space, opts = {}
      opts = defaults.merge opts
      result = []
      result << 'digraph graph_RDot{'
      result << '  graph['
      result << '    rankdir=LR,'
      result << '    splines=true,'
      result << '    labelloc=t, mclimim=10,'
      result << '    fontname="' + opts[:graph_fontname] + '",'
      result << '    fontsize=' + opts[:graph_fontsize].to_s + ','
      result << '    label="' + opts[:graph_label] + '"'
      result << '  ];'
      result << '  node['
      result << '    shape=plaintext,'
      result << '    fontname="' + opts[:node_fontname] + '",'
      result << '    fontsize=' + opts[:node_fontsize].to_s + ''
      result << '  ];'
      result << '  edge['
      result << '    dir=back,'
      result << '    arrowtail=vee,'
      result << '    penwidth=0.5, arrowsize=0.7'
      result << '  ];'
      @processed = []
      @nested = []
      @extended = []
      @included = []
      @inherited = []
      space.each do |n, m|
        mm = dot_module space, n, m, opts
        result << '  ' + mm if mm
      end
      result << '  subgraph subNested{'
      result << '    edge['
      result << '      color="' + opts[:color_nested] + '",'
      result << '      weight=10,'
      result << '      minlen=-1'
      result << '    ];'
      result << '    ' + @nested.join("\n    ")
      result << '  }'
      result << '  subgraph subExtended{'
      result << '    edge['
      result << '      color="' + opts[:color_extended] + '",'
      result << '      weight=1,'
      result << '      minlen=0'
      result << '    ];'
      result << '    ' + @extended.join("\n    ")
      result << '  }'
      result << '  subgraph subIncluded{'
      result << '    edge['
      result << '      color="' + opts[:color_included] + '",'
      result << '      weight=2,'
      result << '      minlen=1'
      result << '    ];'
      result << '    ' + @included.join("\n    ")
      result << '  }'
      result << '  subgraph subInherited{'
      result << '    edge['
      result << '      color="' + opts[:color_inherited] + '",'
      result << '      weight=10,'
      result << '      minlen=1'
      result << '    ];'
      result << '    ' + @inherited.join("\n    ")
      result << '  }'
      result << '}'
      result.join "\n"
    end

    private :get_file, :get_method_object, :get_module, :add_method,
        :add_module, :diff_module, :find_module, :dot_module, :node_name,
        :node_color, :node_label, :module_kind, :dot_constants, :dot_scope,
        :module_stage

  end

  @preset = []
  ObjectSpace.each_object(Module) { |m| @preset << m if m != ::RDot }

end

