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
    RDot.attr_register *module_scope, names, '[r]', parse_caller(caller)
    old_attr *names
  end

  def attr_reader *names
    RDot.attr_register *module_scope, names, '[r]', parse_caller(caller)
    old_attr_reader *names
  end

  def attr_writer *names
    RDot.attr_register *module_scope, names, '[w]', parse_caller(caller)
    old_attr_writer *names
  end

  def attr_accessor *names
    RDot.attr_register *module_scope, names, '[rw]', parse_caller(caller)
    old_attr_accessor *names
  end

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

  def short max
    if length > max
      self[0..max-20] + ' ... ' + self[-15..-1]
    else
      self
    end
  end

end

module RDot

  VERSION = '0.10.0'

  class << self

    def attr_list
      @@attr_list ||= {}
      @@attr_list
    end

    def attr_register mod, scope, names, access, source
      @@attr_list ||= {}
      @@attr_list[mod] ||= {}
      @@attr_list[mod][scope] ||= {}
      names.each do |name|
        @@attr_list[mod][scope][name] = { :access => access, :source => source }
      end
    end

    def processed
      @@processed ||= []
      @@processed
    end

    def processed_push value
      @@processed ||= []
      @@processed.push value.module
    end

    def processed? value
      @@processed ||= []
      @@processed.include? value.module
    end

    def processed_reset
      @@processed = []
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
    attr_reader :attribute

    def initialize owner, ruby, opts = {}
      @owner = owner
      @opts = opts
      @ruby = ruby
      @name = ruby.name
      @scope = opts[:scope] || :instance
      @source = ruby.source_location
      if @source
        if @source[0] == __FILE__ &&
          ($module_hook_start..$module_hook_end).include?(@source[1])
          nm = @name.to_s
          if nm[-1] == '='
            nm = nm[0..-2]
          end
          nm = nm.intern
          if RDot.attr_list && RDot.attr_list[ruby.owner] &&
              RDot.attr_list[ruby.owner][@scope] &&
              RDot.attr_list[ruby.owner][@scope][nm]
            @source = RDot.attr_list[ruby.owner][@scope][nm][:source]
            @attribute = nm
          end
        end
        @file = @source[0]
        $:.each do |path|
          l = path.length
          if @file[0...l] == path
            @file = @file[l..-1]
            break
          end
        end
        @file = @file.escape
        @line = @source[1]
      end
      @signature = @name.to_s.escape
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
            @signature += "#{first && ' [' || ' [, '}#{n}]"
          when :rest
            @signature += "#{first && ' *' || ', *'}#{n}"
          when :block
            @signature += "#{first && ' &amp;' || ', &amp;'}#{n}"
          end
          first = nil
        end
      end
    end

    def <=> other
      @name <=> other.name
    end

  end

  class Module

    include Comparable

    attr_reader :name, :module
    attr_accessor :ancestors, :extensions
    attr_reader :instance_private_methods, :instance_protected_methods,
        :instance_public_methods, :class_private_methods,
        :class_protected_methods, :class_public_methods

    def initialize space, mod, opts = {}
      @space = space
      @opts = opts
      @module = mod
      @name = mod.name
      @instance_public_methods = {}
      @instance_protected_methods = {}
      @instance_private_methods = {}
      @class_public_methods = {}
      @class_protected_methods = {}
      @class_private_methods = {}
      @attributes = {}
      @constants = {}
      @ancestors = []
      @extensions = []
      @kind = Class === mod && (mod <= Exception && :exception || :class) ||
          :module
      if ! @opts[:no_init]
        if ! @opts[:hide_methods]
          mod.instance_methods(false).each do |m|
            m = mod.instance_method(m)
            @instance_public_methods[m.name] = RDot::Method.new self, m, @opts
          end
          mod.methods(false).each do |m|
            m = mod.method(m).unbind
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
              m = mod.method(m).unbind
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
              m = mod.method(m).unbind
              @class_private_methods[m.name] = RDot::Method.new self, m,
                  @opts.merge(:visibility => :private, :scope => :class)
            end
          end
        end
        if ! @opts[:hide_constants]
          mod.constants(false).each do |c|
            next if mod == Object && c == :Config
            @constants[c] = mod.const_get c
          end
        end
        @ancestors = mod.ancestors - [mod]
        @extensions = mod.singleton_class.ancestors - [mod.singleton_class]
        if Class === mod && mod.superclass
          @ancestors -= [mod.superclass] + mod.superclass.ancestors
          @extensions -= [mod.superclass.singleton_class] +
              mod.superclass.singleton_class.ancestors
        end
        dels = @ancestors.clone
        dels.each do |del|
          @ancestors -= del.ancestors - [del]
        end
        dels = @extensions.clone
        dels.each do |del|
          @extensions -= del.ancestors - [del]
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
      result = RDot::Module.new @space, @module,
          @opt.merge(:no_init => true, :preloaded => true)
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
      result.ancestors = @ancestors - other.ancestors
      result.extensions = @extensions - other.extensions
      if result.instance_public_methods.empty? &&
          result.instance_protected_methods.empty? &&
          result.instance_private_methods.empty? &&
          result.class_public_methods.empty? &&
          result.class_protected_methods.empty? &&
          result.class_private_methods.empty? &&
          result.constants.empty? && result.ancestors.empty? &&
          result.extensions.empty?
        nil
      else
        result
      end
    end

    def node_name
      "node_#{@module.inspect.tr('#<>() =,.;:', '_')}"
    end

    def node_color
      if @opts[:preloaded]
        case @kind
        when :exception
          @opts[:color_exception_preloaded] || 'chocolate'
        when :class
          @opts[:color_class_preloaded] || 'mediumseagreen'
        when :module
          @opts[:color_module_preloaded] || 'steelblue'
        end
      else
        case @kind
        when :exception
          @opts[:color_exception] || 'lightcoral'
        when :class
          @opts[:color_class] || 'mediumaquamarine'
        when :module
          @opts[:color_module] || 'skyblue'
        end
      end
    end

    def node_rows
      result = ''
      if !(@opts[:hide_constants] || @constants.empty?)
        c = @constants.map do |n, v|
          "#{n} &lt;#{v.class}&gt;".short(50)
        end
        result += '<TR>' +
            '<TD ROWSPAN="' + c.size.to_s + '" VALIGN="TOP">const</TD>' +
            '<TD COLSPAN="3">' + c.join('</TD></TR><TR><TD COLSPAN="3">') +
            '</TD></TR>'
      end
      if ! (@opts[:hide_methods] ||
            (@class_public_methods.empty? && @class_protected_methods.empty? &&
             @class_private_methods.empty?))
        public_attrs = []
        public_meths = []
        protected_attrs = []
        protected_meths = []
        private_attrs = []
        private_meths = []
        @class_public_methods.values.sort.each do |m|
          if @opts[:select_attributes] && m.attribute
            public_attrs << [m.attribute, m] unless public_attrs.include? m.attribute
          else
            public_meths << m
          end
        end
        @class_protected_methods.values.sort.each do |m|
          if @opts[:select_attributes] && m.attribute
            protected_attrs << [m.attribute, m] unless protected_attrs.include? m.attribute
          else
            protected_meths << m
          end
        end
        @class_private_methods.values.sort.each do |m|
          if @opts[:select_attributes] && m.attribute
            private_attrs << [m.attribute, m] unless private_attrs.include? m.attribute
          else
            private_meths << m
          end
        end
        rows = []
        rows += public_attrs.map do |a|
          acc = RDot.attr_list[@module][:class][a[0]][:access]
          "<TD>#{a[0].to_s.escape} #{acc}</TD><TD>#{a[1].file}</TD><TD>#{a[1].line}</TD>"
        end
        rows += public_meths.map do |m|
          "<TD>#{m.signature}</TD><TD>#{m.file}</TD><TD>#{m.line}</TD>"
        end
        rows += protected_attrs.map do |a|
          acc = RDot.attr_list[@module][:class][a[0]][:access]
          "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{a[0].to_s.escape} #{acc}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{a[1].file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{a[1].line}</TD>"
        end
        rows += protected_meths.map do |m|
          "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{m.signature}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{m.file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{m.line}</TD>"
        end
        rows += private_attrs.map do |a|
          acc = RDot.attr_list[@module][:class][a[0]][:access]
          "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{a[0].to_s.escape} #{acc}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{a[1].file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{a[1].line}</TD>"
        end
        rows += private_meths.map do |m|
          "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{m.signature}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{m.file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{m.line}</TD>"
        end
        result += '<TR>' +
            '<TD COLSPAN="' + rows.size.to_s + '" VALIGN="TOP">class</TD>' +
            rows.join('</TR><TR>') + '</TR>'
      end
      if ! (@opts[:hide_methods] ||
            (@instance_public_methods.empty? && @instance_protected_methods.empty? &&
             @instance_private_methods.empty?))
        public_attrs = []
        public_meths = []
        protected_attrs = []
        protected_meths = []
        private_attrs = []
        private_meths = []
        @instance_public_methods.values.sort.each do |m|
          if @opts[:select_attributes] && m.attribute
            public_attrs << [m.attribute, m] unless public_attrs.include? m.attribute
          else
            public_meths << m
          end
        end
        @instance_protected_methods.values.sort.each do |m|
          if @opts[:select_attributes] && m.attribute
            protected_attrs << [m.attribute, m] unless protected_attrs.include? m.attribute
          else
            protected_meths << m
          end
        end
        @instance_private_methods.values.sort.each do |m|
          if @opts[:select_attributes] && m.attribute
            private_attrs << [m.attribute, m] unless private_attrs.include? m.attribute
          else
            private_meths << m
          end
        end
        rows = []
        rows += public_attrs.map do |a|
          acc = RDot.attr_list[@module][:instance][a[0]][:access]
          "<TD>#{a[0].to_s.escape} #{acc}</TD><TD>#{a[1].file}</TD><TD>#{a[1].line}</TD>"
        end
        rows += public_meths.map do |m|
          "<TD>#{m.signature}</TD><TD>#{m.file}</TD><TD>#{m.line}</TD>"
        end
        rows += protected_attrs.map do |a|
          acc = RDot.attr_list[@module][:instance][a[0]][:access]
          "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{a[0].to_s.escape} #{acc}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{a[1].file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{a[1].line}</TD>"
        end
        rows += protected_meths.map do |m|
          "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{m.signature}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{m.file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_protected] || '#EEEEEE'}\">#{m.line}</TD>"
        end
        rows += private_attrs.map do |a|
          acc = RDot.attr_list[@module][:instance][a[0]][:access]
          "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{a[0].to_s.escape} #{acc}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{a[1].file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{a[1].line}</TD>"
        end
        rows += private_meths.map do |m|
          "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{m.signature}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{m.file}</TD>" +
              "<TD BGCOLOR=\"#{@opts[:color_private] || '#DDDDDD'}\">#{m.line}</TD>"
        end
        result += '<TR>' +
            '<TD COLSPAN="' + rows.size.to_s + '" VALIGN="TOP">instance</TD>' +
            rows.join('</TR><TR>') + '</TR>'
      end
      result
    end

    def to_dot out = ''
      if ! RDot.processed? self
        RDot.processed_push self
        fname = @opts[:name_fontname] || @opts[:fontname] || 'monospace'
        fsize = @opts[:name_fontsize] || @opts[:fontsize] || 9
        out.echo '  ', node_name, '['
        out.echo '    label=<'
        out.echo '      <TABLE CELLBORDER="0" CELLSPACING="0">'
        out.echo '       <TR>'
        out.echo '        <TD ALIGN="RIGHT" BGCOLOR="', node_color, '">'
        out.echo '         <FONT FACE="', fname, '" POINT-SIZE="', fsize, '">'
        out.echo '          ', @kind
        out.echo '         </FONT>'
        out.echo '        </TD>'
        out.echo '        <TD COLSPAN="3" ALIGN="LEFT" BGCOLOR="', node_color, '">'
        out.echo '         <FONT FACE="', fname, '" POINT-SIZE="', fsize, '">'
        out.echo '          ', @module.inspect.escape
        out.echo '         </FONT>'
        out.echo '        </TD>'
        out.echo '       </TR>'
        out.echo    node_rows
        out.echo '      </TABLE>'
        out.echo '    >'
        out.echo '  ];'
        if Class === @module && @module.superclass
          sup =  @space[@module.superclass] ||
              RDot::Module.new(@space, @module.superclass,
                               @opts.merge(:no_init => true,
                                           :preloaded => true))
          sup.to_dot out
          out.echo '  ', sup.node_name, ' -> ', node_name, '[color="',
              @opts[:color_inherited] || 'steelblue', '", weight=1];'
        end
        @ancestors.each do |a|
          anc = @space[a] ||
              RDot::Module.new(@space, a,
                               @opts.merge(:no_init => true,
                                           :preloaded => true))
          anc.to_dot out
          out.echo '  ', anc.node_name, ' -> ', node_name,
              '[color="', @opts[:color_included] || 'skyblue', '", weight=10];'
        end
        @extensions.each do |e|
          ext = @space[e] ||
              RDot::Module.new(@space, e,
                               @opts.merge(:no_init => true,
                                           :preloaded => true))
          ext.to_dot out
          out.echo '  ', ext.node_name, ' -> ', node_name, '[color="',
              @opts[:color_extended] || 'olivedrab', '", weight=10];'
        end
        if (ns = @module.namespace)
          nsm = @space[ns] ||
              RDot::Module.new(@space, ns,
                               @opts.merge(:no_init => true,
                                           :preloaded => true))
          nsm.to_dot out
          out.echo '  ', nsm.node_name, ' -> ', node_name,
              '[color="', @opts[:color_nested] || '#AAAAAA', '", weight=100]'
        end
      end
    end

    private :node_color, :node_rows
    protected :add_method, :add_constant, :node_name

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
            @modules[m] = RDot::Module.new self, m, @opts
          end
        end
      end
    end

    def [] mod
      @modules[mod]
    end

    def []= mod, m
      @modules[mod] = m
    end

    def each &block
      @modules.each &block
    end

    def sub other
      result = RDot::Space.new @opts.merge(:no_init => true)
      @modules.each do |m|
        sm = m.sub other[m.module]
        result[m.module] = sm if sm
      end
      result
    end

    def title
      return @opts[:title] if @opts[:title]
      return 'RDot: ' + @opts[:includes].join(', ') if @opts[:includes]
      'RDot Graph'
    end

    def to_dot out = ''
      if ! out.respond_to?(:<<)
        raise 'Invalid output.'
      end
      out.echo 'digraph graph_RDot{'
      out.echo '  graph['
      out.echo '    rankdir=LR,'
      out.echo '    splines=true,'
      out.echo '    fontname="', @opts[:caption_fontname] || 'sans-serif', '",'
      out.echo '    fontsize=', @opts[:caption_fontsize] || 24, ','
      out.echo '    labelloc=t,'
      out.echo '    label="', title, '"'
      out.echo '  ];'
      out.echo '  node['
      out.echo '    shape=plaintext,'
      out.echo '    fontname="', @opts[:fontname] || 'monospace', '",'
      out.echo '    fontsize=', @opts[:fontsize] || 9
      out.echo '  ];'
      out.echo '  edge[dir=back, arrowtail=vee];'
      out.echo
      RDot.processed_reset
      @modules.each do |_, m|
        m.to_dot out
      end
      out.echo
      out.echo '}'
    end

    private :title
    protected :[]=

  end

end
