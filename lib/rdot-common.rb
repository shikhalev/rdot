# encoding: utf-8

module RDot

  VERSION = '1.1.1'

  class << self

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

  end

end
