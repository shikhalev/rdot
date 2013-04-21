# encoding: utf-8

module RDot

  VERSION = '0.99.0'

  class Module

    include Comparable

    def initialize mod, opts = {}
      @opts = opts
      @module = mod
    end

    def <=> other
      to_s <=> other.to_s
    end

    def sub other
    end

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
              exclude_classes.each { |e| throw :module if m <= e }
            end
            if (exclude_namespaces = @opts[:exclude_namespaces])
              exclude_namespaces.each { |e| throw :module if m.in? e }
            end
            @modules[m.name] = RDot::Module.new m, opts
          end
        end
      end
    end

    def each &block
      @modules.each &block
    end

    def sub other
    end

  end

end
